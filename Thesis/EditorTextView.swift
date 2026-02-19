// EditorTextView.swift — Thesis
// NSViewRepresentable wrapping NSTextView with modal editing support

import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var mode: EditorMode
    @Binding var cursorPosition: Int
    @Binding var highlightRange: NSRange?
    @Binding var flashRange: NSRange?
    @Binding var selectionRange: NSRange?
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
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        
        let textView = ModalNSTextView(
            frame: NSRect(origin: .zero, size: contentSize),
            textContainer: textContainer
        )
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.delegate = context.coordinator
        
        let coordinator = context.coordinator
        textView.onKeyPress = { key, mods in
            coordinator.parent.onKeyPress(key, mods)
        }
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ModalNSTextView else { return }
        textView.currentMode = mode
        textView.diffChanges = diffChanges
        
        if textView.string != text {
            textView.string = text
        }
        
        switch mode {
        case .freeText, .insert:
            textView.isEditable = true
            textView.isSelectable = true
        default:
            textView.isEditable = false
            textView.isSelectable = true
        }
        
        let safePos = min(cursorPosition, textView.string.count)
        if textView.selectedRange().location != safePos {
            textView.setSelectedRange(NSRange(location: safePos, length: 0))
            textView.scrollRangeToVisible(NSRange(location: safePos, length: 0))
        }
        
        applyHighlights(to: textView)
    }
    
    private func applyHighlights(to textView: ModalNSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textStorage = textView.textStorage else { return }
        
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }
        
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        
        let safe: (NSRange) -> NSRange = { r in
            TextAnalyzer.safeRange(r, in: textStorage.length)
        }
        
        if let selection = selectionRange, case .visual = mode {
            let r = safe(selection)
            if r.length > 0 {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.4),
                    forCharacterRange: r
                )
            }
        }
        
        if let highlight = highlightRange {
            let r = safe(highlight)
            if r.length > 0 {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.systemYellow.withAlphaComponent(0.3),
                    forCharacterRange: r
                )
            }
        }
        
        if let flash = flashRange {
            let r = safe(flash)
            if r.length > 0 {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.systemBlue.withAlphaComponent(0.3),
                    forCharacterRange: r
                )
            }
        }
        
        if mode == .comp {
            for change in diffChanges {
                switch change.type {
                case .addition:
                    let r = safe(change.range)
                    guard r.length > 0 else { continue }
                    let color: NSColor = {
                        switch change.semanticType {
                        case .refined:  return .systemBlue
                        case .replaced: return .systemOrange
                        default:        return .systemGreen
                        }
                    }()
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor, value: color.withAlphaComponent(0.2),
                        forCharacterRange: r
                    )
                case .moved:
                    let r = safe(change.range)
                    guard r.length > 0 else { continue }
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor,
                        value: NSColor.systemPurple.withAlphaComponent(0.15),
                        forCharacterRange: r
                    )
                case .deletion, .unchanged:
                    break
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        private var isUpdating = false
        
        init(_ parent: EditorTextView) { self.parent = parent }
        
        func textDidChange(_ notification: Notification) {
            guard !isUpdating else { return }
            guard let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = textView.string
            parent.cursorPosition = textView.selectedRange().location
            parent.onTextChange()
            isUpdating = false
        }
    }
}

// MARK: - Custom NSTextView

class ModalNSTextView: NSTextView {
    var currentMode: EditorMode = .freeText
    var diffChanges: [DiffChange] = []
    var onKeyPress: ((String, NSEvent.ModifierFlags) -> Void)?
    
    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""
        let modifiers = event.modifierFlags
        
        switch currentMode {
        case .freeText:
            if chars == "\u{1B}" { onKeyPress?(chars, modifiers); return }
            super.keyDown(with: event)
            
        case .insert:
            if chars == "\u{1B}" { onKeyPress?(chars, modifiers); return }
            super.keyDown(with: event)
            DispatchQueue.main.async { [weak self] in
                self?.onKeyPress?(chars, modifiers)
            }
            
        case .normal, .visual, .command, .comp:
            onKeyPress?(chars, modifiers)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        switch currentMode {
        case .freeText, .insert, .normal, .visual, .comp:
            super.mouseDown(with: event)
        case .command:
            break
        }
    }
}
