// MarkdownStyler.swift — Thesis
// Formats Markdown in the editor as you write: headings larger, **bold** bold, *italic*
// italic, `code` in a fixed-width font, quotes and list markers tinted. The markers
// themselves stay visible (faint), so what you see is still exactly the text you have.
//
// Only attributes change, never characters, so undo, change tracking and notes are
// unaffected. Restyling is limited to the edited lines, unless a ``` fence was touched
// (which can change everything below it).

import AppKit

final class MarkdownStyler {
    var baseFont: NSFont
    var baseParagraphStyle: NSParagraphStyle
    var enabled: Bool

    init(baseFont: NSFont, baseParagraphStyle: NSParagraphStyle, enabled: Bool) {
        self.baseFont = baseFont
        self.baseParagraphStyle = baseParagraphStyle
        self.enabled = enabled
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.textColor, .paragraphStyle: baseParagraphStyle]
    }

    /// Restyles everything (on load, or when the setting is switched). Not for use while
    /// the text storage is processing an edit.
    func restyleAll(_ storage: NSTextStorage) {
        storage.beginEditing()
        restyle(storage, lines: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }

    /// Call from `textStorage(_:willProcessEditing:…)` after characters change in
    /// `editedRange` (post-edit coordinates). The storage is already mid-edit there, so
    /// attributes are changed directly, without another begin/endEditing batch.
    func restyle(_ storage: NSTextStorage, editedRange: NSRange) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }
        let start = min(editedRange.location, ns.length)
        let end = min(NSMaxRange(editedRange), ns.length)
        var lines = ns.paragraphRange(for: NSRange(location: start, length: end - start))
        // A fence opening or closing changes how everything after it reads.
        if containsFence(ns, in: lines) || lineIsFence(ns, at: max(0, start - 1)) {
            lines = NSRange(location: lines.location, length: ns.length - lines.location)
        }
        restyle(storage, lines: lines)
    }

    private func restyle(_ storage: NSTextStorage, lines range: NSRange) {
        let ns = storage.string as NSString
        guard range.length > 0 else { return }
        storage.setAttributes(baseAttributes, range: range)
        if enabled {
            var inFence = fenceIsOpen(ns, before: range.location)
            var lineStart = range.location
            while lineStart < NSMaxRange(range) {
                let line = ns.lineRange(for: NSRange(location: lineStart, length: 0))
                guard line.length > 0 else { break }
                let content = contentRange(of: line, in: ns)
                let text = ns.substring(with: content)
                let kind = MarkdownSource.kind(of: text)
                if kind == .fence {
                    styleCode(storage, content, marker: true)
                    inFence.toggle()
                } else if inFence {
                    styleCode(storage, content, marker: false)
                } else {
                    styleBlock(storage, ns, line: content, kind: kind)
                    styleInline(storage, ns, line: content)
                }
                lineStart = NSMaxRange(line)
            }
        }
    }

    // MARK: - Blocks

    private func styleBlock(_ storage: NSTextStorage, _ ns: NSString, line: NSRange, kind: MarkdownSource.LineKind) {
        let text = ns.substring(with: line)
        let leading = text.prefix(while: { $0 == " " || $0 == "\t" }).utf16.count
        switch kind {
        case .heading:
            let level = text.dropFirst(leading).prefix(while: { $0 == "#" }).count
            let scale: [CGFloat] = [1.5, 1.3, 1.15, 1.05, 1.0, 1.0]
            let font = withTraits(baseFont, size: baseFont.pointSize * scale[min(level, 6) - 1], bold: true, italic: false)
            storage.addAttribute(.font, value: font, range: line)
            dim(storage, NSRange(location: line.location + leading, length: min(level + 1, line.length - leading)))
        case .quote:
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: line)
            storage.addAttribute(.font, value: withTraits(baseFont, size: nil, bold: false, italic: true), range: line)
            dim(storage, NSRange(location: line.location + leading, length: 1))
        case .listItem:
            let trimmed = text.dropFirst(leading)
            let markerLength = (trimmed.first.map { "-*+".contains($0) } ?? false)
                ? 1
                : trimmed.prefix(while: { $0.isNumber }).utf16.count + 1
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor,
                                 range: NSRange(location: line.location + leading, length: markerLength))
        case .table:
            storage.addAttribute(.font, value: monospaced(), range: line)
        default:
            break
        }
    }

    // MARK: - Inline

    private static let patterns: [(regex: NSRegularExpression, kind: InlineKind)] = {
        func make(_ pattern: String) -> NSRegularExpression {
            // The patterns are constants; a failure here is a programming error.
            try! NSRegularExpression(pattern: pattern, options: [])
        }
        return [
            (make(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#), .bold),
            (make(#"(?<![\*\w])(\*)(?=[^\s*])([^*\n]+?)(?<=[^\s*])(\*)(?![\*\w])"#), .italic),
            (make(#"(?<![_\w])(_)(?=[^\s_])([^_\n]+?)(?<=[^\s_])(_)(?![_\w])"#), .italic),
            (make(#"(~~)(?=\S)(.+?)(?<=\S)(~~)"#), .strikethrough),
            (make(#"(`)([^`\n]+)(`)"#), .code),
            (make(#"(\[)([^\]\n]+)(\]\([^)\s]+\))"#), .link),
        ]
    }()

    private enum InlineKind { case bold, italic, strikethrough, code, link }

    private func styleInline(_ storage: NSTextStorage, _ ns: NSString, line: NSRange) {
        for (regex, kind) in Self.patterns {
            for match in regex.matches(in: ns as String, options: [], range: line) {
                let whole = match.range
                let inner = match.range(at: 2)
                switch kind {
                case .bold, .italic:
                    storage.enumerateAttribute(.font, in: inner, options: []) { value, range, _ in
                        let current = (value as? NSFont) ?? baseFont
                        storage.addAttribute(.font, value: withTraits(current, size: nil,
                                                                      bold: kind == .bold,
                                                                      italic: kind == .italic), range: range)
                    }
                case .strikethrough:
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inner)
                case .code:
                    storage.addAttribute(.font, value: monospaced(), range: whole)
                    storage.addAttribute(.backgroundColor,
                                         value: NSColor.quaternaryLabelColor.withAlphaComponent(0.25), range: whole)
                case .link:
                    storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: inner)
                }
                // Markers: everything in the match outside the inner text.
                dim(storage, NSRange(location: whole.location, length: inner.location - whole.location))
                dim(storage, NSRange(location: NSMaxRange(inner), length: NSMaxRange(whole) - NSMaxRange(inner)))
            }
        }
    }

    private func styleCode(_ storage: NSTextStorage, _ line: NSRange, marker: Bool) {
        guard line.length > 0 else { return }
        storage.addAttribute(.font, value: monospaced(), range: line)
        storage.addAttribute(.foregroundColor,
                             value: marker ? NSColor.tertiaryLabelColor : NSColor.secondaryLabelColor, range: line)
    }

    // MARK: - Helpers

    private func dim(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
    }

    private func monospaced() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.88, weight: .regular)
    }

    private func withTraits(_ font: NSFont, size: CGFloat?, bold: Bool, italic: Bool) -> NSFont {
        var result = font
        if let size = size, let resized = NSFont(descriptor: font.fontDescriptor, size: size) { result = resized }
        if bold { result = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask) }
        if italic { result = NSFontManager.shared.convert(result, toHaveTrait: .italicFontMask) }
        return result
    }

    /// The line without its line break.
    private func contentRange(of line: NSRange, in ns: NSString) -> NSRange {
        var end = NSMaxRange(line)
        while end > line.location {
            let c = ns.character(at: end - 1)
            if c == 10 || c == 13 { end -= 1 } else { break }
        }
        return NSRange(location: line.location, length: end - line.location)
    }

    private func lineIsFence(_ ns: NSString, at position: Int) -> Bool {
        guard position < ns.length else { return false }
        let line = contentRange(of: ns.lineRange(for: NSRange(location: position, length: 0)), in: ns)
        return MarkdownSource.kind(of: ns.substring(with: line)) == .fence
    }

    private func containsFence(_ ns: NSString, in range: NSRange) -> Bool {
        ns.range(of: "```", options: [], range: range).location != NSNotFound
            || ns.range(of: "~~~", options: [], range: range).location != NSNotFound
    }

    /// Whether a ``` block is open at `position` (an odd number of fence lines above it).
    private func fenceIsOpen(_ ns: NSString, before position: Int) -> Bool {
        var open = false
        var searchStart = 0
        while searchStart < position {
            let candidates = [ns.range(of: "```", options: [], range: NSRange(location: searchStart, length: position - searchStart)),
                              ns.range(of: "~~~", options: [], range: NSRange(location: searchStart, length: position - searchStart))]
                .filter { $0.location != NSNotFound }
            guard let found = candidates.min(by: { $0.location < $1.location }) else { break }
            let line = ns.lineRange(for: NSRange(location: found.location, length: 0))
            if lineIsFence(ns, at: found.location) && NSMaxRange(line) <= position + 1 {
                open.toggle()
            }
            searchStart = NSMaxRange(line)
        }
        return open
    }
}
