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
                    diffChanges: $diffChanges,  // BUGFIX #4: Pass diff changes for rendering
                    onTextChange: { handleTextChange() },
                    onKeyPress: { key, modifiers in handleKeyPress(key, modifiers: modifiers) },
                    onModeChange: { newMode in handleModeChange(newMode) }  // BUGFIX #2: Handle mode changes from delegate
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
    
    // BUGFIX #3: Display branch information
    private var branchInfo: String? {
        if document.isBranching, let parent = document.currentBranchParent {
            return "Branching from: \(parent.name)"
        }
        return nil
    }
    
    // Diff info for comp mode status bar
    private var currentDiffInfo: StatusBar.DiffInfo? {
        guard mode == .comp, !diffChanges.isEmpty else { return nil }
        
        let changeIndices = DiffGenerator.getChangeIndices(in: diffChanges)
        guard !changeIndices.isEmpty else { return nil }
        
        // Find which change index we're at
        let currentChangeArrayIndex = changeIndices.firstIndex(of: currentDiffIndex) ?? 0
        
        return StatusBar.DiffInfo(
            currentIndex: currentChangeArrayIndex,
            totalChanges: changeIndices.count,
            currentChange: currentDiffIndex < diffChanges.count ? diffChanges[currentDiffIndex] : nil
        )
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
    
    // BUGFIX #2: Handle mode changes triggered by the delegate
    private func handleModeChange(_ newMode: EditorMode) {
        mode = newMode
        if newMode == .edit {
            insertContext = nil
            lastNewlinePosition = -1
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
    
    // MARK: - Insert Mode
    // Note: Exit trigger logic is now handled in EditorTextView.Coordinator.shouldChangeTextIn
    // This handler is now simplified since the delegate handles exit conditions

    private func handleInsertMode(_ characters: String, context: InsertContext) {
        // ESC always exits to EDIT
        if characters == "\u{1B}" {
            mode = .edit
            insertContext = nil
            return
        }
        
        // All other character handling is done by the delegate's shouldChangeTextIn
        // The delegate blocks/allows characters and triggers mode changes as needed
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
        
        // Find the current word (if cursor is inside one)
        let currentWordEnd = words.first(where: {
            NSLocationInRange(cursorPosition, $0.range)
        }).map { $0.range.location + $0.range.length } ?? cursorPosition
        
        // Find the first word that starts AT OR AFTER the end of current word
        if let nextWord = words.first(where: { $0.range.location >= currentWordEnd }) {
            cursorPosition = nextWord.range.location
        }
    }

    private func moveToPreviousWord() {
        let words = TextAnalyzer.getWords(in: document.currentContent)
        
        // Find the last word that starts BEFORE the current cursor position
        // If we're at the start of a word, go to the previous word
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
        
        // BUGFIX #4: Navigate to first change if any
        if let firstChangeIndex = DiffGenerator.getChangeIndices(in: diffChanges).first {
            currentDiffIndex = firstChangeIndex
            // Move cursor to the first change
            if currentDiffIndex < diffChanges.count {
                cursorPosition = diffChanges[currentDiffIndex].range.location
            }
        }
    }
    
    private func handleCompMode(_ characters: String) {
        guard let char = characters.first else { return }
        
        switch char {
        case "n":
            // Next change
            if let next = DiffGenerator.findNextChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = next
                // Move cursor to the change (use displayRange for deletions)
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
            // Previous change
            if let prev = DiffGenerator.findPreviousChange(from: currentDiffIndex, in: diffChanges) {
                currentDiffIndex = prev
                // Move cursor to the change (use displayRange for deletions)
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
            diffChanges = []  // Clear diff data (and highlights via updateNSView)
            
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
    let branchInfo: String?  // BUGFIX #3: Show branch info
    let diffInfo: DiffInfo?  // Show current change info in comp mode
    
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
                // Draft info (when not in comp mode)
                Text(draftInfo)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(hasUnsavedChanges ? .orange : .secondary)
                
                if hasUnsavedChanges {
                    Text("*")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                }
                
                // BUGFIX #3: Branch indicator
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
                    // Move to comment field on Enter
                    focusedField = .comment
                }
            
            TextField("What changed in your thinking?", text: $comment)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .comment)
                .onSubmit {
                    // Save on Enter if both fields filled
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
            // Focus the name field on appear
            focusedField = .name
        }
    }
}
