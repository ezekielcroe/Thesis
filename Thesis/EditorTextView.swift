import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var mode: EditorMode
    @Binding var cursorPosition: Int
    @Binding var highlightRange: NSRange?
    @Binding var flashRange: NSRange?
    @Binding var diffChanges: [DiffChange]
    
    let onTextChange: () -> Void
    let onKeyPress: (String, NSEvent.ModifierFlags) -> Void
    let onModeChange: (EditorMode) -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
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
        customTextView.autoresizingMask = [.width]
        
        // Setup Appearance
        customTextView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        customTextView.isAutomaticQuoteSubstitutionEnabled = false
        customTextView.isAutomaticDashSubstitutionEnabled = false
        customTextView.allowsUndo = false // We handle undo manually
        customTextView.drawsBackground = true
        customTextView.backgroundColor = NSColor.textBackgroundColor
        customTextView.delegate = context.coordinator
        
        scrollView.documentView = customTextView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CustomTextView else { return }
        
        // 1. Pass Data
        textView.diffChanges = diffChanges
        textView.currentMode = mode
        
        // 2. Sync Text
        if textView.string != text {
            textView.string = text
        }
        
        // 3. Sync Cursor (Protected)
        // This check prevents the "Reverse Typing" bug by ignoring SwiftUI updates
        // that are merely echoing the cursor position we just typed.
        let currentPos = textView.selectedRange().location
        
        // We only force-update the cursor if we are NOT in strict insert mode (meaning we are navigating),
        // OR if the position discrepancy is large (meaning a programmatic jump/undo).
        let isStrictTyping = (mode == .insert(.word) || mode == .insert(.sentence) || mode == .insert(.paragraph))
        
        if !isStrictTyping || abs(currentPos - cursorPosition) > 1 {
            if cursorPosition >= 0 && cursorPosition <= (textView.string as NSString).length {
                let range = NSRange(location: cursorPosition, length: 0)
                if currentPos != cursorPosition {
                    textView.setSelectedRange(range)
                    textView.scrollRangeToVisible(range)
                }
            }
        }
        
        // 4. Update Highlights & Phantom Text
        textView.refreshHighlights(highlightRange: highlightRange, flashRange: flashRange)
        textView.updatePhantomText()
        
        context.coordinator.parent = self
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        
        init(_ parent: EditorTextView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // 1. Update bindings immediately
            parent.text = textView.string
            parent.cursorPosition = textView.selectedRange().location
            
            // 2. Notify parent
            parent.onTextChange()
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? CustomTextView else { return }
            
            // Update bindings
            parent.cursorPosition = textView.selectedRange().location
            
            // Update Phantom Text visibility based on new cursor location
            textView.updatePhantomText()
        }
        
        // RESTORED: Strict Mode Logic
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let input = replacementString else { return true }
            
            if case .insert(let context) = parent.mode {
                switch context {
                case .word:
                    // Exit on Space or Newline
                    if input == " " || input == "\n" {
                        DispatchQueue.main.async { self.parent.onModeChange(.edit) }
                        return true // Allow the space to be typed, then exit
                    }
                    
                case .sentence:
                    // Exit on Punctuation
                    if input == "." || input == "!" || input == "?" {
                        DispatchQueue.main.async { self.parent.onModeChange(.edit) }
                        return true // Allow punctuation, then exit
                    }
                    
                case .paragraph:
                    // Exit on Double Newline
                    if input == "\n" {
                        let text = textView.string as NSString
                        // Check if previous char was also newline
                        if affectedCharRange.location > 0 {
                            let prevCharRange = NSRange(location: affectedCharRange.location - 1, length: 1)
                            if prevCharRange.location + prevCharRange.length <= text.length {
                                let prevChar = text.substring(with: prevCharRange)
                                if prevChar == "\n" {
                                    DispatchQueue.main.async { self.parent.onModeChange(.edit) }
                                    return false // Consume the second newline to avoid triple spacing
                                }
                            }
                        }
                    }
                }
            }
            
            return true
        }
    }
}

class CustomTextView: NSTextView {
    var currentMode: EditorMode = .freeText
    var diffChanges: [DiffChange] = []
    
    // Subview for Inline Diff (Phantom Text)
    private lazy var phantomView: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.8)
        label.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9)
        label.drawsBackground = true
        label.isBordered = false
        label.isHidden = true
        label.wantsLayer = true
        label.layer?.cornerRadius = 4
        return label
    }()
    
    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
        self.addSubview(phantomView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Phantom Text Logic
    
    func updatePhantomText() {
        guard currentMode == .comp, let layoutManager = self.layoutManager, let textContainer = self.textContainer else {
            phantomView.isHidden = true
            return
        }
        
        let cursorLoc = self.selectedRange().location
        
        // Find if cursor is inside a diff change that has oldText
        guard let change = diffChanges.first(where: {
            $0.type == .addition &&
            $0.oldText != nil &&
            NSLocationInRange(cursorLoc, $0.range)
        }), let oldText = change.oldText else {
            phantomView.isHidden = true
            return
        }
        
        // Calculate Position
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: change.range.location)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        
        // Configure View
        phantomView.stringValue = "PREV: \(oldText)"
        phantomView.sizeToFit()
        
        // Position: 18pts above the line
        let xPos = rect.origin.x
        let yPos = rect.origin.y - 18
        
        phantomView.frame.origin = NSPoint(x: xPos, y: yPos)
        phantomView.isHidden = false
    }
    
    // MARK: - Highlight Logic
    
    func refreshHighlights(highlightRange: NSRange?, flashRange: NSRange?) {
        guard let layoutManager = self.layoutManager else { return }
        let textLength = (self.string as NSString).length
        let fullRange = NSRange(location: 0, length: textLength)
        
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        
        // 1. Diff Colors
        if currentMode == .comp {
            for change in diffChanges {
                switch change.type {
                case .addition:
                    if change.range.location + change.range.length <= textLength {
                        layoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.2), forCharacterRange: change.range)
                    }
                case .deletion:
                    if let displayRange = change.displayRange {
                        let markerStart = min(displayRange.location, max(0, textLength - 1))
                        let markerRange = NSRange(location: markerStart, length: 1)
                        if markerStart < textLength {
                            layoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.5), forCharacterRange: markerRange)
                        }
                    }
                case .unchanged: break
                }
            }
        }
        
        // 2. Action Highlights
        if let range = highlightRange, range.location + range.length <= textLength {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.3), forCharacterRange: range)
        }
        
        // 3. Navigation Flash
        if let range = flashRange, range.location + range.length <= textLength {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.7), forCharacterRange: range)
        }
    }
    
    // MARK: - Event Handling
    
    override func keyDown(with event: NSEvent) {
        // Modal logic interception
        if event.keyCode == 53 { // ESC
            if let coord = delegate as? EditorTextView.Coordinator {
                coord.parent.onKeyPress("\u{1B}", event.modifierFlags)
            }
            return
        }
        
        // Pass to parent logic for navigation/commands
        if currentMode == .edit || currentMode == .comp || currentMode == .command("") {
            if let characters = event.characters, let coord = delegate as? EditorTextView.Coordinator {
                coord.parent.onKeyPress(characters, event.modifierFlags)
            }
            return
        }
        
        super.keyDown(with: event)
    }
}
