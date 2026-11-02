// DocumentExport.swift — Thesis
// What gets written when exporting: the current text as .txt / .md (PDF is drawn in
// Exporter.swift), and the .thesis archive, a complete backup of one or more
// documents that can be imported again.

import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case plainText = "txt"
    case markdown = "md"
    case pdf = "pdf"
    case archive = "thesis"

    var id: String { rawValue }
    var fileExtension: String { rawValue }

    var menuTitle: String {
        switch self {
        case .plainText: return "Plain Text (.txt)…"
        case .markdown: return "Markdown (.md)…"
        case .pdf: return "PDF…"
        case .archive: return "Thesis Archive with History (.thesis)…"
        }
    }

    /// For `:export txt`, `:export md`, `:export pdf`, `:export archive`.
    init?(command: String) {
        switch command.lowercased() {
        case "txt", "text", "plain": self = .plainText
        case "md", "markdown": self = .markdown
        case "pdf": self = .pdf
        case "thesis", "archive", "backup": self = .archive
        default: return nil
        }
    }
}

enum DocumentExport {

    // MARK: - Latest work

    /// The text exactly as written.
    static func plainText(_ document: Document) -> String {
        let text = document.content
        return text.hasSuffix("\n") || text.isEmpty ? text : text + "\n"
    }

    /// Title as a heading, then one paragraph per block. Markdown needs a blank line
    /// between paragraphs; the editor treats every non-blank line as a paragraph.
    static func markdown(_ document: Document) -> String {
        let paragraphs = TextUnits(document.content).paragraphs.map(\.text)
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = title.isEmpty ? [] : ["# \(title)"]
        return (heading + paragraphs).joined(separator: "\n\n") + "\n"
    }

    static func suggestedFileName(title: String, format: ExportFormat) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|").union(.newlines))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cleaned.isEmpty ? "Untitled" : cleaned).\(format.fileExtension)"
    }

    // MARK: - Archive (full backup)

    enum ArchiveError: LocalizedError {
        case unrecognized

        var errorDescription: String? {
            "This file isn't a Thesis archive."
        }
    }

    private struct Archive: Codable {
        let format: String
        let version: Int
        let exportedAt: Date
        let documents: [Document]
    }

    static let archiveFormat = "thesis-archive"

    /// Everything about the documents: text, snapshots, darlings, notes and reasons.
    static func archiveData(_ documents: [Document]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Archive(format: archiveFormat, version: 1, exportedAt: Date(), documents: documents))
    }

    /// Reads a .thesis archive. Also accepts the app's own `documents.json` and a single
    /// encoded document, so any copy of your data can be brought back in.
    static func documents(fromArchive data: Data) throws -> [Document] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let archive = try? decoder.decode(Archive.self, from: data), archive.format == archiveFormat {
            return archive.documents
        }
        if let library = try? decoder.decode([Document].self, from: data) {
            return library
        }
        if let single = try? decoder.decode(Document.self, from: data) {
            return [single]
        }
        throw ArchiveError.unrecognized
    }
}
