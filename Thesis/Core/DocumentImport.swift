// DocumentImport.swift — Thesis
// Turning text from other apps into a Thesis document. Rich text (Word, RTF, …) is
// converted to Markdown first (RichTextImporter.swift); this file handles what's
// common to all imports: line endings, a title from a leading "# Heading", and
// unwrapping hard-wrapped paragraphs so each paragraph is one line, as Thesis expects.

import Foundation

enum DocumentImport {

    /// Plain-text formats read as they are. Markdown files may start with "# Title".
    static let plainTextExtensions: Set<String> = ["txt", "text", "md", "markdown", "mdown", "mkd"]
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    /// Formats macOS can read as rich text, converted to Markdown on import.
    static let richTextExtensions: Set<String> = ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm"]
    static let archiveExtensions: Set<String> = ["thesis", "json"]

    struct Prepared: Equatable {
        let title: String
        let content: String
    }

    /// - Parameter unwrap: join hard-wrapped lines (plain text and Markdown files). Rich
    ///   text from Word etc. has real paragraphs and must not be unwrapped.
    static func prepare(_ raw: String, isMarkdown: Bool, fallbackTitle: String, unwrap: Bool = true) -> Prepared {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        // Decide before the title line is taken off, which changes the blank-line pattern.
        let wrapped = unwrap && usesBlankLineParagraphs(text)

        var title = fallbackTitle
        if isMarkdown {
            var lines = text.components(separatedBy: "\n")
            if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                let line = lines[first].trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("# ") {
                    title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    lines.removeSubrange(0...first)
                    text = lines.joined(separator: "\n")
                }
            }
        }

        let content = (wrapped ? unwrapHardWrappedLines(text, force: true) : text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Prepared(title: title.isEmpty ? fallbackTitle : title, content: content)
    }

    /// Text that separates paragraphs with blank lines usually also breaks long lines
    /// within a paragraph (email, Markdown written in a code editor, `fold`). Those lines
    /// are joined so each paragraph is a single line. Text with no blank lines is already
    /// one-paragraph-per-line and is left alone. Lists, quotes, tables, headings and code
    /// blocks keep their structure; a line ending in two spaces or "\" is a deliberate break.
    static func unwrapHardWrappedLines(_ text: String, force: Bool = false) -> String {
        guard force || usesBlankLineParagraphs(text) else { return text }
        var output: [String] = []
        var inFence = false
        var previousBlank = true

        for line in text.components(separatedBy: "\n") {
            let kind = MarkdownSource.kind(of: line)
            if kind == .fence {
                inFence.toggle()
                output.append(line)
                previousBlank = false
                continue
            }
            if inFence {
                output.append(line)
                continue
            }
            if kind == .blank {
                if !previousBlank { output.append("") }    // collapse runs of blank lines
                previousBlank = true
                continue
            }

            if !previousBlank, let last = output.last, !last.hasSuffix("  "), !last.hasSuffix("\\") {
                let lastKind = MarkdownSource.kind(of: last)
                let indented = line.first == " " || line.first == "\t"
                let joins: Bool
                switch (lastKind, kind) {
                case (.text, .text): joins = true
                case (.listItem, .text): joins = indented          // continuation of a list item
                case (.quote, .quote): joins = true
                default: joins = false
                }
                if joins {
                    var continuation = line.trimmingCharacters(in: .whitespaces)
                    if kind == .quote {
                        continuation = String(continuation.dropFirst()).trimmingCharacters(in: .whitespaces)
                    }
                    if !continuation.isEmpty {
                        // Trailing spaces only: a nested list item's indentation must stay.
                        output[output.count - 1] = last.replacingOccurrences(of: "\\s+$", with: "",
                                                                              options: .regularExpression)
                            + " " + continuation
                    }
                    previousBlank = false
                    continue
                }
            }
            output.append(line)
            previousBlank = false
        }
        while output.last == "" { output.removeLast() }
        return output.joined(separator: "\n")
    }

    /// True when blank lines separate paragraphs of prose (text, list or quote lines on
    /// both sides). A blank line only after a heading doesn't count: plenty of
    /// one-line-per-paragraph files have one there.
    static func usesBlankLineParagraphs(_ text: String) -> Bool {
        let prose: Set<MarkdownSource.LineKind> = [.text, .listItem, .quote]
        var inFence = false
        var lastKind: MarkdownSource.LineKind?
        var blankSince = false
        for line in text.components(separatedBy: "\n") {
            let kind = MarkdownSource.kind(of: line)
            if kind == .fence { inFence.toggle(); lastKind = .fence; blankSince = false; continue }
            if inFence { continue }
            if kind == .blank { blankSince = true; continue }
            if blankSince, let last = lastKind, prose.contains(last), prose.contains(kind) { return true }
            lastKind = kind
            blankSince = false
        }
        return false
    }

    /// The file name without its extension, as a title.
    static func title(fromFileName name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        return base.isEmpty ? "Untitled" : base
    }
}
