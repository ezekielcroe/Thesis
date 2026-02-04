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
    @State private var mode: EditorMode = .freeText  // Start in FREE TEXT
    @State private var commandBuffer: String = ""
    @State private var insertContext: InsertContext?
    @State private var lastNewlinePosition: Int = -1  // For paragraph mode
    @State private var pendingCommand: PendingCommand?
    @State private var highlightRange: NSRange?
    @State private var cursorPosition: Int = 0
    @State private var undoStack = UndoStack()
    @State private var showingFirstDraftSheet = false
    @State private var showingPrintSheet = false
    @State private var diffChanges: [DiffChange] = []
    @State private var currentDiffIndex: Int = 0
    @State private var stats: TextStats = TextStats(paragraphCount: 0, sentenceCount: 0, wordCount: 0)
    
    var body: some View {
        VStack(spacing: 0) {
            // Main editor area
            ZStack {
                EditorTextView(
                    text: $document.currentContent,
                    mode: $mode,
                    cursorPosition: $cursorPosition,
                    highlightRange: $highlightRange,
                    onTextChange: { handleTextChange() },
                    onKeyPress: { key, modifiers in handleKeyPress(key, modifiers: modifiers) }
                )
                .border(mode.borderColor, width: 3)
            }
            
            // Status bar
            StatusBar(
                mode: mode,
                commandBuffer: commandBuffer,
                stats: stats,
                draftInfo: draftInfo,
                hasUnsavedChanges: document.hasUnsavedChanges
            )
        }
        .onAppear {
            DispatchQueue.main.async {
                updateStats()
            }
            // Start in FREE TEXT if no drafts, EDIT if we have drafts
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
    
    private func updateStats() {
        // Calculate stats using TextAnalyzer
        let paragraphs = TextAnalyzer.getParagraphs(in: document.currentContent)
        let sentences = TextAnalyzer.getSentences(in: document.currentContent)
        let words = TextAnalyzer.getWords(in: document.currentContent)
        
        // Create the stats object
        let newStats = TextStats(
            paragraphCount: paragraphs.count,
            sentenceCount: sentences.count,
            wordCount: words.count
        )
        
        // FIX: Defer state modification to avoid "modifying state during view update"
        DispatchQueue.main.async {
            self.stats = newStats
        }
    }

    private func handleTextChange() {
            DispatchQueue.main.async {
                self.updateStats()
            }
            
            // Use a switch to match .edit OR any case of .insert
            switch mode {
            case .insert, .edit:
                document.updateWorkingDraft()
            default:
                break
            }
        }
    
    private func handleKeyPress(_ characters: String, modifiers: NSEvent.ModifierFlags) {
        // Handle Cmd+D for comp mode (only in EDIT mode)
        if modifiers.contains(.command) && characters == "d" && mode == .edit {
            enterCompMode()
            return
        }
        
        // Handle Cmd+S for print (only in EDIT mode)
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
        // Only ESC exits - everything else is passed to editor
        if characters == "\u{1B}" { // ESC
            if !document.currentContent.isEmpty {
                showingFirstDraftSheet = true
            }
        }
        // All other keys pass through naturally
    }
    
    // MARK: - Insert Mode (COMPLETE FIX)

    private func handleInsertMode(_ characters: String, context: InsertContext) {
        // ESC always exits to EDIT
        if characters == "\u{1B}" {
            mode = .edit
            insertContext = nil
            return
        }
        
        // Check exit conditions based on context
        switch context {
        case .word:
            // Exit on space or newline (block the character)
            if characters == " " || characters == "\n" {
                mode = .edit
                insertContext = nil
                // Don't type the space/newline
                return
            }
            
        case .sentence:
            // Exit on . ! ? (allow the character first)
            if characters == "." || characters == "!" || characters == "?" {
                // Let the character be typed, then exit
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.mode = .edit
                    self.insertContext = nil
                }
            }
            
        case .paragraph:
            // Exit on double newline
            if characters == "\n" {
                if lastNewlinePosition == cursorPosition - 1 {
                    // Second newline in a row - exit
                    mode = .edit
                    insertContext = nil
                    lastNewlinePosition = -1
                    return
                } else {
                    lastNewlinePosition = cursorPosition
                }
            } else {
                lastNewlinePosition = -1
            }
        }
        
        // All other keys pass through to editor
    }

    // MARK: - Edit Mode

    private func handleEditMode(_ characters: String, modifiers: NSEvent.ModifierFlags) {
        guard let char = characters.first else { return }
        
        // Check for multi-character commands first
        if !commandBuffer.isEmpty {
            let combined = commandBuffer + String(char)
            
            // Two-character commands
            if combined == "dw" {
                executeDeleteWord(forward: true)
                commandBuffer = ""
                return
            } else if combined == "db" {
                executeDeleteWord(forward: false)
                commandBuffer = ""
                return
            } else if combined == "cw" {
                executeChangeWord()
                commandBuffer = ""
                return
            }
            
            // Partial three-character commands
            if combined == "da" || combined == "ca" {
                commandBuffer = combined
                return
            }
            
            // Complete three-character commands
            if combined == "das" {
                executeDeleteSentence()
                commandBuffer = ""
                return
            } else if combined == "dap" {
                executeDeleteParagraph()
                commandBuffer = ""
                return
            } else if combined == "cas" {
                executeChangeSentence()
                commandBuffer = ""
                return
            } else if combined == "cap" {
                executeChangeParagraph()
                commandBuffer = ""
                return
            }
            
            // Invalid combination - clear and process as single
            commandBuffer = ""
        }
        
        // Single character commands
        switch char {
        case "h":
            moveToPreviousSentence()
            
        case "l":
            moveToNextSentence()
            
        case "j":
            moveToNextParagraph()
            
        case "k":
            moveToPreviousParagraph()
            
        case "w":
            if commandBuffer.isEmpty {
                moveToNextWord()
            }
            // If buffer has 'd' or 'c', this completes 'dw' or 'cw' (handled above)
            
        case "b":
            if commandBuffer.isEmpty {
                moveToPreviousWord()
            }
            // If buffer has 'd', this completes 'db' (handled above)
            
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
            
        case "i":
            mode = .insert(.word)
            insertContext = .word
            commandBuffer = ""
            
        case "a":
            if commandBuffer.isEmpty {
                mode = .insert(.sentence)
                insertContext = .sentence
            }
            // If buffer is 'd' or 'c', keep waiting for 's' or 'p'
            
        case "s":
            // Only valid after 'da' or 'ca'
            // Will be handled by multi-char check above
            break
            
        case "p":
            // Only valid after 'da' or 'ca'
            // Will be handled by multi-char check above
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
    
    // MARK: - Navigation Commands
    
    private func moveToPreviousSentence() {
        if let prev = TextAnalyzer.getPreviousSentence(from: cursorPosition, in: document.currentContent) {
            cursorPosition = prev.range.location
        }
    }

    private func moveToNextSentence() {
        if let next = TextAnalyzer.getNextSentence(from: cursorPosition, in: document.currentContent) {
            cursorPosition = next.range.location
        }
    }

    private func moveToPreviousParagraph() {
        if let prev = TextAnalyzer.getPreviousParagraph(from: cursorPosition, in: document.currentContent) {
            cursorPosition = prev.range.location
        }
    }

    private func moveToNextParagraph() {
        if let next = TextAnalyzer.getNextParagraph(from: cursorPosition, in: document.currentContent) {
            cursorPosition = next.range.location
        }
    }

    private func moveToNextWord() {
        let words = TextAnalyzer.getWords(in: document.currentContent)
        
        // Find the first word that starts AFTER the current cursor position
        if let nextWord = words.first(where: { $0.range.location > cursorPosition }) {
            cursorPosition = nextWord.range.location
        }
    }

    private func moveToPreviousWord() {
        let words = TextAnalyzer.getWords(in: document.currentContent)
        
        // Find the last word that starts BEFORE the current cursor position
        if let prevWord = words.last(where: { $0.range.location < cursorPosition }) {
            cursorPosition = prevWord.range.location
        }
    }
    
    // MARK: - Delete Commands
    
    private func executeDeleteWord(forward: Bool) {
        let words = TextAnalyzer.getWords(in: document.currentContent)
        let nsText = document.currentContent as NSString
        
        if forward {
            // Find word at or after cursor
            guard let word = words.first(where: { $0.range.location >= cursorPosition }) else { return }
            
            // Calculate range including trailing space
            var deleteRange = word.range
            let endPos = deleteRange.location + deleteRange.length
            
            // Include trailing space if it exists
            if endPos < nsText.length {
                let nextChar = nsText.substring(with: NSRange(location: endPos, length: 1))
                if nextChar == " " || nextChar == "\n" {
                    deleteRange.length += 1
                }
            }
            
            highlightRangeBriefly(deleteRange) {
                self.deleteRange(deleteRange)
            }
            
        } else {
            // Find word before cursor
            guard let word = words.last(where: { $0.range.location + $0.range.length <= cursorPosition }) else { return }
            
            // Calculate range including leading space
            var deleteRange = word.range
            
            // Include leading space if it exists
            if deleteRange.location > 0 {
                let prevChar = nsText.substring(with: NSRange(location: deleteRange.location - 1, length: 1))
                if prevChar == " " || prevChar == "\n" {
                    deleteRange.location -= 1
                    deleteRange.length += 1
                }
            }
            
            highlightRangeBriefly(deleteRange) {
                self.deleteRange(deleteRange)
            }
        }
    }
    
    private func executeDeleteSentence() {
        guard let sentence = TextAnalyzer.getSentenceAt(position: cursorPosition, in: document.currentContent) else { return }
        
        highlightRangeBriefly(sentence.range) {
            deleteRange(sentence.range)
        }
    }
    
    private func executeDeleteParagraph() {
        guard let paragraph = TextAnalyzer.getParagraphAt(position: cursorPosition, in: document.currentContent) else { return }
        
        highlightRangeBriefly(paragraph.range) {
            deleteRange(paragraph.range)
        }
    }
    
    private func executeDeleteToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        
        highlightRangeBriefly(rest.range) {
            deleteRange(rest.range)
        }
    }
    
    private func deleteRange(_ range: NSRange) {
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
        
        // Find word at or immediately after cursor
        guard let word = words.first(where: {
            $0.range.location >= cursorPosition ||
            NSLocationInRange(cursorPosition, $0.range)
        }) else { return }
        
        highlightRangeBriefly(word.range) {
            deleteRange(word.range)
            mode = .insert(.word)
            insertContext = .word
        }
    }


    private func executeChangeSentence() {
        guard let sentence = TextAnalyzer.getSentenceAt(position: cursorPosition, in: document.currentContent) else { return }
        
        highlightRangeBriefly(sentence.range) {
            deleteRange(sentence.range)
            mode = .insert(.sentence)
            insertContext = .sentence
        }
    }

    private func executeChangeParagraph() {
        guard let paragraph = TextAnalyzer.getParagraphAt(position: cursorPosition, in: document.currentContent) else { return }
        
        highlightRangeBriefly(paragraph.range) {
            deleteRange(paragraph.range)
            mode = .insert(.paragraph)
            insertContext = .paragraph
        }
    }

    private func executeChangeToEnd() {
        guard let rest = TextAnalyzer.getRestOfSentence(from: cursorPosition, in: document.currentContent) else { return }
        
        highlightRangeBriefly(rest.range) {
            deleteRange(rest.range)
            mode = .insert(.sentence)
            insertContext = .sentence
        }
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
    }
    
    private func handleCompMode(_ characters: String) {
        guard let char = characters.first else { return }
        
        switch char {
        case "n":
            // Next change
            if let next = DiffGenerator.findNextChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = next
            }
            
        case "p":
            // Previous change
            if let prev = DiffGenerator.findPreviousChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = prev
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
        
        // Add character to command string
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
        highlightRange = range
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            highlightRange = nil
            completion()
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
            
            // Draft info
            Text(draftInfo)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(hasUnsavedChanges ? .orange : .secondary)
            
            if hasUnsavedChanges {
                Text("*")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.orange)
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
                .keyboardShortcut(.escape) // FIX: Add escape shortcut
                
                Button("Save") {
                    if !draftName.isEmpty {
                        dismiss()
                        onSave(draftName)
                    }
                }
                .keyboardShortcut(.return) // FIX: Add return shortcut
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
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) var dismiss
    
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
            
            TextField("What changed in your thinking?", text: $comment)
                .textFieldStyle(.roundedBorder)
            
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
                .keyboardShortcut(.return)
                .disabled(draftName.isEmpty || comment.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
}

