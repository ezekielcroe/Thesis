// EditorEngine.swift — Thesis
// Dedicated controller for Vim-style modal editing, text mutation, and change tracking.

import SwiftUI
import AppKit
import Combine

enum EditorSheet: Identifiable {
    case firstDraft
    case save
    case annotation(anchorText: String, position: Int)
    case citation(anchorText: String, insertPosition: Int)
    case branch
    case merge
    case log
    case help
    
    var id: String {
        switch self {
        case .firstDraft: return "firstDraft"
        case .save: return "save"
        case .annotation: return "annotation"
        case .citation: return "citation"
        case .branch: return "branch"
        case .merge: return "merge"
        case .log: return "log"
        case .help: return "help"
        }
    }
}

class EditorEngine: ObservableObject {
    // Core Dependencies
    let document: Document
    
    // Published View State
    @Published var mode: EditorMode = .freeText
    @Published var cursorPosition: Int = 0
    @Published var selectionRange: NSRange?
    @Published var highlightRange: NSRange?
    @Published var flashRange: NSRange?
    @Published var diffChanges: [DiffChange] = []
    
    // Overlay & Status State
    @Published var pendingVerb: PendingVerb?
    @Published var movePayload: TextUnit?
    @Published var stats: TextAnalyzer.Stats = .init(paragraphCount: 0, sentenceCount: 0, wordCount: 0)
    @Published var activeSheet: EditorSheet?
    
    // Search State
    @Published var searchMatches: [NSRange] = []
    @Published var currentSearchIndex: Int = 0
    
    // Argument Structure State
    @Published var pendingArgument: Bool = false
    
    // Internal Engine State
    private var insertContext: InsertContext?
    private var movePayloadType: TextUnitType?
    @Published var currentDiffIndex: Int = 0
    private var pendingG: Bool = false
    
    let undoStack = UndoStack()
    let pendingChangeTracker = PendingChangeTracker()
    private var lastCommand: LastCommand?
    let analyzer = CachedTextAnalyzer()
    private var statsTimer: Timer?
    
    init(document: Document) {
        self.document = document
        if !document.drafts.isEmpty {
            self.mode = .normal
        }
    }
    
    // MARK: - Core Updates
    
    func handleTextChange() {
        analyzer.invalidate()
        debouncedUpdateStats()
        
        switch mode {
        case .insert, .freeText:
            document.scheduleWorkingDraftUpdate()
        default: break
        }
    }
    
    func handleModeChange(_ newMode: EditorMode) {
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
    
    private func debouncedUpdateStats() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.stats = self.analyzer.stats(for: self.document.currentContent)
            }
        }
    }
    
    // MARK: - Key Dispatch
    
    func handleKeyPress(_ characters: String, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if characters == "d" && mode == .normal { enterCompMode(); return }
            if characters == "s" && mode == .normal {
                if document.currentBranchHead != nil { activeSheet = .save }
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
        case .search(let cur):         handleSearchKey(characters, current: cur)
        }
    }
    
    // MARK: - Free Text Mode
    
    private func handleFreeTextKey(_ chars: String) {
        if chars == "\u{1B}" && !document.currentContent.isEmpty {
            activeSheet = .firstDraft
        }
    }
    
    // MARK: - Insert Mode
    
    private func handleInsertKey(_ chars: String, context: InsertContext) {
        if chars == "\u{1B}" {
            completeInsertMode()
            return
        }
        
        guard context != .freeform else { return }
        
        let nsText = document.currentContent as NSString
        
        switch context {
        case .word:
            if chars == " " {
                scheduleAutoExit()
            }
            
        case .sentence:
            if chars == "." || chars == "!" || chars == "?" {
                scheduleAutoExit()
            }
            
        case .paragraph:
            if chars == "\n" && cursorPosition > 0 && cursorPosition <= nsText.length {
                let prevChar = nsText.substring(with: NSRange(location: cursorPosition - 1, length: 1))
                if prevChar == "\n" {
                    scheduleAutoExit()
                }
            }
            
        case .clause:
            if chars == "," || chars == ";" || chars == ":" {
                scheduleAutoExit()
            } else if chars == " " {
                let prevWord = getWordBeforeCursor()
                let conjunctions: Set<String> = [
                    "and", "but", "or", "so", "yet", "for", "nor",
                    "although", "because", "since", "unless", "if", "while", "whereas"
                ]
                if conjunctions.contains(prevWord.lowercased()) {
                    scheduleAutoExit()
                }
            }
            
        case .line:
            if chars == "\n" {
                scheduleAutoExit()
            }
            
        default:
            break
        }
    }
    
    private func scheduleAutoExit() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.completeInsertMode()
        }
    }
    
    private func getWordBeforeCursor() -> String {
        let nsText = document.currentContent as NSString
        guard cursorPosition > 0 && cursorPosition <= nsText.length else { return "" }
        
        var pos = cursorPosition - 1
        while pos >= 0 {
            let char = nsText.substring(with: NSRange(location: pos, length: 1))
            if char != " " && char != "\n" { break }
            pos -= 1
        }
        let endPos = pos + 1
        while pos >= 0 {
            let char = nsText.substring(with: NSRange(location: pos, length: 1))
            if char == " " || char == "\n" { break }
            pos -= 1
        }
        let startPos = pos + 1
        if endPos > startPos {
            return nsText.substring(with: NSRange(location: startPos, length: endPos - startPos))
        }
        return ""
    }
    
    private func completeInsertMode() {
        if pendingChangeTracker.hasPending {
            let capturedStartPos = pendingChangeTracker.insertStartPosition
            
            if let completed = pendingChangeTracker.completeChange(
                currentContent: document.currentContent,
                cursorPosition: cursorPosition
            ) {
                document.recordChange(completed)
                
                if let startPos = capturedStartPos {
                    let length = cursorPosition - startPos
                    if length > 0 {
                        let nsText = document.currentContent as NSString
                        let safeRange = TextAnalyzer.safeRange(NSRange(location: startPos, length: length), in: nsText.length)
                        let insertedText = nsText.substring(with: safeRange)
                        let operation = InsertOperation(position: startPos, insertedText: insertedText, semanticChange: completed)
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
        guard let char = chars.first.map(String.init) else { return }
        let isShift = modifiers.contains(.shift)
        
        if let payload = movePayload, let payloadType = movePayloadType {
            handleMoveKey(char, payload: payload, payloadType: payloadType)
            return
        }
        
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
        
        // Handle G (Shift+g) — jump to bottom
        if char == "G" && isShift {
            pendingG = false
            cursorPosition = (document.currentContent as NSString).length
            flashCursor()
            return
        }
        
        // Handle gg (double-press) — jump to top
        if char.lowercased() == "g" && !isShift {
            if pendingG {
                pendingG = false
                cursorPosition = 0
                flashCursor()
            } else {
                pendingG = true
            }
            return
        }
        
        pendingG = false
        
        // Handle ' (argument structure prefix)
        if char == "'" && !isShift {
            if pendingArgument {
                pendingArgument = false
            } else {
                pendingArgument = true
            }
            return
        }
        
        if pendingArgument {
            pendingArgument = false
            if let argType = parseArgumentType(char.lowercased()) {
                executeArgumentCommand(argType)
                return
            }
        }
        
        switch char.lowercased() {
        // Navigation — sentence-first
        case "h": isShift ? navigateClause(forward: false) : navigateSentence(forward: false)
        case "l": isShift ? navigateClause(forward: true) : navigateSentence(forward: true)
        case "j": isShift ? navigateLine(forward: true) : navigateParagraph(forward: true)
        case "k": isShift ? navigateLine(forward: false) : navigateParagraph(forward: false)
        case "w": navigateWord(forward: true)
        case "b": navigateWord(forward: false)
            
        // Verbs (updated: r=replace, c=cite)
        case "d": isShift ? executeDeleteToEnd() : startPendingVerb(.delete)
        case "r": isShift ? executeReplaceToEnd() : startPendingVerb(.replace)
        case "c": isShift ? executeCiteToEnd() : startPendingVerb(.cite)
        case "y": startPendingVerb(.yank)
        case "m": startPendingVerb(.markup)
        case "x": startPendingVerb(.move)
            
        // Direct actions
        case "i": startInsert(context: .freeform)
        case "a": executeAppendAfterSentence()
        case "o": executeOpenLineBelow()
        case "p": executePaste()
        case "u": executeUndo()
        case ".": repeatLastCommand()
        case "v": enterVisualMode()
        case ":": mode = .command("")
        case "/": enterSearchMode()
            
        // Search navigation
        case "n": isShift ? navigateSearchResult(forward: false) : navigateSearchResult(forward: true)
            
        default: break
        }
    }
    
    // MARK: - Verbs & Objects
    
    private func startPendingVerb(_ verb: EditVerb) {
        pendingVerb = PendingVerb(verb)
        if let sentence = analyzer.sentenceAt(cursorPosition, in: document.currentContent) {
            highlightRange = sentence.range
        }
    }
    
    private func updateLiveHighlightForObject(verb: EditVerb, object: EditObject) {
        if let unit = resolveUnit(for: object) {
            highlightRange = unit.range
        }
    }
    
    private func executeVerbObject(verb: EditVerb, objectKey: String, isShift: Bool) {
        guard let object = parseObject(objectKey),
              let unit = resolveUnit(for: object) else { return }
        
        lastCommand = LastCommand(verb: verb, object: object, insertedText: nil)
        let unitType = objectTextUnitType(object)
        
        switch verb {
        case .delete:  executeDelete(unit: unit, unitType: unitType)
        case .replace: executeReplace(unit: unit, unitType: unitType, object: object)
        case .cite:    executeCite(unit: unit, unitType: unitType)
        case .yank:    executeYank(unit: unit, unitType: unitType)
        case .markup:  executeMarkup(unit: unit, unitType: unitType)
        case .move:    startMove(unit: unit, unitType: unitType)
        }
    }
    
    // MARK: - Core Operations
    
    private func executeDelete(unit: TextUnit, unitType: TextUnitType) {
        let range = unitType == .word ? TextAnalyzer.expandToTrailingSpace(unit.range, in: document.currentContent) : unit.range
        let change = SemanticChange(type: .deleted, unitType: unitType, beforeText: unit.text, position: cursorPosition, context: "deleted \(unitType.rawValue)")
        
        highlightRangeBriefly(range) { self.performDelete(range: range, change: change) }
    }
    
    /// Unified replace: deletes the unit and enters insert mode to type the replacement
    private func executeReplace(unit: TextUnit, unitType: TextUnitType, object: EditObject) {
        let range = unitType == .word ? TextAnalyzer.expandToTrailingSpace(unit.range, in: document.currentContent) : unit.range
        let ctx = objectInsertContext(object)
        
        pendingChangeTracker.startChange(type: .replaced, unitType: unitType, beforeText: unit.text, position: range.location, context: "replaced \(unitType.rawValue)")
        
        highlightRangeBriefly(range) {
            self.performDelete(range: range, change: nil)
            self.mode = .insert(ctx)
            self.insertContext = ctx
        }
    }
    
    /// Cite: flash the text unit and open a citation sheet; marker will be inserted at the end of the unit
    private func executeCite(unit: TextUnit, unitType: TextUnitType) {
        flashUnit(unit)
        activeSheet = .citation(anchorText: unit.text, insertPosition: unit.endLocation)
    }
    
    private func executeYank(unit: TextUnit, unitType: TextUnitType) {
        document.yankRegister = unit.text
        flashUnit(unit)
    }
    
    private func executeMarkup(unit: TextUnit, unitType: TextUnitType) {
        flashUnit(unit)
        activeSheet = .annotation(anchorText: unit.text, position: unit.range.location)
    }
    
    // MARK: - Move Engine
    
    private func startMove(unit: TextUnit, unitType: TextUnitType) {
        movePayload = unit
        movePayloadType = unitType
        flashUnit(unit)
    }
    
    private func handleMoveKey(_ char: String, payload: TextUnit, payloadType: TextUnitType) {
        switch char {
        case "j": navigateParagraph(forward: true)
        case "k": navigateParagraph(forward: false)
        case "\r", "\n": confirmMove(payload: payload, payloadType: payloadType)
        case "\u{1B}": movePayload = nil; movePayloadType = nil
        default: break
        }
    }
    
    private func confirmMove(payload: TextUnit, payloadType: TextUnitType) {
        let dest = cursorPosition
        let change = SemanticChange(type: .moved, unitType: payloadType, beforeText: payload.text, position: payload.range.location, context: "moved to \(dest)")
        let operation = MoveOperation(sourceRange: payload.range, movedText: payload.text, destinationPosition: dest, cursorBefore: payload.range.location, semanticChange: change)
        
        var content = document.currentContent
        let _ = operation.redo(content: &content)
        document.currentContent = content
        
        undoStack.push(operation)
        document.recordChange(change)
        
        movePayload = nil
        movePayloadType = nil
        handleTextChange()
    }
    
    // MARK: - Shift Actions & Direct Actions
    
    private func executeDeleteToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        let change = SemanticChange(type: .deleted, unitType: .sentence, beforeText: rest.text, position: cursorPosition, context: "deleted to end")
        highlightRangeBriefly(rest.range) { self.performDelete(range: rest.range, change: change) }
    }
    
    private func executeReplaceToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        pendingChangeTracker.startChange(type: .replaced, unitType: .sentence, beforeText: rest.text, position: rest.range.location, context: "replace to end")
        highlightRangeBriefly(rest.range) {
            self.performDelete(range: rest.range, change: nil)
            self.mode = .insert(.sentence)
            self.insertContext = .sentence
        }
    }
    
    /// C (shift-c): cite the rest of the current sentence
    private func executeCiteToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        flashRange = rest.range
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.flashRange = nil }
        activeSheet = .citation(anchorText: rest.text, insertPosition: rest.endLocation)
    }
    
    private func startInsert(context: InsertContext) {
        let unitType = insertContextToUnitType(context)
        pendingChangeTracker.startChange(type: .added, unitType: unitType, beforeText: nil, position: cursorPosition, context: "insert \(context.displayName)")
        mode = .insert(context)
        insertContext = context
        pendingVerb = nil
        highlightRange = nil
    }
    
    private func insertContextToUnitType(_ context: InsertContext) -> TextUnitType {
        switch context {
        case .word:      return .word
        case .clause:    return .clause
        case .sentence:  return .sentence
        case .paragraph: return .paragraph
        case .line:      return .sentence
        case .freeform:  return .sentence
        }
    }
    
    private func executeAppendAfterSentence() {
        if let sentence = analyzer.sentenceAt(cursorPosition, in: document.currentContent) {
            cursorPosition = sentence.endLocation
        }
        startInsert(context: .sentence)
    }
    
    private func executeOpenLineBelow() {
        let nsText = document.currentContent as NSString
        let range = NSRange(location: cursorPosition, length: nsText.length - cursorPosition)
        let nextNewline = nsText.range(of: "\n", options: [], range: range)
        let insertPos = nextNewline.location != NSNotFound ? nextNewline.location + 1 : nsText.length
        
        document.currentContent = nsText.replacingCharacters(in: NSRange(location: insertPos, length: 0), with: "\n")
        cursorPosition = insertPos + 1
        startInsert(context: .line)
        handleTextChange()
    }
    
    private func executePaste() {
        guard let yanked = document.yankRegister, !yanked.isEmpty else { return }
        let nsText = document.currentContent as NSString
        let insertPos = min(cursorPosition, nsText.length)
        
        let change = SemanticChange(type: .added, unitType: .sentence, afterText: yanked, position: insertPos, context: "pasted")
        let operation = InsertOperation(position: insertPos, insertedText: yanked, semanticChange: change)
        
        document.currentContent = nsText.replacingCharacters(in: NSRange(location: insertPos, length: 0), with: yanked)
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
        guard let last = lastCommand, let obj = last.object, let _ = resolveUnit(for: obj) else { return }
        executeVerbObject(verb: last.verb, objectKey: obj.rawValue, isShift: false)
    }
    
    // MARK: - Visual Mode
    
    private func enterVisualMode() {
        selectionRange = NSRange(location: cursorPosition, length: 0)
        mode = .visual(.character)
    }
    
    private func handleVisualKey(_ chars: String, modifiers: NSEvent.ModifierFlags) {
        guard let char = chars.first.map({ String($0).lowercased() }) else { return }
        if char == "\u{1B}" { selectionRange = nil; mode = .normal; return }
    }
    
    // MARK: - Command Mode
    
    private func handleCommandKey(_ chars: String, current: String) {
        guard let char = chars.first else { return }
        if char == "\u{1B}" { mode = .normal; return }
        if char == "\r" || char == "\n" { executeCommand(current); return }
        if char == "\u{7F}" {
            mode = current.isEmpty ? .normal : .command(String(current.dropLast()))
            return
        }
        mode = .command(current + String(char))
    }
    
    private func executeCommand(_ cmd: String) {
        let trimmed = cmd.trimmingCharacters(in: .whitespaces).lowercased()
        switch trimmed {
        case "comp", "diff": enterCompMode()
        case "save", "commit": if document.currentBranchHead != nil { activeSheet = .save }; mode = .normal
        case "branch", "branches": activeSheet = .branch; mode = .normal
        case "merge": activeSheet = .merge; mode = .normal
        case "log", "history": activeSheet = .log; mode = .normal
        case "help", "?": activeSheet = .help; mode = .normal
        // Argument structure commands via command mode
        case "ie", "evidence": executeArgumentCommand(.evidence)
        case "ic", "counter", "counterargument": executeArgumentCommand(.counterargument)
        case "ir", "rebuttal": executeArgumentCommand(.rebuttal)
        case "ab", "bridge": executeArgumentCommand(.bridge)
        case "at", "transition": executeArgumentCommand(.transition)
        default: mode = .normal
        }
    }
    
    // MARK: - Compare Mode
    
    private func enterCompMode() {
        guard let headDraft = document.currentBranchHead else { mode = .normal; return }
        diffChanges = DiffGenerator.generateDiff(from: headDraft.content, to: document.currentContent, withChanges: document.sessionChanges)
        let changeIndices = DiffGenerator.getChangeIndices(in: diffChanges)
        if changeIndices.isEmpty {
            // No changes detected — stay in normal mode
            diffChanges = []
            mode = .normal
            return
        }
        currentDiffIndex = changeIndices.first ?? 0
        mode = .comp
        navigateToCurrentDiffChange()
    }
    
    private func handleCompKey(_ chars: String) {
        guard let char = chars.first else { return }
        switch char {
        case "\u{1B}": diffChanges = []; mode = .normal
        case "n":
            if let next = DiffGenerator.findNextChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = next; navigateToCurrentDiffChange()
            }
        case "p":
            if let prev = DiffGenerator.findPreviousChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = prev; navigateToCurrentDiffChange()
            }
        default: break
        }
    }
    
    private func navigateToCurrentDiffChange() {
        guard currentDiffIndex < diffChanges.count else { return }
        let c = diffChanges[currentDiffIndex]
        cursorPosition = (c.type == .deletion ? c.displayRange?.location : c.range.location) ?? 0
    }
    
    // MARK: - Search Mode
    
    private func enterSearchMode() {
        searchMatches = []
        currentSearchIndex = 0
        mode = .search("")
    }
    
    private func handleSearchKey(_ chars: String, current: String) {
        guard let char = chars.first else { return }
        if char == "\u{1B}" {
            searchMatches = []
            highlightRange = nil
            mode = .normal
            return
        }
        if char == "\r" || char == "\n" {
            if !searchMatches.isEmpty {
                let match = searchMatches[currentSearchIndex]
                cursorPosition = match.location
                highlightRange = match
            }
            mode = .normal
            return
        }
        if char == "\u{7F}" {
            let newQuery = current.isEmpty ? "" : String(current.dropLast())
            mode = .search(newQuery)
            updateSearchResults(for: newQuery)
            return
        }
        let newQuery = current + String(char)
        mode = .search(newQuery)
        updateSearchResults(for: newQuery)
    }
    
    private func updateSearchResults(for query: String) {
        guard !query.isEmpty else {
            searchMatches = []
            highlightRange = nil
            return
        }
        let nsContent = document.currentContent as NSString
        var matches: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsContent.length)
        
        while searchRange.location < nsContent.length {
            let found = nsContent.range(of: query, options: .caseInsensitive, range: searchRange)
            guard found.location != NSNotFound else { break }
            matches.append(found)
            searchRange.location = found.location + found.length
            searchRange.length = nsContent.length - searchRange.location
        }
        
        searchMatches = matches
        
        if let nearestIdx = matches.firstIndex(where: { $0.location >= cursorPosition }) {
            currentSearchIndex = nearestIdx
        } else if !matches.isEmpty {
            currentSearchIndex = 0
        }
        
        if !matches.isEmpty && currentSearchIndex < matches.count {
            let match = matches[currentSearchIndex]
            cursorPosition = match.location
            highlightRange = match
        } else {
            highlightRange = nil
        }
    }
    
    private func navigateSearchResult(forward: Bool) {
        guard !searchMatches.isEmpty else { return }
        if forward {
            currentSearchIndex = (currentSearchIndex + 1) % searchMatches.count
        } else {
            currentSearchIndex = (currentSearchIndex - 1 + searchMatches.count) % searchMatches.count
        }
        let match = searchMatches[currentSearchIndex]
        cursorPosition = match.location
        highlightRange = match
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.highlightRange == match { self?.highlightRange = nil }
        }
    }
    
    // MARK: - Argument Structure Commands
    
    private func parseArgumentType(_ key: String) -> ArgumentType? {
        switch key {
        case "e": return .evidence
        case "c": return .counterargument
        case "r": return .rebuttal
        case "b": return .bridge
        case "t": return .transition
        default: return nil
        }
    }
    
    private func executeArgumentCommand(_ argType: ArgumentType) {
        let nsText = document.currentContent as NSString
        
        let insertPos: Int
        switch argType {
        case .evidence, .counterargument, .rebuttal:
            if let sentence = analyzer.sentenceAt(cursorPosition, in: document.currentContent) {
                insertPos = sentence.endLocation
            } else {
                insertPos = min(cursorPosition, nsText.length)
            }
        case .bridge:
            let paras = analyzer.paragraphs(in: document.currentContent)
            if let currentPara = paras.first(where: { NSLocationInRange(cursorPosition, $0.range) }) {
                insertPos = currentPara.endLocation
            } else {
                insertPos = min(cursorPosition, nsText.length)
            }
        case .transition:
            if let sentence = analyzer.sentenceAt(cursorPosition, in: document.currentContent) {
                insertPos = sentence.range.location
            } else {
                insertPos = min(cursorPosition, nsText.length)
            }
        }
        
        let prefix = argType.promptPrefix
        let separator = (argType == .bridge) ? "\n\n" : " "
        let insertText = separator + prefix
        
        document.currentContent = nsText.replacingCharacters(
            in: NSRange(location: insertPos, length: 0),
            with: insertText
        )
        cursorPosition = insertPos + insertText.count
        
        pendingChangeTracker.startChange(
            type: .added,
            unitType: .sentence,
            beforeText: nil,
            position: insertPos,
            context: argType.context
        )
        
        mode = .insert(.sentence)
        insertContext = .sentence
        pendingVerb = nil
        highlightRange = nil
        handleTextChange()
    }
    
    // MARK: - Annotation Navigation
    
    func navigateToPosition(_ position: Int) {
        let text = document.currentContent
        cursorPosition = TextAnalyzer.safePosition(position, in: text)
        if let sentence = analyzer.sentenceAt(cursorPosition, in: text) {
            highlightRange = sentence.range
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if self?.highlightRange == sentence.range { self?.highlightRange = nil }
            }
        }
    }
    
    // MARK: - Navigation Utilities
    
    private func navigateWord(forward: Bool) {
        let text = document.currentContent
        if forward {
            cursorPosition = analyzer.nextWord(from: cursorPosition, in: text)?.range.location ?? (text as NSString).length
        } else {
            cursorPosition = analyzer.prevWord(from: cursorPosition, in: text)?.range.location ?? 0
        }
        flashCursor()
    }
    
    private func navigateClause(forward: Bool) {
        let clauses = analyzer.clauses(in: document.currentContent)
        if forward {
            if let next = clauses.first(where: { $0.range.location > cursorPosition }) { cursorPosition = next.range.location }
        } else {
            if let prev = clauses.last(where: { $0.range.location < cursorPosition }) { cursorPosition = prev.range.location }
        }
        flashCursor()
    }
    
    private func navigateSentence(forward: Bool) {
        let text = document.currentContent
        if forward {
            if let next = analyzer.nextSentence(from: cursorPosition, in: text) { cursorPosition = next.range.location }
        } else {
            if let prev = analyzer.prevSentence(from: cursorPosition, in: text) { cursorPosition = prev.range.location }
        }
        flashCursor()
    }
    
    // FIX 1: Paragraph navigation now uses the NLP-based paragraph list
    // instead of raw \n\n searching. This correctly handles edge cases where
    // the cursor sits at a paragraph boundary.
    private func navigateParagraph(forward: Bool) {
        let text = document.currentContent
        let paragraphs = analyzer.paragraphs(in: text)
        guard !paragraphs.isEmpty else { return }
        
        if forward {
            // Find the first paragraph whose start is strictly after the cursor
            if let next = paragraphs.first(where: { $0.range.location > cursorPosition }) {
                cursorPosition = next.range.location
            } else {
                // Already in/past the last paragraph — go to end
                cursorPosition = (text as NSString).length
            }
        } else {
            // Find the current paragraph (the one containing the cursor)
            let currentParaIndex = paragraphs.lastIndex(where: { $0.range.location <= cursorPosition })
            
            if let idx = currentParaIndex {
                if paragraphs[idx].range.location < cursorPosition {
                    // Cursor is in the middle of this paragraph — jump to its start
                    cursorPosition = paragraphs[idx].range.location
                } else if idx > 0 {
                    // Cursor is at the start of this paragraph — jump to previous
                    cursorPosition = paragraphs[idx - 1].range.location
                } else {
                    // Already at the first paragraph — go to 0
                    cursorPosition = 0
                }
            } else {
                cursorPosition = 0
            }
        }
        flashCursor()
    }
    
    private func navigateLine(forward: Bool) {
        cursorPosition = forward ? TextAnalyzer.getNextLineStart(from: cursorPosition, in: document.currentContent)
                                 : TextAnalyzer.getPreviousLineStart(from: cursorPosition, in: document.currentContent)
        flashCursor()
    }
    
    // MARK: - Unit Helpers
    
    private func performDelete(range: NSRange, change: SemanticChange?) {
        let nsText = document.currentContent as NSString
        let safeRange = TextAnalyzer.safeRange(range, in: nsText.length)
        guard safeRange.length > 0 else { return }
        
        let deletedText = nsText.substring(with: safeRange)
        let afterContent = nsText.replacingCharacters(in: safeRange, with: "")
        
        let operation = DeleteOperation(range: safeRange, deletedText: deletedText, cursorBefore: cursorPosition, semanticChange: change)
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
        flashRange = NSRange(location: loc, length: loc < (text as NSString).length ? 1 : 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.flashRange = nil }
    }
    
    private func parseObject(_ key: String) -> EditObject? {
        switch key {
        case "w": return .word
        case "b": return .wordBack
        case "c": return .clause
        case "s": return .sentence
        case "p": return .paragraph
        default: return nil
        }
    }
    
    private func resolveUnit(for object: EditObject) -> TextUnit? {
        let text = document.currentContent
        let pos = cursorPosition
        switch object {
        case .word: return analyzer.wordAt(pos, in: text)
        case .wordBack: return analyzer.prevWord(from: pos, in: text)
        case .clause: return analyzer.clauseAt(pos, in: text)
        case .sentence: return analyzer.sentenceAt(pos, in: text)
        case .paragraph: return analyzer.paragraphAt(pos, in: text)
        }
    }
    
    private func objectTextUnitType(_ object: EditObject) -> TextUnitType {
        switch object {
        case .word, .wordBack: return .word
        case .clause: return .clause
        case .sentence: return .sentence
        case .paragraph: return .paragraph
        }
    }
    
    private func objectInsertContext(_ object: EditObject) -> InsertContext {
        switch object {
        case .word, .wordBack: return .word
        case .clause: return .clause
        case .sentence: return .sentence
        case .paragraph: return .paragraph
        }
    }
}
