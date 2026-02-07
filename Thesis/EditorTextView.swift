import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var mode: EditorMode
    @Binding var cursorPosition: Int
    @Binding var highlightRange: NSRange? // Red (Deletion/Action)
    @Binding var flashRange: NSRange?     // Yellow (Navigation Flash)
    @Binding var diffChanges: [DiffChange]
    
    let onTextChange: () -> Void
    let onKeyPress: (String, NSEvent.ModifierFlags) -> Void
    let onModeChange: (EditorMode) -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        // ... [Identical to previous version] ...
        // Copy the makeNSView implementation from the previous answer exactly.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
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
        customTextView.insertionPointColor = NSColor.controlAccentColor
        customTextView.isSelectable = true
        customTextView.isEditable = true
        
        scrollView.documentView = customTextView
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
            if textView.selectedRange().location != cursorPosition {
                textView.setSelectedRange(range)
                textView.scrollRangeToVisible(range)
            }
        }
        
        // Update View State
        textView.isEditable = true
        textView.isSelectable = true
        textView.currentMode = mode
        
        if textView.window?.firstResponder != textView {
            textView.window?.makeFirstResponder(textView)
        }
        
        // RENDER HIGHLIGHTS
        // This consolidates all coloring logic (Red preview, Yellow flash, Green/Red diffs)
        renderHighlights(textView: textView)
        
        context.coordinator.parent = self
        textView.coordinator = context.coordinator
    }
    
    // NEW: Centralized Highlight Rendering
    private func renderHighlights(textView: CustomTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let textLength = (textView.string as NSString).length
        let fullRange = NSRange(location: 0, length: textLength)
        
        // 1. Clean Slate: Remove all temp attributes
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        
        // 2. Render Comp Mode Diffs (if active)
        if mode == .comp {
            for change in diffChanges {
                switch change.type {
                case .addition:
                    guard change.range.location + change.range.length <= textLength else { continue }
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor,
                        value: NSColor.systemGreen.withAlphaComponent(0.3),
                        forCharacterRange: change.range
                    )
                case .deletion:
                    if let displayRange = change.displayRange {
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
                case .unchanged: break
                }
            }
        }
        
        // 3. Render Action Highlights (RED)
        // Used for deletions, changes, etc.
        if let range = highlightRange, range.location + range.length <= textLength {
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.systemRed.withAlphaComponent(0.3),
                forCharacterRange: range
            )
        }
        
        // 4. Render Navigation Flash (YELLOW)
        // Used for w, b, h, j, k, l movement
        if let range = flashRange, range.location + range.length <= textLength {
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.7),
                forCharacterRange: range
            )
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // ... [Coordinator and CustomTextView classes remain identical to previous answer] ...
    // Reuse the Coordinator and CustomTextView code exactly as provided in the previous step.
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: CustomTextView?
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
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            switch parent.mode {
            case .freeText:
                return true
            case .insert(let context):
                guard let input = replacementString else { return true }
                if input.isEmpty { return true }
                
                switch context {
                case .word:
                    if input == " " || input == "\n" {
                        DispatchQueue.main.async { self.parent.onModeChange(.edit) }
                        return true
                    }
                case .sentence:
                    if input == "." || input == "!" || input == "?" {
                        DispatchQueue.main.async { self.parent.onModeChange(.edit) }
                        return true
                    }
                case .paragraph:
                    if input == "\n" {
                        let currentPos = parent.cursorPosition
                        let textLength = (parent.text as NSString).length
                        let hasNewlineBefore = currentPos > 0 && textLength > 0 &&
                            (parent.text as NSString).substring(with: NSRange(location: currentPos - 1, length: 1)) == "\n"
                        
                        if hasNewlineBefore {
                            DispatchQueue.main.async { self.parent.onModeChange(.edit) }
                            lastNewlinePosition = -1
                            return false
                        } else {
                            lastNewlinePosition = currentPos
                            return true
                        }
                    } else {
                        lastNewlinePosition = -1
                    }
                }
                return true
            case .edit, .comp, .command:
                return false
            }
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onKeyPress("\u{1B}", [])
                return true
            }
            
            let isNavCommand = commandSelector == #selector(NSResponder.moveUp(_:)) ||
                               commandSelector == #selector(NSResponder.moveDown(_:)) ||
                               commandSelector == #selector(NSResponder.moveLeft(_:)) ||
                               commandSelector == #selector(NSResponder.moveRight(_:))
            
            if isNavCommand {
                switch parent.mode {
                case .freeText: return false
                case .insert: return true
                default: return true
                }
            }
            
            switch parent.mode {
            case .insert, .freeText: return false
            default: return true
            }
        }
    }
}

class CustomTextView: NSTextView {
    var currentMode: EditorMode = .freeText
    weak var coordinator: EditorTextView.Coordinator?
    
    private var actualMode: EditorMode {
        return coordinator?.parent.mode ?? currentMode
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        switch actualMode {
        case .freeText:
            super.mouseDown(with: event)
        case .insert, .edit, .comp, .command:
            return
        }
    }
    
    override func keyDown(with event: NSEvent) {
        let mode = actualMode
        
        if event.keyCode == 53 {
            coordinator?.parent.onKeyPress("\u{1B}", event.modifierFlags)
            return
        }
        
        switch mode {
        case .edit, .comp, .command:
            if let characters = event.characters {
                coordinator?.parent.onKeyPress(characters, event.modifierFlags)
            }
            return
        case .insert, .freeText:
            super.keyDown(with: event)
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
