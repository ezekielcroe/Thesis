import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var mode: EditorMode
    @Binding var cursorPosition: Int
    @Binding var highlightRange: NSRange?
    
    let onTextChange: () -> Void
    let onKeyPress: (String, NSEvent.ModifierFlags) -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        
        let customTextView = CustomTextView()
        scrollView.documentView = customTextView
        
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
        
        context.coordinator.textView = customTextView
        
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
        
        // Sync highlights
        if let range = highlightRange {
            textView.showFindIndicator(for: range)
        }
        
        // Logic: Enable editing for Typing modes (Insert/FreeText), disable for Command modes
        switch mode {
        case .insert, .freeText:
            textView.isEditable = true
        default:
            textView.isEditable = false
        }
        
        textView.isSelectable = true
        textView.currentMode = mode
        
        // Ensure focus
        if textView.window?.firstResponder != textView {
            textView.window?.makeFirstResponder(textView)
        }
        
        // Visual feedback
        if mode == .comp {
            textView.textColor = NSColor.secondaryLabelColor
        } else {
            textView.textColor = NSColor.labelColor
        }
        
        context.coordinator.parent = self
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: CustomTextView?
        
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
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // 1. Always Handle ESC in parent
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onKeyPress("\u{1B}", [])
                return true
            }
            
            // 2. Always Allow Arrow Keys
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
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            // Allow typing only in Insert or FreeText modes
            switch parent.mode {
            case .insert, .freeText:
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Custom NSTextView

class CustomTextView: NSTextView {
    // Default to .insert(.word) to satisfy initialization requirements
    var currentMode: EditorMode = .insert(.word)
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        switch currentMode {
        case .insert, .freeText:
            // Standard typing behavior
            super.keyDown(with: event)
            
        case .edit, .comp, .command:
            // Intercept keys and send to parent handler
            if let characters = event.characters {
                if let coordinator = delegate as? EditorTextView.Coordinator {
                    coordinator.parent.onKeyPress(characters, event.modifierFlags)
                }
            }
            // Do NOT call super (suppress system beep/input)
        }
    }
    
    override var shouldDrawInsertionPoint: Bool {
        return true
    }
    
    override func updateInsertionPointStateAndRestartTimer(_ restartTimer: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartTimer)
        needsDisplay = true
    }
}
