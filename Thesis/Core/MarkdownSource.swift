// MarkdownSource.swift — Thesis
// Reading the document's text as Markdown.
//
// The editor treats every line as a paragraph (that's what j/k, dp and the change
// tracking use). Standard Markdown instead joins consecutive lines into one paragraph.
// `normalizedForRendering` inserts the blank lines Markdown needs, so the preview,
// PDF and .md export show the same paragraphs the editor does.

import Foundation

enum MarkdownSettings {
    /// Settings ▸ "Format Markdown while writing". On by default.
    static let styleEditorKey = "markdown.styleEditor"
}

enum MarkdownSource {

    enum LineKind: Equatable {
        case blank, fence, heading, quote, listItem, table, text
    }

    static func kind(of line: String) -> LineKind {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .blank }
        if t.hasPrefix("```") || t.hasPrefix("~~~") { return .fence }
        if t.hasPrefix("#") {
            let hashes = t.prefix(while: { $0 == "#" }).count
            let rest = t.dropFirst(hashes)
            if hashes <= 6 && (rest.isEmpty || rest.first == " ") { return .heading }
        }
        if t.hasPrefix(">") { return .quote }
        if t.hasPrefix("|") { return .table }
        if isListItem(t) { return .listItem }
        return .text
    }

    /// "- item", "* item", "+ item", "1. item", "1) item"
    static func isListItem(_ trimmed: String) -> Bool {
        if let first = trimmed.first, "-*+".contains(first) {
            return trimmed.dropFirst().first == " "
        }
        let digits = trimmed.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, digits.count <= 9 else { return false }
        let rest = trimmed.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")" else { return false }
        return rest.dropFirst().first == " "
    }

    /// Makes each line its own paragraph, except where Markdown needs lines to stay
    /// together: list items, table rows, and everything inside a ``` fence. Consecutive
    /// quote lines become separate paragraphs within the same quote.
    static func normalizedForRendering(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var inFence = false
        for (i, line) in lines.enumerated() {
            output.append(line)
            let current = kind(of: line)
            if current == .fence { inFence.toggle(); continue }
            if inFence || current == .blank || i + 1 >= lines.count { continue }

            let next = kind(of: lines[i + 1])
            switch (current, next) {
            case (_, .blank), (_, .fence):
                break                                   // already separated
            case (.listItem, .listItem), (.table, .table):
                break                                   // keep lists and tables together
            case (.listItem, _) where lines[i + 1].first == " " || lines[i + 1].first == "\t":
                break                                   // indented continuation of a list item
            case (.quote, .quote):
                output.append(">")                      // new paragraph, same quote
            default:
                output.append("")
            }
        }
        return output.joined(separator: "\n")
    }
}
