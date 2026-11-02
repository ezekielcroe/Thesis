// EditorTextView.swift — Thesis
// The NSTextView that holds the text. It is the single source of truth while editing:
// every change (typing, engine commands, undo) flows from here into the Document.

import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    @ObservedObject var document: Document
    @ObservedObject var engine: EditorEngine

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, engine: engine)
    }

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

        let textView = ModalTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        let baseFont = NSFont.systemFont(ofSize: 16)
        let font = baseFont.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 16) } ?? baseFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = 6

        textView.isRichText = false
        textView.font = font
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor]
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.allowsUndo = true
        textView.isEditable = true    // always: normal mode blocks typing in keyDown instead,
                                      // so engine edits still go through the undo system
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 32, height: 24)

        textView.string = document.content
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        }
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        // Delegates last, so loading the text isn't treated as an edit.
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.engine = engine
        engine.attach(textView)

        scrollView.documentView = textView
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ModalTextView else { return }
        textView.insertionPointColor = engine.mode == .insert ? .textColor : .systemBlue
        textView.showNotes(document.notes)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        let document: Document
        let engine: EditorEngine
        /// One undo history per document, separate from the title field's.
        let undoManager = UndoManager()

        init(document: Document, engine: EditorEngine) {
            self.document = document
            self.engine = engine
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            document.content = textView.string
            document.lastModified = Date()
            engine.textDidChange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            engine.selectionDidChange()
        }

        /// Sees every character change, whatever caused it, so notes stay attached.
        func textStorage(_ textStorage: NSTextStorage,
                         didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange,
                         changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            let inserted = editedRange.length
            let removed = inserted - delta
            let newText = textStorage.string
            // Don't publish from inside the text system's editing pass.
            DispatchQueue.main.async { [document] in
                document.applyEdit(location: editedRange.location, removed: removed,
                                   inserted: inserted, newText: newText)
            }
        }
    }
}

// MARK: - The text view

final class ModalTextView: NSTextView, TextBuffer {
    weak var engine: EditorEngine?

    /// Arrows, Home/End, Page Up/Down keep their usual meaning in every mode.
    private static let passthroughKeyCodes: Set<UInt16> = [123, 124, 125, 126, 115, 116, 119, 121]

    override func keyDown(with event: NSEvent) {
        guard let engine = engine else { super.keyDown(with: event); return }

        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "s" { engine.openReview(); return }
            super.keyDown(with: event)
            return
        }
        if engine.mode == .insert {
            if event.keyCode == 53 { engine.handle(.escape) } else { super.keyDown(with: event) }
            return
        }
        if Self.passthroughKeyCodes.contains(event.keyCode) {
            super.keyDown(with: event)
            return
        }
        if let key = KeyInput(event: event) { engine.handle(key) }
    }

    // MARK: TextBuffer

    var bufferText: String { string }

    var cursorRange: NSRange {
        get { selectedRange() }
        set { setSelectedRange(clamp(newValue)) }
    }

    func replaceText(in range: NSRange, with replacement: String) {
        let target = clamp(range)
        guard shouldChangeText(in: target, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: target, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: target.location + replacement.utf16Length, length: 0))
    }

    func undoEdit() {
        if undoManager?.canUndo == true { undoManager?.undo() } else { NSSound.beep() }
    }

    func redoEdit() {
        if undoManager?.canRedo == true { undoManager?.redo() } else { NSSound.beep() }
    }

    func endTyping() { breakUndoCoalescing() }

    func moveVisualLine(down: Bool) {
        if down { moveDown(nil) } else { moveUp(nil) }
    }

    func revealCursor() { scrollRangeToVisible(selectedRange()) }

    func flash(_ range: NSRange) {
        let target = clamp(range)
        guard target.length > 0 else { return }
        showFindIndicator(for: target)
    }

    func setHighlight(_ range: NSRange?) {
        guard let layoutManager = layoutManager else { return }
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        guard let range = range else { return }
        let target = clamp(range)
        guard target.length > 0 else { return }
        layoutManager.addTemporaryAttribute(
            .backgroundColor,
            value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.6),
            forCharacterRange: target
        )
    }

    /// Dotted purple underline under text that has an open note.
    func showNotes(_ notes: [Note]) {
        guard let layoutManager = layoutManager else { return }
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        let style = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue
        for note in notes where !note.resolved && !note.isDetached {
            let target = clamp(note.range)
            guard target.length > 0 else { continue }
            layoutManager.addTemporaryAttributes(
                [.underlineStyle: style, .underlineColor: NSColor.systemPurple],
                forCharacterRange: target
            )
        }
    }

    private var fullRange: NSRange { NSRange(location: 0, length: string.utf16Length) }

    private func clamp(_ range: NSRange) -> NSRange {
        let length = string.utf16Length
        let location = max(0, min(range.location, length))
        return NSRange(location: location, length: max(0, min(range.length, length - location)))
    }
}

extension KeyInput {
    init?(event: NSEvent) {
        switch event.keyCode {
        case 53: self = .escape; return
        case 36, 76: self = .enter; return
        case 51: self = .backspace; return
        default: break
        }
        if event.modifierFlags.contains(.control) {
            guard let c = event.charactersIgnoringModifiers?.lowercased().first else { return nil }
            self = .ctrl(c)
            return
        }
        guard let c = event.characters?.first else { return nil }
        self = .char(c)
    }
}
