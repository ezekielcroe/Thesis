// MarkdownPreview.swift — Thesis
// Read-only rendering of the document as formatted text (⇧⌘P, :preview).
// Keys: j/k or arrows scroll, space / shift-space page, gg / G top and bottom,
// ESC (or ⇧⌘P) goes back to the text. Links can be clicked.

import SwiftUI
import AppKit

struct MarkdownPreview: NSViewRepresentable {
    let title: String
    let markdown: String
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let contentSize = scrollView.contentSize
        let textView = PreviewTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 48, height: 32)
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .cursor: NSCursor.pointingHand]
        textView.onClose = onClose

        scrollView.documentView = textView
        render(into: textView)
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PreviewTextView else { return }
        textView.onClose = onClose
        if textView.renderedTitle != title || textView.renderedMarkdown != markdown {
            render(into: textView)
        }
    }

    private func render(into textView: PreviewTextView) {
        textView.renderedTitle = title
        textView.renderedMarkdown = markdown
        textView.textStorage?.setAttributedString(
            MarkdownRenderer.render(title: title, markdown: markdown, style: .screen)
        )
    }
}

final class PreviewTextView: NSTextView {
    var onClose: (() -> Void)?
    var renderedTitle = ""
    var renderedMarkdown = ""
    private var pendingG = false

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers ?? ""
        let shift = event.modifierFlags.contains(.shift)
        if event.modifierFlags.contains(.command) { super.keyDown(with: event); return }
        defer { if key != "g" { pendingG = false } }
        switch (event.keyCode, key) {
        case (53, _): onClose?()                               // ESC
        case (_, "j"), (125, _): scrollPreview(by: 48)                // j, down arrow
        case (_, "k"), (126, _): scrollPreview(by: -48)               // k, up arrow
        case (_, " "): scrollPreview(by: (shift ? -1 : 1) * pageHeight)
        case (_, "G"): scrollPreview(to: .greatestFiniteMagnitude)
        case (_, "g"):
            if pendingG { scrollPreview(to: 0); pendingG = false } else { pendingG = true }
        default: super.keyDown(with: event)
        }
    }

    private var pageHeight: CGFloat {
        max(100, (enclosingScrollView?.contentView.bounds.height ?? 400) - 48)
    }

    private func scrollPreview(by delta: CGFloat) {
        guard let clip = enclosingScrollView?.contentView else { return }
        scrollPreview(to: clip.bounds.origin.y + delta)
    }

    private func scrollPreview(to y: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let maxY = max(0, frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }
}
