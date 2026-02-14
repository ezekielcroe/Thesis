import SwiftUI
import AppKit

// MARK: - TextStats (needed for StatusBar)
struct TextStats {
    let paragraphCount: Int
    let sentenceCount: Int
    let wordCount: Int
}

struct ModalEditor: View {
    @Binding var document: Document
    @State private var mode: EditorMode = .freeText
    @State private var commandBuffer: String = ""
    @State private var insertContext: InsertContext?
    @State private var lastNewlinePosition: Int = -1
    @State private var pendingCommand: PendingCommand?
    
    // Highlights
    @State private var highlightRange: NSRange?
    @State private var flashRange: NSRange?
    
    @State private var cursorPosition: Int = 0
    @State private var undoStack = UndoStack()
    @State private var showingFirstDraftSheet = false
    @State private var showingPrintSheet = false
    @State private var diffChanges: [DiffChange] = []
    @State private var currentDiffIndex: Int = 0
    @State private var stats: TextStats = TextStats(paragraphCount: 0, sentenceCount: 0, wordCount: 0)
    
    // Semantic changes
    @State private var pendingChangeTracker = PendingChangeTracker()
    @State private var sessionChanges: [SemanticChange] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Main editor area
            ZStack {
                EditorTextView(
                    text: $document.currentContent,
                    mode: $mode,
                    cursorPosition: $cursorPosition,
                    highlightRange: $highlightRange,
                    flashRange: $flashRange,
                    diffChanges: $diffChanges,
                    onTextChange: { handleTextChange() },
                    onKeyPress: { key, modifiers in handleKeyPress(key, modifiers: modifiers) },
                    onModeChange: { newMode in handleModeChange(newMode) }
                )
                .border(mode.borderColor, width: 3)
            }
            
            // Status bar
            StatusBar(
                mode: mode,
                commandBuffer: commandBuffer,
                stats: stats,
                draftInfo: draftInfo,
                hasUnsavedChanges: document.hasUnsavedChanges,
                branchInfo: branchInfo,
                diffInfo: currentDiffInfo
            )
        }
        .onAppear {
            DispatchQueue.main.async { updateStats() }
            if !document.drafts.isEmpty { mode = .edit }
        }
        .sheet(isPresented: $showingFirstDraftSheet) {
            FirstDraftSheet(
                onSave: { name in
                    document.saveFirstDraft(name: name)
                    mode = .edit
                    showingFirstDraftSheet = false
                },
                onCancel: {
                    mode = .freeText
                    showingFirstDraftSheet = false
                }
            )
        }
        .sheet(isPresented: $showingPrintSheet) {
            PrintDraftSheet(
                onSave: { name, comment in
                    document.saveDraft(name: name, comment: comment)
                    mode = .edit
                    showingPrintSheet = false
                    updateStats()
                }
            )
        }
    }
    
    // ... [Properties: draftInfo, branchInfo, currentDiffInfo, updateStats, handleTextChange, handleModeChange remain unchanged] ...
    
    // REUSE: Reuse the property getters and update methods from previous source [161-169]
    private var draftInfo: String {
        document.latestDraft?.displayName ?? "No draft saved"
    }
    
    private var branchInfo: String? {
        if document.isBranching, let parent = document.currentBranchParent {
            return "Branching from: \(parent.name)"
        }
        return nil
    }
    
    private var currentDiffInfo: StatusBar.DiffInfo? {
        guard mode == .comp, !diffChanges.isEmpty else { return nil }
        let changeIndices = DiffGenerator.getChangeIndices(in: diffChanges)
        guard !changeIndices.isEmpty else { return nil }
        let currentChangeArrayIndex = changeIndices.firstIndex(of: currentDiffIndex) ?? 0
        return StatusBar.DiffInfo(
            currentIndex: currentChangeArrayIndex,
            totalChanges: changeIndices.count,
            currentChange: currentDiffIndex < diffChanges.count ? diffChanges[currentDiffIndex] : nil
        )
    }
    
    private func updateStats() {
        let paragraphs = TextAnalyzer.getParagraphs(in: document.currentContent)
        let sentences = TextAnalyzer.getSentences(in: document.currentContent)
        let words = TextAnalyzer.getWords(in: document.currentContent)
        let newStats = TextStats(paragraphCount: paragraphs.count, sentenceCount: sentences.count, wordCount: words.count)
        DispatchQueue.main.async { self.stats = newStats }
    }

    private func handleTextChange() {
        DispatchQueue.main.async { self.updateStats() }
        switch mode {
        case .insert, .edit: document.updateWorkingDraft()
        default: break
        }
    }
    
    private func handleModeChange(_ newMode: EditorMode) {
        switch (mode, newMode) {
        case (.insert, .insert): break
        case (.insert, _): completeInsertMode()
        default: break
        }
        mode = newMode
        if newMode == .edit {
            insertContext = nil
            lastNewlinePosition = -1
        }
    }

    // MARK: - Key Handling
    
    private func handleKeyPress(_ characters: String, modifiers: NSEvent.ModifierFlags) {
        // Global Shortcuts
        if modifiers.contains(.command) && characters == "d" && mode == .edit {
            enterCompMode()
            return
        }
        if modifiers.contains(.command) && characters == "s" && mode == .edit {
            if document.latestDraft != nil { showingPrintSheet = true }
            return
        }
        
        switch mode {
        case .freeText: handleFreeTextMode(characters)
        case .edit: handleEditMode(characters, modifiers: modifiers)
        case .insert(let context): handleInsertMode(characters, context: context)
        case .command(let current): handleCommandMode(characters, current: current)
        case .comp: handleCompMode(characters)
        }
    }
    
    private func handleFreeTextMode(_ characters: String) {
        if characters == "\u{1B}" && !document.currentContent.isEmpty { // ESC
            showingFirstDraftSheet = true
        }
    }
    
    private func handleInsertMode(_ characters: String, context: InsertContext) {
        if characters == "\u{1B}" { // ESC
            completeInsertMode()
        }
    }
    
    private func completeInsertMode() {
        if pendingChangeTracker.hasPending {
            let insertedText = getRecentlyInsertedText()
            if let completedChange = pendingChangeTracker.completeChange(afterText: insertedText) {
                document.recordChange(completedChange)
            }
        }
        mode = .edit
        insertContext = nil
    }
    
    private func getRecentlyInsertedText() -> String {
        if let sentence = TextAnalyzer.getSentenceAt(position: cursorPosition, in: document.currentContent) {
            return sentence.text
        } else if let word = TextAnalyzer.getWordAt(position: cursorPosition, in: document.currentContent) {
            return word.text
        }
        return ""
    }

    // MARK: - Edit Mode Logic (FIXED)

    private func handleEditMode(_ characters: String, modifiers: NSEvent.ModifierFlags) {
        // FIX 1: Normalize input to handle Shift correctly
        // "Shift+h" produces "H", which failed the previous switch case "h"
        guard let rawChar = characters.first else { return }
        let char = rawChar.lowercased()
        
        if !commandBuffer.isEmpty {
            let combined = commandBuffer + char
            
            // Execute Clause Commands
            if combined == "dc" { executeDeleteClause(); commandBuffer = ""; return }
            if combined == "cc" { executeChangeClause(); commandBuffer = ""; return }
            if combined == "rc" { executeRefineClause(); commandBuffer = ""; return }
            
            // Execute Other Commands
            if combined == "dw" { executeDeleteWordEnhanced(forward: true); commandBuffer = ""; return }
            if combined == "db" { executeDeleteWordEnhanced(forward: false); commandBuffer = ""; return }
            if combined == "cw" { executeChangeWord(); commandBuffer = ""; return }
            if combined == "rw" { executeRefineWord(); commandBuffer = ""; return }
            if combined == "rs" { executeRefineSentence(); commandBuffer = ""; return }
            if combined == "rp" { executeRefineParagraph(); commandBuffer = ""; return }
            if combined == "das" { executeDeleteSentence(); commandBuffer = ""; return }
            if combined == "dap" { executeDeleteParagraph(); commandBuffer = ""; return }
            if combined == "cas" { executeChangeSentence(); commandBuffer = ""; return }
            if combined == "cap" { executeChangeParagraph(); commandBuffer = ""; return }
            
            // Multi-key prefixes
            if combined == "da" || combined == "ca" {
                commandBuffer = combined
                return
            }
            
            commandBuffer = ""
        }
        
        switch char {
        case "h":
            // FIX 2: Check modifiers on the lowercased character match
            if modifiers.contains(.shift) {
                moveToPreviousSentence() // Shift+H
            } else {
                moveToPreviousClause()   // h
            }
            
        case "l":
            if modifiers.contains(.shift) {
                moveToNextSentence()     // Shift+L
            } else {
                moveToNextClause()       // l
            }
            
        case "j":
            if modifiers.contains(.shift) {
                moveToNextLine()         // Shift+J
            } else {
                moveToNextParagraph()    // j
            }
            
        case "k":
            if modifiers.contains(.shift) {
                moveToPreviousLine()     // Shift+K
            } else {
                moveToPreviousParagraph() // k
            }
            
        case "w":
            if commandBuffer.isEmpty { moveToNextWord() }
            
        case "b":
            if commandBuffer.isEmpty { moveToPreviousWord() }
            
        case "d", "c", "r":
            // Handle Shift+D/C/R (To End)
            if modifiers.contains(.shift) {
                if char == "d" { executeDeleteToEnd() }
                if char == "c" { executeChangeToEnd() }
                if char == "r" { executeRefineToEnd() }
            } else {
                commandBuffer = String(char)
            }
            
        case "i":
            startInsert(context: .word)
            
        case "a":
            if commandBuffer.isEmpty { executeAppendSentence() }
            
        case "u":
            executeUndo()
            commandBuffer = ""
            
        case ":":
            mode = .command("")
            commandBuffer = ""
            
        default:
            commandBuffer = ""
        }
    }
    
    private func startInsert(context: InsertContext) {
        pendingChangeTracker.startChange(
             type: .added,
             unitType: .word,
             beforeText: nil,
             position: cursorPosition,
             context: "insert"
        )
        mode = .insert(context)
        insertContext = context
        commandBuffer = ""
    }
    
    // MARK: - Navigation (FIXED)

    private func moveToNextParagraph() {
        // FIX 3: True paragraph navigation (Jumping blank lines)
        // This ignores single \n and looks for the next block separated by \n\n
        let nsText = document.currentContent as NSString
        let length = nsText.length
        
        // 1. Move past current paragraph (scan for \n\n)
        var searchPos = cursorPosition
        let doubleNewline = "\n\n"
        
        let range = NSRange(location: searchPos, length: length - searchPos)
        let result = nsText.range(of: doubleNewline, options: [], range: range)
        
        if result.location != NSNotFound {
            // Jump to character AFTER the \n\n
            cursorPosition = result.location + result.length
        } else {
            // If no more paragraphs, go to end
            cursorPosition = length
        }
        flashCursor()
    }
    
    private func moveToPreviousParagraph() {
        let nsText = document.currentContent as NSString
        
        // Scan backwards for \n\n
        let range = NSRange(location: 0, length: cursorPosition)
        let result = nsText.range(of: "\n\n", options: .backwards, range: range)
        
        if result.location != NSNotFound {
            // Found the gap BEFORE this paragraph.
            // Check if we are currently AT the start of a paragraph
            if cursorPosition == result.location + result.length {
                // We are at the top of current para, jump to the previous one
                let subRange = NSRange(location: 0, length: result.location)
                let prevResult = nsText.range(of: "\n\n", options: .backwards, range: subRange)
                if prevResult.location != NSNotFound {
                    cursorPosition = prevResult.location + prevResult.length
                } else {
                    cursorPosition = 0
                }
            } else {
                // We are in the middle of a para, jump to its start
                cursorPosition = result.location + result.length
            }
        } else {
            cursorPosition = 0
        }
        flashCursor()
    }

    private func moveToNextLine() {
        // Standard line navigation (Next \n)
        let nsText = document.currentContent as NSString
        let range = NSRange(location: cursorPosition, length: nsText.length - cursorPosition)
        let nextNewline = nsText.range(of: "\n", options: [], range: range)
        
        if nextNewline.location != NSNotFound {
            cursorPosition = min(nextNewline.location + 1, nsText.length)
        } else {
            cursorPosition = nsText.length
        }
        flashCursor()
    }

    private func moveToPreviousLine() {
        let nsText = document.currentContent as NSString
        let range = NSRange(location: 0, length: cursorPosition)
        let prevNewline = nsText.range(of: "\n", options: .backwards, range: range)
        
        if prevNewline.location != NSNotFound {
            if prevNewline.location == cursorPosition - 1 {
                // Currently at start of line, jump to previous start of line
                let subRange = NSRange(location: 0, length: prevNewline.location)
                let secondPrev = nsText.range(of: "\n", options: .backwards, range: subRange)
                if secondPrev.location != NSNotFound {
                    cursorPosition = secondPrev.location + 1
                } else {
                    cursorPosition = 0
                }
            } else {
                cursorPosition = prevNewline.location + 1
            }
        } else {
            cursorPosition = 0
        }
        flashCursor()
    }

    // [Clause and Word Navigation Methods remain same as previous]
    private func moveToPreviousClause() {
        let clauses = TextAnalyzer.getClauses(in: document.currentContent)
        if let prev = clauses.last(where: { $0.range.location < cursorPosition }) {
            cursorPosition = prev.range.location
            flashCursor()
        }
    }

    private func moveToNextClause() {
        let clauses = TextAnalyzer.getClauses(in: document.currentContent)
        if let next = clauses.first(where: { $0.range.location > cursorPosition }) {
            cursorPosition = next.range.location
            flashCursor()
        }
    }
    
    private func moveToPreviousSentence() {
        if let prev = TextAnalyzer.getPreviousSentence(from: cursorPosition, in: document.currentContent) {
            cursorPosition = prev.range.location
            flashCursor()
        }
    }

    private func moveToNextSentence() {
        if let next = TextAnalyzer.getNextSentence(from: cursorPosition, in: document.currentContent) {
            cursorPosition = next.range.location
            flashCursor()
        }
    }
    
    private func moveToNextWord() {
        let words = TextAnalyzer.getWords(in: document.currentContent)
        if let nextWord = words.first(where: { word in
            word.range.location > cursorPosition &&
            !word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            cursorPosition = nextWord.range.location
        } else {
            cursorPosition = document.currentContent.count
        }
        flashCursor()
    }

    private func moveToPreviousWord() {
        let words = TextAnalyzer.getWords(in: document.currentContent)
        let currentWordStart = words.first(where: {
            NSLocationInRange(cursorPosition, $0.range) || $0.range.location == cursorPosition
        })?.range.location ?? cursorPosition
        
        if let prevWord = words.last(where: { word in
            word.range.location < currentWordStart &&
            !word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            cursorPosition = prevWord.range.location
        } else if let firstWord = words.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  cursorPosition > firstWord.range.location {
            cursorPosition = firstWord.range.location
        } else {
            cursorPosition = 0
        }
        flashCursor()
    }

    // MARK: - Editing Helpers (Clause/Word/Sentence Deletions)
    
    private func executeDeleteClause() {
        let clauses = TextAnalyzer.getClauses(in: document.currentContent)
        guard let clause = clauses.first(where: { NSLocationInRange(cursorPosition, $0.range) }) else { return }
        highlightAndRecordChange(range: clause.range, text: clause.text, type: .deleted, unit: .clause, context: "deleted clause")
    }
    
    private func executeChangeClause() {
        let clauses = TextAnalyzer.getClauses(in: document.currentContent)
        guard let clause = clauses.first(where: { NSLocationInRange(cursorPosition, $0.range) }) else { return }
        
        pendingChangeTracker.startChange(type: .replaced, unitType: .clause, beforeText: clause.text, position: cursorPosition, context: "clause replacement")
        
        highlightRangeBriefly(clause.range) {
            self.deleteRange(clause.range, trackAsChange: false)
            self.mode = .insert(.sentence)
            self.insertContext = .sentence
        }
    }
    
    private func executeRefineClause() {
        let clauses = TextAnalyzer.getClauses(in: document.currentContent)
        guard let clause = clauses.first(where: { NSLocationInRange(cursorPosition, $0.range) }) else { return }
        
        pendingChangeTracker.startChange(type: .refined, unitType: .clause, beforeText: clause.text, position: cursorPosition, context: "clause refinement")
        
        highlightRangeBriefly(clause.range) {
            self.deleteRange(clause.range, trackAsChange: false)
            self.mode = .insert(.sentence)
            self.insertContext = .sentence
        }
    }

    private func executeDeleteWordEnhanced(forward: Bool) {
        let words = TextAnalyzer.getWords(in: document.currentContent)
        let nsText = document.currentContent as NSString
        var wordToDelete: TextUnit?
        
        if forward {
            wordToDelete = words.first(where: { $0.range.location + $0.range.length > cursorPosition && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        } else {
            wordToDelete = words.last(where: { $0.range.location < cursorPosition && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
        
        guard let word = wordToDelete else { return }
        
        // Extend to trailing space
        var deleteRange = word.range
        var endPos = deleteRange.location + deleteRange.length
        while endPos < nsText.length {
            if nsText.substring(with: NSRange(location: endPos, length: 1)) == " " {
                deleteRange.length += 1; endPos += 1
            } else { break }
        }
        
        highlightAndRecordChange(range: deleteRange, text: word.text, type: .deleted, unit: .word, context: "deleted word")
    }

    private func executeChangeWord() {
        let words = TextAnalyzer.getWords(in: document.currentContent)
        guard let word = words.first(where: { NSLocationInRange(cursorPosition, $0.range) || $0.range.location >= cursorPosition }) else { return }
        
        let nsText = document.currentContent as NSString
        var deleteRange = word.range
        var endPos = deleteRange.location + deleteRange.length
        while endPos < nsText.length {
            if nsText.substring(with: NSRange(location: endPos, length: 1)) == " " {
                deleteRange.length += 1; endPos += 1
            } else { break }
        }
        
        pendingChangeTracker.startChange(type: .replaced, unitType: .word, beforeText: word.text, position: cursorPosition, context: "word replacement")
        
        highlightRangeBriefly(deleteRange) {
            self.deleteRange(deleteRange, trackAsChange: false)
            self.mode = .insert(.word)
            self.insertContext = .word
        }
    }

    private func executeRefineWord() {
        let words = TextAnalyzer.getWords(in: document.currentContent)
        guard let word = words.first(where: { NSLocationInRange(cursorPosition, $0.range) || $0.range.location >= cursorPosition }) else { return }
        
        // Similar to change word logic, refine consumes spaces too
        let nsText = document.currentContent as NSString
        var deleteRange = word.range
        var endPos = deleteRange.location + deleteRange.length
        while endPos < nsText.length {
            if nsText.substring(with: NSRange(location: endPos, length: 1)) == " " {
                deleteRange.length += 1; endPos += 1
            } else { break }
        }
        
        pendingChangeTracker.startChange(type: .refined, unitType: .word, beforeText: word.text, position: cursorPosition, context: "word refinement")
        
        highlightRangeBriefly(deleteRange) {
            self.deleteRange(deleteRange, trackAsChange: false)
            self.mode = .insert(.word)
            self.insertContext = .word
        }
    }

    // Reuse helper for simple deletions
    private func highlightAndRecordChange(range: NSRange, text: String, type: SemanticChangeType, unit: TextUnitType, context: String) {
        highlightRangeBriefly(range) {
            self.deleteRange(range, trackAsChange: false)
            let change = SemanticChange(type: type, unitType: unit, beforeText: text, afterText: nil, position: self.cursorPosition, context: context)
            self.document.recordChange(change)
        }
    }
    
    // [Implementations for executeDeleteSentence, executeRefineSentence etc. reuse similar patterns as above]
    private func executeDeleteSentence() {
        guard let sentence = TextAnalyzer.getSentenceAt(position: cursorPosition, in: document.currentContent) else { return }
        highlightAndRecordChange(range: sentence.range, text: sentence.text, type: .deleted, unit: .sentence, context: "deleted sentence")
    }
    
    private func executeChangeSentence() {
        guard let sentence = TextAnalyzer.getSentenceAt(position: cursorPosition, in: document.currentContent) else { return }
        pendingChangeTracker.startChange(type: .replaced, unitType: .sentence, beforeText: sentence.text, position: cursorPosition, context: "sentence replacement")
        highlightRangeBriefly(sentence.range) {
            self.deleteRange(sentence.range, trackAsChange: false)
            self.mode = .insert(.sentence); self.insertContext = .sentence
        }
    }
    
    private func executeRefineSentence() {
        guard let sentence = TextAnalyzer.getSentenceAt(position: cursorPosition, in: document.currentContent) else { return }
        pendingChangeTracker.startChange(type: .refined, unitType: .sentence, beforeText: sentence.text, position: cursorPosition, context: "sentence refinement")
        highlightRangeBriefly(sentence.range) {
            self.deleteRange(sentence.range, trackAsChange: false)
            self.mode = .insert(.sentence); self.insertContext = .sentence
        }
    }
    
    private func executeDeleteParagraph() {
        guard let paragraph = TextAnalyzer.getParagraphAt(position: cursorPosition, in: document.currentContent) else { return }
        highlightAndRecordChange(range: paragraph.range, text: paragraph.text, type: .deleted, unit: .paragraph, context: "deleted paragraph")
    }
    
    private func executeChangeParagraph() {
        guard let paragraph = TextAnalyzer.getParagraphAt(position: cursorPosition, in: document.currentContent) else { return }
        pendingChangeTracker.startChange(type: .replaced, unitType: .paragraph, beforeText: paragraph.text, position: cursorPosition, context: "paragraph replacement")
        highlightRangeBriefly(paragraph.range) {
            self.deleteRange(paragraph.range, trackAsChange: false)
            self.mode = .insert(.paragraph); self.insertContext = .paragraph
        }
    }
    
    private func executeRefineParagraph() {
        guard let paragraph = TextAnalyzer.getParagraphAt(position: cursorPosition, in: document.currentContent) else { return }
        pendingChangeTracker.startChange(type: .refined, unitType: .paragraph, beforeText: paragraph.text, position: cursorPosition, context: "paragraph refinement")
        highlightRangeBriefly(paragraph.range) {
            self.deleteRange(paragraph.range, trackAsChange: false)
            self.mode = .insert(.paragraph); self.insertContext = .paragraph
        }
    }
    
    private func executeDeleteToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        highlightAndRecordChange(range: rest.range, text: rest.text, type: .deleted, unit: .sentence, context: "deleted to end")
    }
    
    private func executeChangeToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        pendingChangeTracker.startChange(type: .replaced, unitType: .sentence, beforeText: rest.text, position: cursorPosition, context: "change to end")
        highlightRangeBriefly(rest.range) {
            self.deleteRange(rest.range, trackAsChange: false)
            self.mode = .insert(.sentence); self.insertContext = .sentence
        }
    }
    
    private func executeRefineToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        pendingChangeTracker.startChange(type: .refined, unitType: .sentence, beforeText: rest.text, position: cursorPosition, context: "refine to end")
        highlightRangeBriefly(rest.range) {
            self.deleteRange(rest.range, trackAsChange: false)
            self.mode = .insert(.sentence); self.insertContext = .sentence
        }
    }
    
    private func executeAppendSentence() {
        if let sentence = TextAnalyzer.getSentenceAt(position: cursorPosition, in: document.currentContent) {
            cursorPosition = sentence.range.location + sentence.range.length
        }
        pendingChangeTracker.startChange(type: .added, unitType: .sentence, beforeText: nil, position: cursorPosition, context: "appended sentence")
        mode = .insert(.sentence)
        insertContext = .sentence
    }
    
    // MARK: - Core Helpers
    
    private func executeUndo() {
        guard let command = undoStack.pop() else { return }
        if let newPosition = command.undo(in: &document.currentContent) {
            cursorPosition = newPosition
            handleTextChange()
        }
    }
    
    private func deleteRange(_ range: NSRange, trackAsChange: Bool = true) {
        let beforeContent = document.currentContent
        let nsText = beforeContent as NSString
        let afterContent = nsText.replacingCharacters(in: range, with: "")
        
        let command = UndoCommand(beforeContent: beforeContent, afterContent: afterContent, cursorBefore: cursorPosition, cursorAfter: range.location)
        undoStack.push(command)
        
        document.currentContent = afterContent
        cursorPosition = range.location
        handleTextChange()
    }
    
    private func highlightRangeBriefly(_ range: NSRange, completion: @escaping () -> Void) {
        highlightRange = range
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.highlightRange = nil
            completion()
        }
    }
    
    private func flashCursor() {
        guard !document.currentContent.isEmpty else { return }
        var location = cursorPosition
        if location >= document.currentContent.count { location = max(0, document.currentContent.count - 1) }
        flashRange = NSRange(location: location, length: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.flashRange = nil }
    }
    
    // [Comp Mode and Command Mode handlers remain mostly identical, included for completeness]
    private func handleCommandMode(_ characters: String, current: String) {
        guard let char = characters.first else { return }
        if char == "\u{1B}" { mode = .edit; return }
        if char == "\r" || char == "\n" { executeCommand(current); return }
        mode = .command(current + String(char))
    }
    
    private func executeCommand(_ cmd: String) {
        if cmd == "comp" { enterCompMode() }
        else if cmd == "print" { if document.latestDraft != nil { showingPrintSheet = true }; mode = .edit }
        else { mode = .edit }
    }
    
    private func enterCompMode() {
            guard let latestDraft = document.latestDraft else { return }
            
            // FIX: Pass the session changes so DiffGenerator knows the "Old Text"
            diffChanges = DiffGenerator.generateDiff(
                from: latestDraft.content,
                to: document.currentContent,
                withChanges: document.sessionChanges // <--- ADD THIS
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
    
    private func handleCompMode(_ characters: String) {
        guard let char = characters.first else { return }
        if char == "n" {
            if let next = DiffGenerator.findNextChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = next
                if currentDiffIndex < diffChanges.count {
                    let c = diffChanges[currentDiffIndex]
                    cursorPosition = (c.type == .deletion ? c.displayRange?.location : c.range.location) ?? 0
                }
            }
        } else if char == "p" {
            if let prev = DiffGenerator.findPreviousChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = prev
                if currentDiffIndex < diffChanges.count {
                    let c = diffChanges[currentDiffIndex]
                    cursorPosition = (c.type == .deletion ? c.displayRange?.location : c.range.location) ?? 0
                }
            }
        } else if char == "\u{1B}" {
            mode = .edit; diffChanges = []
        }
    }
}

// MARK: - Supporting Types

struct PendingCommand {
    let type: PendingCommandType
    let startPosition: Int
}

enum PendingCommandType {
    case insertWord
    case appendSentence
    case change(replacedText: String, range: NSRange, exitOn: ExitCondition)
}

enum ExitCondition {
    case space
    case punctuation
    case doubleNewline
}

// MARK: - Status Bar

struct StatusBar: View {
    let mode: EditorMode
    let commandBuffer: String
    let stats: TextStats
    let draftInfo: String
    let hasUnsavedChanges: Bool
    let branchInfo: String?
    let diffInfo: DiffInfo?
    
    struct DiffInfo {
        let currentIndex: Int
        let totalChanges: Int
        let currentChange: DiffChange?
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Mode indicator
            Text(mode.displayName)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(mode.borderColor)
                .cornerRadius(4)
            
            // Command buffer
            if !commandBuffer.isEmpty {
                Text(commandBuffer)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Diff info (in comp mode)
            if let diff = diffInfo {
                HStack(spacing: 8) {
                    Text("Change \(diff.currentIndex + 1)/\(diff.totalChanges)")
                        .font(.system(size: 11, design: .monospaced))
                    
                    if let change = diff.currentChange {
                        switch change.type {
                        case .addition:
                            Text("ADDED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(3)
                        case .deletion:
                            Text("DELETED: \"\(change.text.prefix(30))\(change.text.count > 30 ? "..." : "")\"")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .cornerRadius(3)
                                .lineLimit(1)
                        case .unchanged:
                            EmptyView()
                        }
                    }
                    
                    Text("(n: next, p: prev, ESC: exit)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } else {
                // Draft info
                Text(draftInfo)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(hasUnsavedChanges ? .orange : .secondary)
                
                if hasUnsavedChanges {
                    Text("*")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                }
                
                if let branch = branchInfo {
                    Text(branch)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            // Stats
            HStack(spacing: 12) {
                Text("\(stats.paragraphCount) ¶")
                Text("\(stats.sentenceCount) sentences")
                Text("\(stats.wordCount) words")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Sheets

struct FirstDraftSheet: View {
    @State private var draftName: String = ""
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Save as First Draft")
                .font(.headline)
            
            Text("This will be the baseline for tracking your thought evolution.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            TextField("Draft name (e.g., 'Initial thoughts')", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if !draftName.isEmpty {
                        dismiss()
                        onSave(draftName)
                    }
                }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Button("Save") {
                    if !draftName.isEmpty {
                        dismiss()
                        onSave(draftName)
                    }
                }
                .keyboardShortcut(.return)
                .disabled(draftName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
}

struct PrintDraftSheet: View {
    @State private var draftName: String = ""
    @State private var comment: String = ""
    @FocusState private var focusedField: Field?
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) var dismiss
    
    enum Field {
        case name
        case comment
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Save Draft")
                .font(.headline)
            
            Text("Capture this evolution point with a name and comment.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            TextField("Draft name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .name)
                .onSubmit {
                    focusedField = .comment
                }
            
            TextField("What changed in your thinking?", text: $comment)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .comment)
                .onSubmit {
                    if !draftName.isEmpty && !comment.isEmpty {
                        dismiss()
                        onSave(draftName, comment)
                    }
                }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Save") {
                    if !draftName.isEmpty && !comment.isEmpty {
                        dismiss()
                        onSave(draftName, comment)
                    }
                }
                .disabled(draftName.isEmpty || comment.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450)
        .onAppear {
            focusedField = .name
        }
    }
}
