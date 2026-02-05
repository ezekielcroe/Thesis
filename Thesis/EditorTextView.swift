import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var mode: EditorMode
    @Binding var cursorPosition: Int
    @Binding var highlightRange: NSRange?
    @Binding var diffChanges: [DiffChange]  // NEW: For diff visualization
    
    let onTextChange: () -> Void
    let onKeyPress: (String, NSEvent.ModifierFlags) -> Void
    let onModeChange: (EditorMode) -> Void  // NEW: Callback for mode changes from delegate
    
    func makeNSView(context: Context) -> NSScrollView {
        // Create scroll view manually to ensure we use our CustomTextView
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // Create our custom text view with TextKit 1 for reliable cursor control
        // TextKit 2 (default in macOS 13+) ignores shouldDrawInsertionPoint override
        let contentSize = scrollView.contentSize
        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        
        let customTextView = CustomTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        customTextView.minSize = NSSize(width: 0, height: contentSize.height)
        customTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        customTextView.isVerticallyResizable = true
        customTextView.isHorizontallyResizable = false
        customTextView.autoresizingMask = [.width]
        
        customTextView.delegate = context.coordinator
        customTextView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        customTextView.isAutomaticQuoteSubstitutionEnabled = false
        customTextView.isAutomaticDashSubstitutionEnabled = false
        customTextView.isAutomaticSpellingCorrectionEnabled = false
        customTextView.allowsUndo = false
        customTextView.drawsBackground = true
        customTextView.backgroundColor = NSColor.textBackgroundColor
        
        // Configuration for cursor visibility
        customTextView.insertionPointColor = NSColor.controlAccentColor
        customTextView.isSelectable = true
        
        // ALWAYS keep editable = true
        // We simulate "read-only" via delegate interception (see shouldChangeTextIn)
        customTextView.isEditable = true
        
        // Set the text view as the document view
        scrollView.documentView = customTextView
        
        // Set coordinator reference for direct communication
        context.coordinator.textView = customTextView
        customTextView.coordinator = context.coordinator
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CustomTextView else { return }
        
        // Sync text
        if textView.string != text {
            textView.string = text
        }
        
        // Sync cursor
        if cursorPosition >= 0 && cursorPosition <= text.count {
            let range = NSRange(location: cursorPosition, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
        
        // Sync highlights (for delete/change previews)
        if let range = highlightRange {
            textView.showFindIndicator(for: range)
        }
        
        // BUGFIX #1: ALWAYS keep isEditable = true
        // The "read-only" behavior is enforced via shouldChangeTextIn delegate method
        textView.isEditable = true
        textView.isSelectable = true
        textView.currentMode = mode
        
        // Ensure focus
        if textView.window?.firstResponder != textView {
            textView.window?.makeFirstResponder(textView)
        }
        
        // BUGFIX #4: Render diff visualization in comp mode
        if mode == .comp {
            textView.textColor = NSColor.labelColor // Keep text visible
            renderDiffHighlights(textView: textView)
        } else {
            // Clear any diff highlights when not in comp mode
            clearDiffHighlights(textView: textView)
            textView.textColor = NSColor.labelColor
        }
        
        context.coordinator.parent = self
        textView.coordinator = context.coordinator
    }
    
    // MARK: - BUGFIX #4: Diff Rendering
    
    private func renderDiffHighlights(textView: CustomTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        
        let textLength = (textView.string as NSString).length
        let fullRange = NSRange(location: 0, length: textLength)
        
        // Clear existing temporary attributes
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        
        // Apply highlights for diff changes
        for change in diffChanges {
            switch change.type {
            case .addition:
                // Validate range is within bounds
                guard change.range.location + change.range.length <= textLength else {
                    continue
                }
                // Green background for added text
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.systemGreen.withAlphaComponent(0.3),
                    forCharacterRange: change.range
                )
                
            case .deletion:
                // Show a red underline at the position where text was deleted
                // Use displayRange which indicates where in the new text to show the marker
                if let displayRange = change.displayRange {
                    // Mark a small range (or the character before) with red to indicate deletion occurred here
                    let markerStart = min(displayRange.location, textLength > 0 ? textLength - 1 : 0)
                    let markerLength = min(1, textLength - markerStart)
                    if markerLength > 0 {
                        let markerRange = NSRange(location: markerStart, length: markerLength)
                        layoutManager.addTemporaryAttribute(
                            .backgroundColor,
                            value: NSColor.systemRed.withAlphaComponent(0.2),
                            forCharacterRange: markerRange
                        )
                    }
                }
                
            case .unchanged:
                // No highlighting for unchanged text
                break
            }
        }
    }
    
    private func clearDiffHighlights(textView: CustomTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: CustomTextView?
        
        // Track last newline position for paragraph mode
        private var lastNewlinePosition: Int = -1
        
        init(_ parent: EditorTextView) {
            self.parent = parent
            super.init()
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            parent.text = textView.string
            parent.cursorPosition = textView.selectedRange().location
            parent.onTextChange()
        }
        
        // MARK: - BUGFIX #2: Synchronous Input Filtering
        // This is the KEY fix for constrained insert mode triggers.
        // By intercepting here, we BLOCK characters BEFORE they enter the text storage.
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            
            // Handle based on current mode
            switch parent.mode {
            case .freeText:
                // Allow all typing in free text mode
                return true
                
            case .insert(let context):
                guard let input = replacementString else { return true }
                
                // Always allow backspace/deletion
                if input.isEmpty {
                    return true
                }
                
                // BUGFIX #2: Check exit triggers BEFORE allowing the character
                switch context {
                case .word:
                    // Exit on space or newline - ALLOW the space, then exit
                    if input == " " || input == "\n" {
                        // Switch mode asynchronously to avoid state modification during view update
                        DispatchQueue.main.async {
                            self.parent.onModeChange(.edit)
                        }
                        return true  // Allow the space/newline to be typed, then exit
                    }
                    
                case .sentence:
                    // Exit AFTER punctuation - ALLOW the character, then exit
                    if input == "." || input == "!" || input == "?" {
                        DispatchQueue.main.async {
                            self.parent.onModeChange(.edit)
                        }
                        return true  // Allow the punctuation to be typed
                    }
                    
                case .paragraph:
                    // Exit on double newline
                    if input == "\n" {
                        let currentPos = parent.cursorPosition
                        let textLength = (parent.text as NSString).length
                        
                        // Check if the character before cursor is also a newline
                        let hasNewlineBefore = currentPos > 0 && textLength > 0 &&
                            (parent.text as NSString).substring(with: NSRange(location: currentPos - 1, length: 1)) == "\n"
                        
                        if hasNewlineBefore {
                            DispatchQueue.main.async {
                                self.parent.onModeChange(.edit)
                            }
                            lastNewlinePosition = -1
                            return false  // Block the second newline
                        } else {
                            lastNewlinePosition = currentPos
                            return true  // Allow first newline
                        }
                    } else {
                        lastNewlinePosition = -1
                    }
                }
                
                return true  // Allow all other characters in insert mode
                
            case .edit, .comp, .command:
                // BUGFIX #1: Block ALL text changes in non-typing modes
                // This makes the view "virtually read-only" while keeping cursor visible
                return false
            }
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // 1. Always Handle ESC in parent
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onKeyPress("\u{1B}", [])
                return true
            }
            
            // 2. Always Allow Arrow Keys (for navigation in all modes)
            if commandSelector == #selector(NSResponder.moveUp(_:)) ||
               commandSelector == #selector(NSResponder.moveDown(_:)) ||
               commandSelector == #selector(NSResponder.moveLeft(_:)) ||
               commandSelector == #selector(NSResponder.moveRight(_:)) {
                return false
            }
            
            // 3. Mode-Specific Behavior
            switch parent.mode {
            case .insert, .freeText:
                // Allow NSTextView to handle standard commands (Enter, Delete, etc.)
                return false
            default:
                // Intercept all other commands in Edit/Comp modes
                return true
            }
        }
    }
}

// MARK: - Custom NSTextView

class CustomTextView: NSTextView {
    // Track current mode - kept for backwards compatibility but coordinator.parent.mode is source of truth
    var currentMode: EditorMode = .freeText
    
    // Reference to coordinator for direct communication and real-time mode access
    weak var coordinator: EditorTextView.Coordinator?
    
    // Get the actual current mode from the coordinator's parent binding (real-time)
    private var actualMode: EditorMode {
        return coordinator?.parent.mode ?? currentMode
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        let mode = actualMode  // Use binding-backed mode for real-time accuracy
        
        // Handle ESC specially - always send to parent
        if event.keyCode == 53 { // ESC key
            coordinator?.parent.onKeyPress("\u{1B}", event.modifierFlags)
            return
        }
        
        // For edit/comp/command modes, intercept ALL keys and send to parent handler
        switch mode {
        case .edit, .comp, .command:
            if let characters = event.characters {
                coordinator?.parent.onKeyPress(characters, event.modifierFlags)
            }
            // Do NOT call super (suppress system beep/input)
            return
            
        case .insert, .freeText:
            // For insert/freeText modes, let NSTextView handle normally
            // The shouldChangeTextIn delegate will filter based on context
            super.keyDown(with: event)
        }
    }
    
    // Always draw insertion point (for Bug #1 fix)
    override var shouldDrawInsertionPoint: Bool {
        return true
    }
    
    override func updateInsertionPointStateAndRestartTimer(_ restartTimer: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartTimer)
        needsDisplay = true
    }
}
