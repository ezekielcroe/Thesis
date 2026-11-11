// RichTextImporter.swift — Thesis
// Reads Word (.docx, .doc), RTF/RTFD, OpenDocument (.odt) and HTML with macOS's own
// readers, and converts the formatting to Markdown: headings (from font size), bold,
// italic, strikethrough, links and bulleted/numbered lists. Tables, images, footnotes,
// comments and tracked changes are not carried over; their text is kept where possible.

import AppKit

enum RichTextImporter {

    enum ImportError: LocalizedError {
        case pages
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .pages:
                return "Pages documents can't be read directly. In Pages, choose File ▸ Export To ▸ Word…, then open the Word file in Thesis."
            case .unreadable(let name):
                return "“\(name)” couldn't be read as a text document."
            }
        }
    }

    static func read(_ url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        if ext == "pages" { throw ImportError.pages }
        let type: NSAttributedString.DocumentType?
        switch ext {
        case "docx": type = .officeOpenXML
        case "doc": type = .docFormat
        case "rtf": type = .rtf
        case "rtfd": type = .rtfd
        case "odt": type = .openDocument
        case "html", "htm": type = .html
        default: type = nil
        }
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        if let type = type { options[.documentType] = type }
        do {
            return try NSAttributedString(url: url, options: options, documentAttributes: nil)
        } catch {
            throw ImportError.unreadable(url.lastPathComponent)
        }
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        let ns = attributed.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard full.length > 0 else { return "" }

        // The body size is the font size used by the most characters.
        var sizeCounts: [CGFloat: Int] = [:]
        attributed.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            if let font = value as? NSFont { sizeCounts[font.pointSize.rounded(), default: 0] += range.length }
        }
        let bodySize = sizeCounts.max(by: { $0.value < $1.value })?.key ?? 12

        var lines: [String] = []
        ns.enumerateSubstrings(in: full, options: [.byParagraphs]) { _, range, _, _ in
            guard range.length > 0 else { lines.append(""); return }
            let paragraph = attributed.attributedSubstring(from: range)
            let plain = paragraph.string.trimmingCharacters(in: .whitespaces)
            guard !plain.isEmpty else { lines.append(""); return }

            let font = paragraph.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            let size = font?.pointSize ?? bodySize
            let bold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            var prefix = ""
            if size >= bodySize * 1.6 {
                prefix = "# "
            } else if size >= bodySize * 1.3 {
                prefix = "## "
            } else if size >= bodySize * 1.12 && bold && plain.count < 120 {
                prefix = "### "
            }

            var body = inline(paragraph, emphasis: prefix.isEmpty)

            if prefix.isEmpty,
               let style = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
               let list = style.textLists.last {
                let ordered: [NSTextList.MarkerFormat] = [.decimal, .lowercaseAlpha, .uppercaseAlpha,
                                                         .lowercaseRoman, .uppercaseRoman, .lowercaseLatin, .uppercaseLatin]
                prefix = String(repeating: "    ", count: max(0, style.textLists.count - 1))
                    + (ordered.contains(list.markerFormat) ? "1. " : "- ")
                // The readers put the marker ("•", "1.") into the text itself; drop it.
                body = body.replacingOccurrences(of: #"^\s*([•◦▪▫●○■□‣⁃\-–*]|\(?[0-9A-Za-z]{1,4}[.)])\s+"#,
                                                 with: "", options: .regularExpression)
            }
            lines.append(prefix + body.trimmingCharacters(in: .whitespaces))
        }

        // Collapse runs of blank lines.
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) {
            result.append(line)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Inline formatting

    private struct Segment {
        var text: String
        var bold: Bool
        var italic: Bool
        var strike: Bool
        var link: URL?

        func sameStyle(as other: Segment) -> Bool {
            bold == other.bold && italic == other.italic && strike == other.strike && link == other.link
        }
    }

    /// Text with **bold**, *italic*, ~~strikethrough~~ and [links](url). Runs with the same
    /// style are merged first, so a colour change mid-word doesn't produce "**a****b**".
    private static func inline(_ paragraph: NSAttributedString, emphasis: Bool) -> String {
        var segments: [Segment] = []
        let range = NSRange(location: 0, length: paragraph.length)
        paragraph.enumerateAttributes(in: range, options: []) { attrs, runRange, _ in
            var text = (paragraph.string as NSString).substring(with: runRange)
            text = text.replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\u{2028}", with: " ")
                .replacingOccurrences(of: "\u{2029}", with: "")
            guard !text.isEmpty else { return }
            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            let link: URL?
            if let url = attrs[.link] as? URL { link = url }
            else if let string = attrs[.link] as? String { link = URL(string: string) }
            else { link = nil }
            let segment = Segment(text: text,
                                  bold: emphasis && traits.contains(.bold),
                                  italic: emphasis && traits.contains(.italic),
                                  strike: ((attrs[.strikethroughStyle] as? Int) ?? 0) != 0,
                                  link: link)
            if var last = segments.last, last.sameStyle(as: segment) {
                last.text += segment.text
                segments[segments.count - 1] = last
            } else {
                segments.append(segment)
            }
        }

        return segments.map { segment in
            var text = segment.text
            if segment.strike { text = EvolutionReport.wrap(text, "~~") }
            if segment.italic { text = EvolutionReport.wrap(text, "*") }
            if segment.bold { text = EvolutionReport.wrap(text, "**") }
            if let url = segment.link {
                let label = text.trimmingCharacters(in: .whitespaces)
                if !label.isEmpty { text = text.replacingOccurrences(of: label, with: "[\(label)](\(url.absoluteString))") }
            }
            return text
        }.joined()
    }
}
