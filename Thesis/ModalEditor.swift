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
    
    // SEPARATE Highlight types
    @State private var highlightRange: NSRange? // For RED deletion previews
    @State private var flashRange: NSRange?     // For YELLOW navigation flashes
    
    @State private var cursorPosition: Int = 0
    @State private var undoStack = UndoStack()
    @State private var showingFirstDraftSheet = false
    @State private var showingPrintSheet = false
    @State private var diffChanges: [DiffChange] = []
    @State private var currentDiffIndex: Int = 0
    @State private var stats: TextStats = TextStats(paragraphCount: 0, sentenceCount: 0, wordCount: 0)
    
    // ENHANCED: Tracking semantic changes
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
                    flashRange: $flashRange, // NEW: Pass flash range
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
            DispatchQueue.main.async {
                updateStats()
            }
            if !document.drafts.isEmpty {
                mode = .edit
            }
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
    
    private var draftInfo: String {
        if let latest = document.latestDraft {
            return latest.displayName
        }
        return "No draft saved"
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
        
        let newStats = TextStats(
            paragraphCount: paragraphs.count,
            sentenceCount: sentences.count,
            wordCount: words.count
        )
        
        DispatchQueue.main.async {
            self.stats = newStats
        }
    }

    private func handleTextChange() {
        DispatchQueue.main.async {
            self.updateStats()
        }
        
        switch mode {
        case .insert, .edit:
            document.updateWorkingDraft()
        default:
            break
        }
    }
    
    private func handleModeChange(_ newMode: EditorMode) {
        // ENHANCED: Fixed Tuple Switch for Exit Logic
        switch (mode, newMode) {
        case (.insert, .insert):
            break // Context change only
        case (.insert, _):
            completeInsertMode() // Exiting insert mode
        default:
            break
        }
        
        mode = newMode
        
        if newMode == .edit {
            insertContext = nil
            lastNewlinePosition = -1
        }
    }
    
    private func handleKeyPress(_ characters: String, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) && characters == "d" && mode == .edit {
            enterCompMode()
            return
        }
        
        if modifiers.contains(.command) && characters == "s" && mode == .edit {
            if document.latestDraft != nil {
                showingPrintSheet = true
            }
            return
        }
        
        switch mode {
        case .freeText:
            handleFreeTextMode(characters)
        case .edit:
            handleEditMode(characters, modifiers: modifiers)
        case .insert(let context):
            handleInsertMode(characters, context: context)
        case .command(let current):
            handleCommandMode(characters, current: current)
        case .comp:
            handleCompMode(characters)
        }
    }

    // MARK: - FREE TEXT Mode Handler

    private func handleFreeTextMode(_ characters: String) {
        if characters == "\u{1B}" { // ESC
            if !document.currentContent.isEmpty {
                showingFirstDraftSheet = true
            }
        }
    }
    
    // MARK: - Insert Mode

    private func handleInsertMode(_ characters: String, context: InsertContext) {
        if characters == "\u{1B}" {
            completeInsertMode()
            return
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

    // MARK: - Edit Mode

    private func handleEditMode(_ characters: String, modifiers: NSEvent.ModifierFlags) {
        guard let char = characters.first else { return }
        
        if !commandBuffer.isEmpty {
            let combined = commandBuffer + String(char)
            
            if combined == "dw" { executeDeleteWordEnhanced(forward: true); commandBuffer = ""; return }
            if combined == "db" { executeDeleteWordEnhanced(forward: false); commandBuffer = ""; return }
            
            if combined == "cw" { executeChangeWord(); commandBuffer = ""; return }
            
            if combined == "rs" { executeRefineSentence(); commandBuffer = ""; return }
            if combined == "rw" { executeRefineWord(); commandBuffer = ""; return }
            if combined == "rp" { executeRefineParagraph(); commandBuffer = ""; return }
            
            if combined == "da" || combined == "ca" {
                commandBuffer = combined
                return
            }
            
            if combined == "das" { executeDeleteSentence(); commandBuffer = ""; return }
            if combined == "dap" { executeDeleteParagraph(); commandBuffer = ""; return }
            if combined == "cas" { executeChangeSentence(); commandBuffer = ""; return }
            if combined == "cap" { executeChangeParagraph(); commandBuffer = ""; return }
            
            commandBuffer = ""
        }
        
        switch char {
        case "h": moveToPreviousSentence()
        case "l": moveToNextSentence()
        case "j": moveToNextParagraph()
        case "k": moveToPreviousParagraph()
            
        case "w":
            if commandBuffer.isEmpty { moveToNextWord() }
            
        case "b":
            if commandBuffer.isEmpty { moveToPreviousWord() }
            
        case "d":
            if modifiers.contains(.shift) {
                executeDeleteToEnd()
            } else {
                commandBuffer = "d"
            }
            
        case "c":
            if modifiers.contains(.shift) {
                executeChangeToEnd()
            } else {
                commandBuffer = "c"
            }
            
        case "r":
            if modifiers.contains(.shift) {
                executeRefineToEnd()
            } else {
                commandBuffer = "r"
            }
            
        case "i":
            pendingChangeTracker.startChange(
                 type: .added,
                 unitType: .word,
                 beforeText: nil,
                 position: cursorPosition,
                 context: "insert"
            )
            mode = .insert(.word)
            insertContext = .word
            commandBuffer = ""
            
        case "a":
            if commandBuffer.isEmpty {
                executeAppendSentence()
            }
            
        case "s", "p":
            break
            
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
    
    // MARK: - Navigation Commands (Updated with Flash)
        // Same logic, just ensure they call flashCursor()
        
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

        private func moveToPreviousParagraph() {
            if let prev = TextAnalyzer.getPreviousParagraph(from: cursorPosition, in: document.currentContent) {
                cursorPosition = prev.range.location
                flashCursor()
            }
        }

        private func moveToNextParagraph() {
            if let next = TextAnalyzer.getNextParagraph(from: cursorPosition, in: document.currentContent) {
                cursorPosition = next.range.location
                flashCursor()
            }
        }

    private func moveToNextWord() {
            let words = TextAnalyzer.getWords(in: document.currentContent)
            
            // LOGIC CHANGE: Filter out whitespace tokens so we skip " " and jump to "is"
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
            
            // 1. Identify start of current word (if inside one)
            let currentWordStart = words.first(where: {
                NSLocationInRange(cursorPosition, $0.range) || $0.range.location == cursorPosition
            })?.range.location ?? cursorPosition
            
            // 2. Find previous word, IGNORING whitespace tokens
            if let prevWord = words.last(where: { word in
                word.range.location < currentWordStart &&
                !word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                cursorPosition = prevWord.range.location
            } else if let firstWord = words.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                      cursorPosition > firstWord.range.location {
                // Fallback: If we are past the first word but logic didn't catch it
                cursorPosition = firstWord.range.location
            } else {
                // Start of doc
                cursorPosition = 0
            }
            flashCursor()
        }

    // MARK: - Delete Commands
        
        // ENHANCED: Deletes word + trailing space (Filters out whitespace tokens)
        private func executeDeleteWordEnhanced(forward: Bool) {
            let words = TextAnalyzer.getWords(in: document.currentContent)
            let nsText = document.currentContent as NSString
            
            var wordToDelete: TextUnit?
            
            if forward {
                // Forward: Find first non-empty word overlapping or after cursor
                wordToDelete = words.first(where: {
                    $0.range.location + $0.range.length > cursorPosition &&
                    !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })
            } else {
                // Backward: Find last non-empty word starting strictly before cursor
                // This skips the "whitespace word" immediately behind the cursor
                wordToDelete = words.last(where: {
                    $0.range.location < cursorPosition &&
                    !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })
            }
            
            guard let word = wordToDelete else { return }
            
            let deletedText = word.text
            var deleteRange = word.range
            
            // CONSUME TRAILING SPACES
            // This extends the deletion range to include spaces after the word.
            // For 'db', this ensures "Word1 Word2 |" deletes "Word2 " (word + gap).
            var endPos = deleteRange.location + deleteRange.length
            while endPos < nsText.length {
                let nextCharRange = NSRange(location: endPos, length: 1)
                let nextChar = nsText.substring(with: nextCharRange)
                
                if nextChar == " " {
                    deleteRange.length += 1
                    endPos += 1
                } else {
                    break
                }
            }
            
            highlightRangeBriefly(deleteRange) {
                self.deleteRange(deleteRange, trackAsChange: false)
                
                let change = SemanticChange(
                    type: .deleted,
                    unitType: .word,
                    beforeText: deletedText,
                    afterText: nil,
                    position: self.cursorPosition,
                    context: "deleted word '\(deletedText)'"
                )
                self.document.recordChange(change)
            }
        }
    
    private func executeDeleteSentence() {
        guard let sentence = TextAnalyzer.getSentenceAt(position: cursorPosition, in: document.currentContent) else { return }
        let deletedText = sentence.text
        
        highlightRangeBriefly(sentence.range) {
            self.deleteRange(sentence.range, trackAsChange: false)
            
            let change = SemanticChange(
                type: .deleted,
                unitType: .sentence,
                beforeText: deletedText,
                afterText: nil,
                position: self.cursorPosition,
                context: "deleted sentence"
            )
            self.document.recordChange(change)
        }
    }
    
    private func executeDeleteParagraph() {
        guard let paragraph = TextAnalyzer.getParagraphAt(position: cursorPosition, in: document.currentContent) else { return }
        let deletedText = paragraph.text
        
        highlightRangeBriefly(paragraph.range) {
            self.deleteRange(paragraph.range, trackAsChange: false)
            
            let change = SemanticChange(
                type: .deleted,
                unitType: .paragraph,
                beforeText: deletedText,
                afterText: nil,
                position: self.cursorPosition,
                context: "deleted paragraph"
            )
            self.document.recordChange(change)
        }
    }
    
    private func executeDeleteToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        let deletedText = rest.text
        
        highlightRangeBriefly(rest.range) {
            self.deleteRange(rest.range, trackAsChange: false)
            
            let change = SemanticChange(
                type: .deleted,
                unitType: .sentence,
                beforeText: deletedText,
                afterText: nil,
                position: self.cursorPosition,
                context: "deleted to end"
            )
            self.document.recordChange(change)
        }
    }
    
    private func deleteRange(_ range: NSRange, trackAsChange: Bool = true) {
        let beforeContent = document.currentContent
        let nsText = beforeContent as NSString
        let afterContent = nsText.replacingCharacters(in: range, with: "")
        
        let command = UndoCommand(
            beforeContent: beforeContent,
            afterContent: afterContent,
            cursorBefore: cursorPosition,
            cursorAfter: range.location
        )
        
        undoStack.push(command)
        document.currentContent = afterContent
        cursorPosition = range.location
        handleTextChange()
    }
    
    // MARK: - Change Commands
    
    private func executeChangeWord() {
        let words = TextAnalyzer.getWords(in: document.currentContent)
        // Check current or overlapping word
        guard let word = words.first(where: {
            NSLocationInRange(cursorPosition, $0.range) || $0.range.location >= cursorPosition
        }) else { return }
        
        let originalText = word.text
        
        // Use expanded range (with spaces) for the deletion part
        let nsText = document.currentContent as NSString
        var deleteRange = word.range
        var endPos = deleteRange.location + deleteRange.length
        while endPos < nsText.length {
            let nextChar = nsText.substring(with: NSRange(location: endPos, length: 1))
            if nextChar == " " { deleteRange.length += 1; endPos += 1 } else { break }
        }
        
        pendingChangeTracker.startChange(
            type: .replaced,
            unitType: .word,
            beforeText: originalText,
            position: cursorPosition,
            context: "word '\(originalText)'"
        )
        
        highlightRangeBriefly(deleteRange) {
            self.deleteRange(deleteRange, trackAsChange: false)
            self.mode = .insert(.word)
            self.insertContext = .word
        }
    }

    private func executeChangeSentence() {
        guard let sentence = TextAnalyzer.getSentenceAt(position: cursorPosition, in: document.currentContent) else { return }
        let originalText = sentence.text
        
        pendingChangeTracker.startChange(
            type: .replaced,
            unitType: .sentence,
            beforeText: originalText,
            position: cursorPosition,
            context: "sentence at position \(cursorPosition)"
        )
        
        highlightRangeBriefly(sentence.range) {
            self.deleteRange(sentence.range, trackAsChange: false)
            self.mode = .insert(.sentence)
            self.insertContext = .sentence
        }
    }

    private func executeChangeParagraph() {
        guard let paragraph = TextAnalyzer.getParagraphAt(position: cursorPosition, in: document.currentContent) else { return }
        let originalText = paragraph.text
        
        pendingChangeTracker.startChange(
            type: .replaced,
            unitType: .paragraph,
            beforeText: originalText,
            position: cursorPosition,
            context: "paragraph at position \(cursorPosition)"
        )
        
        highlightRangeBriefly(paragraph.range) {
            self.deleteRange(paragraph.range, trackAsChange: false)
            self.mode = .insert(.paragraph)
            self.insertContext = .paragraph
        }
    }

    private func executeChangeToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        let originalText = rest.text
        
        pendingChangeTracker.startChange(
            type: .replaced,
            unitType: .sentence,
            beforeText: originalText,
            position: cursorPosition,
            context: "to end of sentence"
        )
        
        highlightRangeBriefly(rest.range) {
            self.deleteRange(rest.range, trackAsChange: false)
            self.mode = .insert(.sentence)
            self.insertContext = .sentence
        }
    }
    
    // MARK: - Refine Commands
    
    private func executeRefineSentence() {
        guard let sentence = TextAnalyzer.getSentenceAt(position: cursorPosition, in: document.currentContent) else { return }
        let originalText = sentence.text
        
        pendingChangeTracker.startChange(
            type: .refined,
            unitType: .sentence,
            beforeText: originalText,
            position: cursorPosition,
            context: "sentence at position \(cursorPosition)"
        )
        
        highlightRangeBriefly(sentence.range) {
            self.deleteRange(sentence.range, trackAsChange: false)
            self.mode = .insert(.sentence)
            self.insertContext = .sentence
        }
    }
    
    private func executeRefineWord() {
        guard let word = TextAnalyzer.getWordAt(position: cursorPosition, in: document.currentContent) else { return }
        let originalText = word.text
        
        // Consume spaces for refine word too
        let nsText = document.currentContent as NSString
        var deleteRange = word.range
        var endPos = deleteRange.location + deleteRange.length
        while endPos < nsText.length {
            let nextChar = nsText.substring(with: NSRange(location: endPos, length: 1))
            if nextChar == " " { deleteRange.length += 1; endPos += 1 } else { break }
        }
        
        pendingChangeTracker.startChange(
            type: .refined,
            unitType: .word,
            beforeText: originalText,
            position: cursorPosition,
            context: "word '\(originalText)'"
        )
        
        highlightRangeBriefly(deleteRange) {
            self.deleteRange(deleteRange, trackAsChange: false)
            self.mode = .insert(.word)
            self.insertContext = .word
        }
    }
    
    private func executeRefineParagraph() {
        guard let paragraph = TextAnalyzer.getParagraphAt(position: cursorPosition, in: document.currentContent) else { return }
        let originalText = paragraph.text
        
        pendingChangeTracker.startChange(
            type: .refined,
            unitType: .paragraph,
            beforeText: originalText,
            position: cursorPosition,
            context: "paragraph at position \(cursorPosition)"
        )
        
        highlightRangeBriefly(paragraph.range) {
            self.deleteRange(paragraph.range, trackAsChange: false)
            self.mode = .insert(.paragraph)
            self.insertContext = .paragraph
        }
    }
    
    private func executeRefineToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        let originalText = rest.text
        
        pendingChangeTracker.startChange(
            type: .refined,
            unitType: .sentence,
            beforeText: originalText,
            position: cursorPosition,
            context: "remainder of sentence"
        )
        
        highlightRangeBriefly(rest.range) {
            self.deleteRange(rest.range, trackAsChange: false)
            self.mode = .insert(.sentence)
            self.insertContext = .sentence
        }
    }
    
    func executeAppendSentence() {
        if let sentence = TextAnalyzer.getSentenceAt(position: cursorPosition, in: document.currentContent) {
            cursorPosition = sentence.range.location + sentence.range.length
        }
        
        pendingChangeTracker.startChange(
            type: .added,
            unitType: .sentence,
            beforeText: nil,
            position: cursorPosition,
            context: "appended sentence"
        )
        
        mode = .insert(.sentence)
        insertContext = .sentence
    }
    
    // MARK: - Undo
    
    private func executeUndo() {
        guard let command = undoStack.pop() else { return }
        
        if let newPosition = command.undo(in: &document.currentContent) {
            cursorPosition = newPosition
            handleTextChange()
        }
    }
    
    // MARK: - Comp Mode
    
    private func enterCompMode() {
        guard let latestDraft = document.latestDraft else { return }
        
        diffChanges = DiffGenerator.generateDiff(
            from: latestDraft.content,
            to: document.currentContent
        )
        currentDiffIndex = 0
        mode = .comp
        
        if let firstChangeIndex = DiffGenerator.getChangeIndices(in: diffChanges).first {
            currentDiffIndex = firstChangeIndex
            if currentDiffIndex < diffChanges.count {
                cursorPosition = diffChanges[currentDiffIndex].range.location
            }
        }
    }
    
    private func handleCompMode(_ characters: String) {
        guard let char = characters.first else { return }
        
        switch char {
        case "n":
            if let next = DiffGenerator.findNextChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = next
                if currentDiffIndex < diffChanges.count {
                    let change = diffChanges[currentDiffIndex]
                    if change.type == .deletion, let displayRange = change.displayRange {
                        cursorPosition = displayRange.location
                    } else {
                        cursorPosition = change.range.location
                    }
                }
            }
            
        case "p":
            if let prev = DiffGenerator.findPreviousChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = prev
                if currentDiffIndex < diffChanges.count {
                    let change = diffChanges[currentDiffIndex]
                    if change.type == .deletion, let displayRange = change.displayRange {
                        cursorPosition = displayRange.location
                    } else {
                        cursorPosition = change.range.location
                    }
                }
            }
            
        case "\u{1B}": // ESC
            mode = .edit
            diffChanges = []
            
        default:
            break
        }
    }
    
    // MARK: - Command Mode
    
    private func handleCommandMode(_ characters: String, current: String) {
        guard let char = characters.first else { return }
        
        if char == "\u{1B}" { // ESC
            mode = .edit
            return
        }
        
        if char == "\r" || char == "\n" { // Return
            executeCommand(current)
            return
        }
        
        mode = .command(current + String(char))
    }

    private func executeCommand(_ cmd: String) {
        switch cmd {
        case "comp":
            enterCompMode()
        case "print":
            if document.latestDraft != nil {
                showingPrintSheet = true
            }
            mode = .edit
        default:
            mode = .edit
        }
    }
    
    // MARK: - Helpers
        
        private func highlightRangeBriefly(_ range: NSRange, completion: @escaping () -> Void) {
            // This is for RED deletion/action previews
            highlightRange = range
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                highlightRange = nil
                completion()
            }
        }
        
        private func flashCursor() {
            guard !document.currentContent.isEmpty else { return }
            
            var location = cursorPosition
            if location >= document.currentContent.count {
                location = max(0, document.currentContent.count - 1)
            }
            
            // Use flashRange (Yellow) instead of highlightRange (Red)
            flashRange = NSRange(location: location, length: 1)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                flashRange = nil
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
