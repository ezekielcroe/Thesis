// ModalEditor.swift — Thesis
// Core modal editor: key handling, navigation, verb-object, visual mode,
// move command, repeat (.), redo, gg/G, improved insert tracking

import SwiftUI
import AppKit

struct ModalEditor: View {
    @Binding var document: Document
    var onNavigateToAnnotation: ((Annotation) -> Void)?
    
    // Mode state
    @State private var mode: EditorMode = .freeText
    @State private var pendingVerb: PendingVerb?
    @State private var insertContext: InsertContext?
    
    // Cursor and selection
    @State private var cursorPosition: Int = 0
    @State private var visualAnchor: Int = 0
    @State private var selectionRange: NSRange?
    
    // Highlights
    @State private var highlightRange: NSRange?
    @State private var flashRange: NSRange?
    
    // Move mode state
    @State private var movePayload: TextUnit?        // The text being moved
    @State private var movePayloadType: TextUnitType?
    
    // Version control
    @State private var diffChanges: [DiffChange] = []
    @State private var currentDiffIndex: Int = 0
    
    // Sheets
    @State private var showingFirstDraftSheet = false
    @State private var showingSaveSheet = false
    @State private var showingAnnotationSheet = false
    @State private var showingBranchSheet = false
    @State private var showingMergeSheet = false
    @State private var annotationAnchorText: String = ""
    @State private var annotationPosition: Int = 0
    
    // Stats (debounced)
    @State private var stats: TextAnalyzer.Stats = .init(paragraphCount: 0, sentenceCount: 0, wordCount: 0)
    @State private var statsTimer: Timer?
    
    // Tracking
    @State private var undoStack = UndoStack()
    @State private var pendingChangeTracker = PendingChangeTracker()
    @State private var lastCommand: LastCommand?
    @State private var analyzer = CachedTextAnalyzer()
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                EditorTextView(
                    text: $document.currentContent,
                    mode: $mode,
                    cursorPosition: $cursorPosition,
                    highlightRange: $highlightRange,
                    flashRange: $flashRange,
                    selectionRange: $selectionRange,
                    diffChanges: $diffChanges,
                    onTextChange: { handleTextChange() },
                    onKeyPress: { key, mods in handleKeyPress(key, modifiers: mods) },
                    onModeChange: { newMode in handleModeChange(newMode) }
                )
                .border(mode.borderColor, width: 3)
                
                if let verb = pendingVerb {
                    VerbHelpOverlay(verb: verb.verb)
                        .padding(8)
                        .transition(.opacity)
                }
                
                if movePayload != nil {
                    MoveIndicator()
                        .padding(8)
                        .transition(.opacity)
                }
            }
            
            StatusBar(
                mode: mode,
                pendingVerb: pendingVerb?.verb,
                stats: stats,
                draftInfo: draftInfo,
                hasUnsavedChanges: document.hasUnsavedChanges,
                branchInfo: branchInfo,
                diffInfo: currentDiffInfo,
                undoPreview: undoStack.undoPreview,
                annotationCount: document.unresolvedAnnotations.count,
                sessionSummary: document.sessionChangeSummary
            )
        }
        .onAppear {
            DispatchQueue.main.async { debouncedUpdateStats() }
            if !document.drafts.isEmpty { mode = .normal }
        }
        .sheet(isPresented: $showingFirstDraftSheet) {
            FirstDraftSheet(
                onSave: { name in
                    document.saveFirstDraft(name: name)
                    mode = .normal
                    showingFirstDraftSheet = false
                },
                onCancel: {
                    mode = .freeText
                    showingFirstDraftSheet = false
                }
            )
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveDraftSheet(
                sessionSummary: document.sessionChangeSummary,
                onSave: { name, comment in
                    document.saveDraft(name: name, comment: comment)
                    mode = .normal
                    showingSaveSheet = false
                    debouncedUpdateStats()
                }
            )
        }
        .sheet(isPresented: $showingAnnotationSheet) {
            AnnotationSheet(
                anchorText: annotationAnchorText,
                onSave: { noteText, category in
                    document.addAnnotation(
                        text: noteText,
                        anchorText: annotationAnchorText,
                        position: annotationPosition,
                        category: category
                    )
                    showingAnnotationSheet = false
                    mode = .normal
                }
            )
        }
        .sheet(isPresented: $showingBranchSheet) {
            BranchSheet(
                document: document,
                onCreateBranch: { name, desc in
                    document.createBranch(name: name, description: desc)
                    showingBranchSheet = false
                    mode = .normal
                },
                onSwitchBranch: { name in
                    document.switchBranch(to: name)
                    showingBranchSheet = false
                    mode = .normal
                    analyzer.invalidate()
                    debouncedUpdateStats()
                },
                onDeleteBranch: { name in
                    document.deleteBranch(name)
                }
            )
        }
        .sheet(isPresented: $showingMergeSheet) {
            MergeSheet(
                document: document,
                onMerge: { sourceBranch in
                    if let result = document.mergeBranch(sourceName: sourceBranch) {
                        if !result.isClean {
                            // TODO: conflict resolution UI
                        }
                    }
                    showingMergeSheet = false
                    mode = .normal
                    analyzer.invalidate()
                    debouncedUpdateStats()
                }
            )
        }
    }
    
    // MARK: - Computed Properties
    
    private var draftInfo: String {
        if let head = document.currentBranchHead {
            return "\(document.activeBranchName): \(head.name)"
        }
        return "No draft saved"
    }
    
    private var branchInfo: String? {
        if document.branches.count > 1 {
            return "[\(document.activeBranchName)]"
        }
        return nil
    }
    
    private var currentDiffInfo: EditorDiffInfo? {
        guard mode == .comp, !diffChanges.isEmpty else { return nil }
        let changeIndices = DiffGenerator.getChangeIndices(in: diffChanges)
        guard !changeIndices.isEmpty else { return nil }
        let currentChangeArrayIndex = changeIndices.firstIndex(of: currentDiffIndex) ?? 0
        return EditorDiffInfo(
            currentIndex: currentChangeArrayIndex,
            totalChanges: changeIndices.count,
            currentChange: currentDiffIndex < diffChanges.count ? diffChanges[currentDiffIndex] : nil
        )
    }
    
    // MARK: - Updates
    
    private func debouncedUpdateStats() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            DispatchQueue.main.async {
                self.stats = self.analyzer.stats(for: self.document.currentContent)
            }
        }
    }
    
    private func handleTextChange() {
        analyzer.invalidate()
        debouncedUpdateStats()
        switch mode {
        case .insert, .freeText:
            document.scheduleWorkingDraftUpdate()
        default: break
        }
    }
    
    private func handleModeChange(_ newMode: EditorMode) {
        if case .insert = mode, !(newMode == mode) {
            completeInsertMode()
        }
        mode = newMode
        if case .normal = newMode {
            insertContext = nil
            pendingVerb = nil
            highlightRange = nil
        }
    }
    
    // MARK: - Key Dispatch
    
    private func handleKeyPress(_ characters: String, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if characters == "d" && mode == .normal { enterCompMode(); return }
            if characters == "s" && mode == .normal {
                if document.currentBranchHead != nil { showingSaveSheet = true }
                return
            }
            if characters == "z" && mode == .normal { executeUndo(); return }
            return
        }
        
        if modifiers.contains(.control) {
            if characters == "r" && mode == .normal { executeRedo(); return }
            return
        }
        
        switch mode {
        case .freeText:                handleFreeTextKey(characters)
        case .normal:                  handleNormalKey(characters, modifiers: modifiers)
        case .insert(let ctx):         handleInsertKey(characters, context: ctx)
        case .visual:                  handleVisualKey(characters, modifiers: modifiers)
        case .command(let cur):        handleCommandKey(characters, current: cur)
        case .comp:                    handleCompKey(characters)
        }
    }
    
    // MARK: - Free Text Mode
    
    private func handleFreeTextKey(_ chars: String) {
        if chars == "\u{1B}" && !document.currentContent.isEmpty {
            showingFirstDraftSheet = true
        }
    }
    
    // MARK: - Insert Mode
    
    private func handleInsertKey(_ chars: String, context: InsertContext) {
        if chars == "\u{1B}" {
            completeInsertMode()
            return
        }
        guard context != .freeform else { return }
        if let char = chars.first, context.autoExitCharacters.contains(char) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.completeInsertMode()
            }
        }
        if context.exitsOnDoubleNewline && chars == "\n" {
            // Check if previous character was also newline
            let text = document.currentContent
            let nsText = text as NSString
            if cursorPosition > 0 && cursorPosition <= nsText.length {
                let prevChar = nsText.substring(with: NSRange(location: cursorPosition - 1, length: 1))
                if prevChar == "\n" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.completeInsertMode()
                    }
                }
            }
        }
    }
    
    private func completeInsertMode() {
        if pendingChangeTracker.hasPending {
            if let completed = pendingChangeTracker.completeChange(
                currentContent: document.currentContent,
                cursorPosition: cursorPosition
            ) {
                document.recordChange(completed)
                
                // Build undo operation for the insert phase
                if let startPos = pendingChangeTracker.insertStartPosition {
                    let length = cursorPosition - startPos
                    if length > 0 {
                        let nsText = document.currentContent as NSString
                        let safeRange = TextAnalyzer.safeRange(
                            NSRange(location: startPos, length: length),
                            in: nsText.length
                        )
                        let insertedText = nsText.substring(with: safeRange)
                        let operation = InsertOperation(
                            position: startPos,
                            insertedText: insertedText,
                            semanticChange: completed
                        )
                        undoStack.push(operation)
                    }
                }
            }
        }
        mode = .normal
        insertContext = nil
        pendingVerb = nil
        highlightRange = nil
        movePayload = nil
        movePayloadType = nil
    }
    
    // MARK: - Normal Mode
    
    private func handleNormalKey(_ chars: String, modifiers: NSEvent.ModifierFlags) {
        guard let rawChar = chars.first else { return }
        let char = String(rawChar)
        let isShift = modifiers.contains(.shift)
        
        // Move placement mode: j/k to position, Enter to confirm, ESC to cancel
        if let payload = movePayload, let payloadType = movePayloadType {
            handleMoveKey(char, payload: payload, payloadType: payloadType)
            return
        }
        
        // Pending verb → object
        if let verb = pendingVerb {
            if char == "\u{1B}" {
                pendingVerb = nil
                highlightRange = nil
                return
            }
            if let obj = parseObject(char.lowercased()) {
                updateLiveHighlightForObject(verb: verb.verb, object: obj)
            }
            executeVerbObject(verb: verb.verb, objectKey: char.lowercased(), isShift: isShift)
            pendingVerb = nil
            highlightRange = nil
            return
        }
        
        switch char.lowercased() {
        // Navigation
        case "h":
            if isShift { navigateSentence(forward: false) }
            else { navigateClause(forward: false) }
        case "l":
            if isShift { navigateSentence(forward: true) }
            else { navigateClause(forward: true) }
        case "j":
            if isShift { navigateLine(forward: true) }
            else { navigateParagraph(forward: true) }
        case "k":
            if isShift { navigateLine(forward: false) }
            else { navigateParagraph(forward: false) }
        case "w":
            navigateWord(forward: true)
        case "b":
            navigateWord(forward: false)
            
        // Jump to top/bottom
        case "g":
            if char == "g" { cursorPosition = 0; flashCursor() }
        case "G" where chars == "G":
            cursorPosition = (document.currentContent as NSString).length
            flashCursor()
            
        // Verbs
        case "d":
            if isShift { executeDeleteToEnd() }
            else { startPendingVerb(.delete) }
        case "c":
            if isShift { executeChangeToEnd() }
            else { startPendingVerb(.change) }
        case "r":
            if isShift { executeRefineToEnd() }
            else { startPendingVerb(.refine) }
        case "y":
            startPendingVerb(.yank)
        case "m":
            startPendingVerb(.markup)
        case "x":
            startPendingVerb(.move)
            
        // Direct actions
        case "i":
            startInsert(context: .freeform)
        case "a":
            executeAppendAfterSentence()
        case "o":
            executeOpenLineBelow()
        case "p":
            executePaste()
        case "u":
            executeUndo()
        case ".":
            repeatLastCommand()
            
        // Mode switches
        case "v":
            enterVisualMode()
        case ":":
            mode = .command("")
            
        default:
            break
        }
    }
    
    private func startPendingVerb(_ verb: EditVerb) {
        pendingVerb = PendingVerb(verb)
        updateLiveHighlight(for: verb)
    }
    
    /// Default highlight: sentence at cursor
    private func updateLiveHighlight(for verb: EditVerb) {
        if let sentence = analyzer.sentenceAt(cursorPosition, in: document.currentContent) {
            highlightRange = sentence.range
        }
    }
    
    /// Update highlight as user types the object key
    private func updateLiveHighlightForObject(verb: EditVerb, object: EditObject) {
        if let unit = resolveUnit(for: object) {
            highlightRange = unit.range
        }
    }
    
    // MARK: - Verb + Object Execution
    
    private func executeVerbObject(verb: EditVerb, objectKey: String, isShift: Bool) {
        guard let object = parseObject(objectKey) else { return }
        guard let unit = resolveUnit(for: object) else { return }
        
        lastCommand = LastCommand(verb: verb, object: object, insertedText: nil)
        
        switch verb {
        case .delete: executeDelete(unit: unit, unitType: objectTextUnitType(object))
        case .change: executeChange(unit: unit, unitType: objectTextUnitType(object), object: object)
        case .refine: executeRefine(unit: unit, unitType: objectTextUnitType(object), object: object)
        case .yank:   executeYank(unit: unit, unitType: objectTextUnitType(object))
        case .markup: executeMarkup(unit: unit, unitType: objectTextUnitType(object))
        case .move:   startMove(unit: unit, unitType: objectTextUnitType(object))
        }
    }
    
    private func parseObject(_ key: String) -> EditObject? {
        switch key {
        case "w": return .word
        case "b": return .wordBack
        case "c": return .clause
        case "s": return .sentence
        case "p": return .paragraph
        default:  return nil
        }
    }
    
    private func resolveUnit(for object: EditObject) -> TextUnit? {
        let text = document.currentContent
        let pos = cursorPosition
        switch object {
        case .word:      return analyzer.wordAt(pos, in: text)
        case .wordBack:  return analyzer.prevWord(from: pos, in: text)
        case .clause:    return analyzer.clauseAt(pos, in: text)
        case .sentence:  return analyzer.sentenceAt(pos, in: text)
        case .paragraph: return analyzer.paragraphAt(pos, in: text)
        }
    }
    
    private func objectTextUnitType(_ object: EditObject) -> TextUnitType {
        switch object {
        case .word, .wordBack: return .word
        case .clause:          return .clause
        case .sentence:        return .sentence
        case .paragraph:       return .paragraph
        }
    }
    
    private func objectInsertContext(_ object: EditObject) -> InsertContext {
        switch object {
        case .word, .wordBack: return .word
        case .clause:          return .clause
        case .sentence:        return .sentence
        case .paragraph:       return .paragraph
        }
    }
    
    // MARK: - Edit Operations
    
    private func executeDelete(unit: TextUnit, unitType: TextUnitType) {
        let range = unitType == .word
            ? TextAnalyzer.expandToTrailingSpace(unit.range, in: document.currentContent)
            : unit.range
        let change = SemanticChange(
            type: .deleted, unitType: unitType,
            beforeText: unit.text, position: cursorPosition,
            context: "deleted \(unitType.rawValue)"
        )
        highlightRangeBriefly(range) {
            self.performDelete(range: range, change: change)
        }
    }
    
    private func executeChange(unit: TextUnit, unitType: TextUnitType, object: EditObject) {
        let range = unitType == .word
            ? TextAnalyzer.expandToTrailingSpace(unit.range, in: document.currentContent)
            : unit.range
        let ctx = objectInsertContext(object)
        pendingChangeTracker.startChange(
            type: .replaced, unitType: unitType,
            beforeText: unit.text, position: range.location,
            context: "\(unitType.rawValue) replacement"
        )
        highlightRangeBriefly(range) {
            self.performDelete(range: range, change: nil)
            self.mode = .insert(ctx)
            self.insertContext = ctx
        }
    }
    
    private func executeRefine(unit: TextUnit, unitType: TextUnitType, object: EditObject) {
        let range = unitType == .word
            ? TextAnalyzer.expandToTrailingSpace(unit.range, in: document.currentContent)
            : unit.range
        let ctx = objectInsertContext(object)
        pendingChangeTracker.startChange(
            type: .refined, unitType: unitType,
            beforeText: unit.text, position: range.location,
            context: "\(unitType.rawValue) refinement"
        )
        highlightRangeBriefly(range) {
            self.performDelete(range: range, change: nil)
            self.mode = .insert(ctx)
            self.insertContext = ctx
        }
    }
    
    private func executeYank(unit: TextUnit, unitType: TextUnitType) {
        document.yankRegister = unit.text
        flashUnit(unit)
    }
    
    private func executeMarkup(unit: TextUnit, unitType: TextUnitType) {
        annotationAnchorText = unit.text
        annotationPosition = unit.range.location
        flashUnit(unit)
        showingAnnotationSheet = true
    }
    
    // MARK: - Move Operations
    
    private func startMove(unit: TextUnit, unitType: TextUnitType) {
        movePayload = unit
        movePayloadType = unitType
        flashUnit(unit)
        // User now presses j/k to navigate to target, Enter to confirm
    }
    
    private func handleMoveKey(_ char: String, payload: TextUnit, payloadType: TextUnitType) {
        switch char {
        case "j":
            navigateParagraph(forward: true)
        case "k":
            navigateParagraph(forward: false)
        case "\r", "\n":
            confirmMove(payload: payload, payloadType: payloadType)
        case "\u{1B}":
            movePayload = nil
            movePayloadType = nil
        default:
            break
        }
    }
    
    private func confirmMove(payload: TextUnit, payloadType: TextUnitType) {
        let destination = cursorPosition
        let nsText = document.currentContent as NSString
        let movedText = payload.text
        
        guard payload.range.location + payload.range.length <= nsText.length else {
            movePayload = nil
            movePayloadType = nil
            return
        }
        
        let change = SemanticChange(
            type: .moved, unitType: payloadType,
            beforeText: movedText,
            position: payload.range.location,
            context: "moved \(payloadType.rawValue) to position \(destination)"
        )
        
        let operation = MoveOperation(
            sourceRange: payload.range,
            movedText: movedText,
            destinationPosition: destination,
            cursorBefore: payload.range.location,
            semanticChange: change
        )
        
        // Execute the move
        var content = document.currentContent
        let _ = operation.redo(content: &content)
        document.currentContent = content
        
        undoStack.push(operation)
        document.recordChange(change)
        
        movePayload = nil
        movePayloadType = nil
        handleTextChange()
    }
    
    // MARK: - Shift Variants (to end of sentence)
    
    private func executeDeleteToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        let change = SemanticChange(
            type: .deleted, unitType: .sentence,
            beforeText: rest.text, position: cursorPosition,
            context: "deleted to end"
        )
        highlightRangeBriefly(rest.range) {
            self.performDelete(range: rest.range, change: change)
        }
    }
    
    private func executeChangeToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        pendingChangeTracker.startChange(
            type: .replaced, unitType: .sentence,
            beforeText: rest.text, position: rest.range.location,
            context: "change to end"
        )
        highlightRangeBriefly(rest.range) {
            self.performDelete(range: rest.range, change: nil)
            self.mode = .insert(.sentence)
            self.insertContext = .sentence
        }
    }
    
    private func executeRefineToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        pendingChangeTracker.startChange(
            type: .refined, unitType: .sentence,
            beforeText: rest.text, position: rest.range.location,
            context: "refine to end"
        )
        highlightRangeBriefly(rest.range) {
            self.performDelete(range: rest.range, change: nil)
            self.mode = .insert(.sentence)
            self.insertContext = .sentence
        }
    }
    
    // MARK: - Direct Actions
    
    private func executeAppendAfterSentence() {
        let text = document.currentContent
        if let sentence = analyzer.sentenceAt(cursorPosition, in: text) {
            cursorPosition = sentence.endLocation
        }
        pendingChangeTracker.startChange(
            type: .added, unitType: .sentence,
            beforeText: nil, position: cursorPosition,
            context: "appended sentence"
        )
        mode = .insert(.sentence)
        insertContext = .sentence
    }
    
    private func executeOpenLineBelow() {
        let nsText = document.currentContent as NSString
        let range = NSRange(location: cursorPosition, length: nsText.length - cursorPosition)
        let nextNewline = nsText.range(of: "\n", options: [], range: range)
        let insertPos = nextNewline.location != NSNotFound ? nextNewline.location + 1 : nsText.length
        
        document.currentContent = (document.currentContent as NSString).replacingCharacters(
            in: NSRange(location: insertPos, length: 0), with: "\n"
        )
        cursorPosition = insertPos + 1
        
        pendingChangeTracker.startChange(
            type: .added, unitType: .paragraph,
            beforeText: nil, position: cursorPosition,
            context: "opened new line"
        )
        mode = .insert(.line)
        insertContext = .line
        handleTextChange()
    }
    
    private func executePaste() {
        guard let yanked = document.yankRegister, !yanked.isEmpty else { return }
        let nsText = document.currentContent as NSString
        let insertPos = min(cursorPosition, nsText.length)
        let change = SemanticChange(
            type: .added, unitType: .sentence,
            afterText: yanked, position: insertPos,
            context: "pasted from yank"
        )
        let operation = InsertOperation(position: insertPos, insertedText: yanked, semanticChange: change)
        document.currentContent = nsText.replacingCharacters(
            in: NSRange(location: insertPos, length: 0), with: yanked
        )
        cursorPosition = insertPos + yanked.count
        undoStack.push(operation)
        document.recordChange(change)
        handleTextChange()
    }
    
    private func executeUndo() {
        if let result = undoStack.undo(content: &document.currentContent) {
            cursorPosition = result.cursor
            if let change = result.change { document.removeLastChange(matching: change) }
            handleTextChange()
        }
    }
    
    private func executeRedo() {
        if let result = undoStack.redo(content: &document.currentContent) {
            cursorPosition = result.cursor
            if let change = result.change { document.reAddChange(change) }
            handleTextChange()
        }
    }
    
    private func repeatLastCommand() {
        guard let last = lastCommand else { return }
        guard let object = last.object else { return }
        guard let unit = resolveUnit(for: object) else { return }
        
        switch last.verb {
        case .delete: executeDelete(unit: unit, unitType: objectTextUnitType(object))
        case .change: executeChange(unit: unit, unitType: objectTextUnitType(object), object: object)
        case .refine: executeRefine(unit: unit, unitType: objectTextUnitType(object), object: object)
        case .yank:   executeYank(unit: unit, unitType: objectTextUnitType(object))
        case .markup: executeMarkup(unit: unit, unitType: objectTextUnitType(object))
        case .move:   startMove(unit: unit, unitType: objectTextUnitType(object))
        }
    }
    
    // MARK: - Visual Mode
    
    private func enterVisualMode() {
        visualAnchor = cursorPosition
        selectionRange = NSRange(location: cursorPosition, length: 0)
        mode = .visual(.character)
    }
    
    private func updateVisualSelection() {
        let start = min(visualAnchor, cursorPosition)
        let end = max(visualAnchor, cursorPosition)
        selectionRange = NSRange(location: start, length: end - start)
    }
    
    /// Snap visual selection to unit boundaries
    private func snapSelectionToUnit(_ granularity: VisualGranularity) {
        let text = document.currentContent
        let start = min(visualAnchor, cursorPosition)
        let end = max(visualAnchor, cursorPosition)
        
        var snappedStart = start
        var snappedEnd = end
        
        switch granularity {
        case .word:
            if let startWord = analyzer.wordAt(start, in: text) {
                snappedStart = startWord.range.location
            }
            if let endWord = analyzer.wordAt(end, in: text) {
                snappedEnd = endWord.endLocation
            }
        case .sentence:
            if let startSent = analyzer.sentenceAt(start, in: text) {
                snappedStart = startSent.range.location
            }
            if let endSent = analyzer.sentenceAt(end, in: text) {
                snappedEnd = endSent.endLocation
            }
        case .paragraph:
            if let startPara = analyzer.paragraphAt(start, in: text) {
                snappedStart = startPara.range.location
            }
            if let endPara = analyzer.paragraphAt(end, in: text) {
                snappedEnd = endPara.endLocation
            }
        case .character:
            break
        }
        
        selectionRange = NSRange(location: snappedStart, length: snappedEnd - snappedStart)
    }
    
    private func handleVisualKey(_ chars: String, modifiers: NSEvent.ModifierFlags) {
        guard let rawChar = chars.first else { return }
        let char = String(rawChar)
        let isShift = modifiers.contains(.shift)
        
        switch char.lowercased() {
        case "\u{1B}":
            selectionRange = nil
            mode = .normal
            
        // Navigation
        case "h":
            if isShift { navigateSentence(forward: false) }
            else { navigateClause(forward: false) }
            updateVisualSelection()
        case "l":
            if isShift { navigateSentence(forward: true) }
            else { navigateClause(forward: true) }
            updateVisualSelection()
        case "j":
            if isShift { navigateLine(forward: true) }
            else { navigateParagraph(forward: true) }
            updateVisualSelection()
        case "k":
            if isShift { navigateLine(forward: false) }
            else { navigateParagraph(forward: false) }
            updateVisualSelection()
        case "w":
            navigateWord(forward: true)
            updateVisualSelection()
        case "b":
            navigateWord(forward: false)
            updateVisualSelection()
            
        // Snap selection to semantic boundaries
        case "s":
            mode = .visual(.sentence)
            snapSelectionToUnit(.sentence)
        case "p" where selectionRange == nil || selectionRange?.length == 0:
            mode = .visual(.paragraph)
            snapSelectionToUnit(.paragraph)
            
        // Actions
        case "d":
            executeVisualAction(.deleted)
        case "c":
            executeVisualAction(.replaced)
        case "r":
            executeVisualAction(.refined)
        case "y":
            executeVisualYank()
        case "m":
            executeVisualMarkup()
            
        default: break
        }
    }
    
    private func executeVisualAction(_ type: SemanticChangeType) {
        guard let range = selectionRange, range.length > 0 else { return }
        let nsText = document.currentContent as NSString
        let selectedText = nsText.substring(with: range)
        
        if type == .deleted {
            let change = SemanticChange(
                type: .deleted, unitType: .sentence,
                beforeText: selectedText, position: range.location,
                context: "visual delete"
            )
            performDelete(range: range, change: change)
        } else {
            pendingChangeTracker.startChange(
                type: type, unitType: .sentence,
                beforeText: selectedText, position: range.location,
                context: "visual \(type.rawValue)"
            )
            performDelete(range: range, change: nil)
            mode = .insert(.sentence)
            insertContext = .sentence
        }
        selectionRange = nil
        if type == .deleted { mode = .normal }
    }
    
    private func executeVisualYank() {
        guard let range = selectionRange, range.length > 0 else { return }
        let nsText = document.currentContent as NSString
        document.yankRegister = nsText.substring(with: range)
        selectionRange = nil
        mode = .normal
    }
    
    private func executeVisualMarkup() {
        guard let range = selectionRange, range.length > 0 else { return }
        let nsText = document.currentContent as NSString
        annotationAnchorText = nsText.substring(with: range)
        annotationPosition = range.location
        selectionRange = nil
        mode = .normal
        showingAnnotationSheet = true
    }
    
    // MARK: - Command Mode
    
    private func handleCommandKey(_ chars: String, current: String) {
        guard let char = chars.first else { return }
        if char == "\u{1B}" { mode = .normal; return }
        if char == "\r" || char == "\n" { executeCommand(current); return }
        if char == "\u{7F}" {
            if current.isEmpty { mode = .normal }
            else { mode = .command(String(current.dropLast())) }
            return
        }
        mode = .command(current + String(char))
    }
    
    private func executeCommand(_ cmd: String) {
        let trimmed = cmd.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        
        switch lower {
        case "comp", "diff":
            enterCompMode()
        case "save", "commit":
            if document.currentBranchHead != nil { showingSaveSheet = true }
            mode = .normal
        case "hist", "log", "history":
            mode = .normal
        case "notes", "anno":
            mode = .normal
        case "branch", "branches", "explore":
            showingBranchSheet = true
            mode = .normal
        case "merge", "combine":
            showingMergeSheet = true
            mode = .normal
        case "help":
            mode = .normal
        default:
            // Check for :branch <name>
            if lower.hasPrefix("branch ") {
                let name = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    document.createBranch(name: name)
                }
            }
            // Check for :checkout <name>
            else if lower.hasPrefix("checkout ") {
                let name = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    document.switchBranch(to: name)
                    analyzer.invalidate()
                    debouncedUpdateStats()
                }
            }
            mode = .normal
        }
    }
    
    // MARK: - Comp Mode
    
    private func enterCompMode() {
        guard let headDraft = document.currentBranchHead else { mode = .normal; return }
        diffChanges = DiffGenerator.generateDiff(
            from: headDraft.content,
            to: document.currentContent,
            withChanges: document.sessionChanges
        )
        currentDiffIndex = 0
        mode = .comp
        if let first = DiffGenerator.getChangeIndices(in: diffChanges).first {
            currentDiffIndex = first
            if currentDiffIndex < diffChanges.count {
                cursorPosition = diffChanges[currentDiffIndex].range.location
            }
        }
    }
    
    private func handleCompKey(_ chars: String) {
        guard let char = chars.first else { return }
        switch char {
        case "\u{1B}":
            diffChanges = []
            mode = .normal
        case "n":
            if let next = DiffGenerator.findNextChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = next
                navigateToCurrentDiffChange()
            }
        case "p":
            if let prev = DiffGenerator.findPreviousChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = prev
                navigateToCurrentDiffChange()
            }
        default: break
        }
    }
    
    private func navigateToCurrentDiffChange() {
        guard currentDiffIndex < diffChanges.count else { return }
        let c = diffChanges[currentDiffIndex]
        cursorPosition = (c.type == .deletion ? c.displayRange?.location : c.range.location) ?? 0
    }
    
    // MARK: - Navigation
    
    private func navigateWord(forward: Bool) {
        let text = document.currentContent
        if forward {
            if let next = analyzer.nextWord(from: cursorPosition, in: text) {
                cursorPosition = next.range.location
            } else {
                cursorPosition = (text as NSString).length
            }
        } else {
            if let prev = analyzer.prevWord(from: cursorPosition, in: text) {
                cursorPosition = prev.range.location
            } else {
                cursorPosition = 0
            }
        }
        flashCursor()
    }
    
    private func navigateClause(forward: Bool) {
        let clauses = analyzer.clauses(in: document.currentContent)
        if forward {
            if let next = clauses.first(where: { $0.range.location > cursorPosition }) {
                cursorPosition = next.range.location
            }
        } else {
            if let prev = clauses.last(where: { $0.range.location < cursorPosition }) {
                cursorPosition = prev.range.location
            }
        }
        flashCursor()
    }
    
    private func navigateSentence(forward: Bool) {
        let text = document.currentContent
        if forward {
            if let next = analyzer.nextSentence(from: cursorPosition, in: text) {
                cursorPosition = next.range.location
            }
        } else {
            if let prev = analyzer.prevSentence(from: cursorPosition, in: text) {
                cursorPosition = prev.range.location
            }
        }
        flashCursor()
    }
    
    private func navigateParagraph(forward: Bool) {
        let nsText = document.currentContent as NSString
        if forward {
            let range = NSRange(location: cursorPosition, length: nsText.length - cursorPosition)
            let result = nsText.range(of: "\n\n", options: [], range: range)
            cursorPosition = result.location != NSNotFound
                ? result.location + result.length
                : nsText.length
        } else {
            let range = NSRange(location: 0, length: cursorPosition)
            let result = nsText.range(of: "\n\n", options: .backwards, range: range)
            if result.location != NSNotFound {
                if cursorPosition == result.location + result.length {
                    let subRange = NSRange(location: 0, length: result.location)
                    let prev = nsText.range(of: "\n\n", options: .backwards, range: subRange)
                    cursorPosition = prev.location != NSNotFound ? prev.location + prev.length : 0
                } else {
                    cursorPosition = result.location + result.length
                }
            } else {
                cursorPosition = 0
            }
        }
        flashCursor()
    }
    
    private func navigateLine(forward: Bool) {
        if forward {
            cursorPosition = TextAnalyzer.getNextLineStart(from: cursorPosition, in: document.currentContent)
        } else {
            cursorPosition = TextAnalyzer.getPreviousLineStart(from: cursorPosition, in: document.currentContent)
        }
        flashCursor()
    }
    
    // MARK: - Insert Helpers
    
    private func startInsert(context: InsertContext) {
        pendingChangeTracker.startChange(
            type: .added, unitType: .word,
            beforeText: nil, position: cursorPosition,
            context: "insert"
        )
        mode = .insert(context)
        insertContext = context
        pendingVerb = nil
        highlightRange = nil
    }
    
    // MARK: - Core Helpers
    
    private func performDelete(range: NSRange, change: SemanticChange?) {
        let nsText = document.currentContent as NSString
        let safeRange = TextAnalyzer.safeRange(range, in: nsText.length)
        guard safeRange.length > 0 else { return }
        
        let deletedText = nsText.substring(with: safeRange)
        let afterContent = nsText.replacingCharacters(in: safeRange, with: "")
        
        let operation = DeleteOperation(
            range: safeRange,
            deletedText: deletedText,
            cursorBefore: cursorPosition,
            semanticChange: change
        )
        undoStack.push(operation)
        
        document.currentContent = afterContent
        cursorPosition = safeRange.location
        if let change = change { document.recordChange(change) }
        handleTextChange()
    }
    
    private func highlightRangeBriefly(_ range: NSRange, completion: @escaping () -> Void) {
        highlightRange = range
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.highlightRange = nil
            completion()
        }
    }
    
    private func flashUnit(_ unit: TextUnit) {
        flashRange = unit.range
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.flashRange = nil }
    }
    
    private func flashCursor() {
        let text = document.currentContent
        guard !text.isEmpty else { return }
        let loc = TextAnalyzer.safePosition(cursorPosition, in: text)
        let len = loc < (text as NSString).length ? 1 : 0
        flashRange = NSRange(location: loc, length: len)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.flashRange = nil }
    }
}

// MARK: - Move Indicator

struct MoveIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.arrow.down")
            Text("MOVING — j/k to position, Enter to confirm, ESC to cancel")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.purple)
        .cornerRadius(6)
    }
}
