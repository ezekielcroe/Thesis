// EvolutionReport.swift — Thesis
// The document's evolution log as a document of its own: a summary of named
// snapshots, then a timeline of every change between them (with the writer's
// reasons), the darlings, and the notes. Written as Markdown; PDF and Word versions
// are rendered from it (Exporter.swift).

import Foundation

enum EvolutionLogFormat: String, CaseIterable, Identifiable {
    case markdown = "md"
    case pdf = "pdf"
    case word = "docx"

    var id: String { rawValue }
    var fileExtension: String { rawValue }

    var menuTitle: String {
        switch self {
        case .markdown: return "Evolution Log as Markdown (.md)…"
        case .pdf: return "Evolution Log as PDF…"
        case .word: return "Evolution Log as Word (.docx)…"
        }
    }

    /// For `:export log`, `:export log pdf`, `:export log docx`.
    init?(command: String) {
        switch command.lowercased() {
        case "", "md", "markdown": self = .markdown
        case "pdf": self = .pdf
        case "docx", "word": self = .word
        default: return nil
        }
    }
}

enum EvolutionReport {

    static func markdown(for document: Document, date: Date = Date()) -> String {
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.isEmpty ? "Untitled" : title
        let named = document.snapshots.filter { !$0.isAutomatic }
        let automaticCount = document.snapshots.count - named.count

        var out: [String] = []
        out.append("# Evolution of “\(name)”")
        out.append("")
        out.append("*Exported \(stamp(date)). "
                   + "\(plural(named.count, "named snapshot")), \(plural(automaticCount, "automatic snapshot")), "
                   + "\(plural(document.darlings.count, "darling")), \(plural(document.notes.count, "note")).*")

        // Summary
        out.append("")
        out.append("## Summary")
        out.append("")
        if named.isEmpty {
            out.append("No named snapshots yet. Save one with ⌘S or `:w` to start the log.")
        } else {
            out.append("| # | Snapshot | Date | Words | Changes |")
            out.append("|---|---|---|---|---|")
            for (i, snapshot) in named.enumerated() {
                let changes = document.changes(from: document.namedSnapshot(before: snapshot), to: snapshot)
                let words = TextUnits(snapshot.content).words.count
                out.append("| \(i + 1) | \(cell(snapshot.name ?? "")) | \(stamp(snapshot.timestamp)) | \(words) | \(summary(changes)) |")
            }
            let pending = document.changesSinceLastNamedSnapshot()
            if !pending.isEmpty {
                let words = TextUnits(document.content).words.count
                out.append("| | *Current text (not yet saved as a snapshot)* | | \(words) | \(summary(pending)) |")
            }
        }

        // Timeline
        if !named.isEmpty {
            out.append("")
            out.append("## Timeline")
            for (i, snapshot) in named.enumerated() {
                let previous = document.namedSnapshot(before: snapshot)
                let changes = document.changes(from: previous, to: snapshot)
                out.append("")
                out.append("### \(i + 1). \(snapshot.name ?? "") — \(stamp(snapshot.timestamp))")
                if !snapshot.note.isEmpty {
                    out.append("")
                    out.append("> \(oneLine(snapshot.note))")
                }
                out.append("")
                if previous == nil && i == 0 {
                    let words = TextUnits(snapshot.content).words.count
                    out.append("The starting point: \(plural(words, "word")).")
                } else if changes.isEmpty {
                    out.append("No changes to the text since the previous snapshot.")
                } else {
                    out.append("**\(plural(changes.count, "change")):** \(summary(changes)).")
                    out.append("")
                    out.append(contentsOf: changes.map { line(for: $0, in: document) })
                }
            }
            let pending = document.changesSinceLastNamedSnapshot()
            if !pending.isEmpty {
                out.append("")
                out.append("### Since “\(named.last?.name ?? "")” (not yet saved as a snapshot)")
                out.append("")
                out.append("**\(plural(pending.count, "change")):** \(summary(pending)).")
                out.append("")
                out.append(contentsOf: pending.map { line(for: $0, in: document) })
            }
        }

        // Darlings
        out.append("")
        out.append("## Darlings")
        out.append("")
        if document.darlings.isEmpty {
            out.append("Nothing has been cut yet.")
        } else {
            out.append("Text cut or rewritten away, newest first.")
            out.append("")
            for darling in document.darlings.reversed() {
                var entry = "- “\(oneLine(darling.text))” — \(stamp(darling.cutAt))"
                if let replacement = darling.replacedBy {
                    entry += "\n    - *Became:* “\(oneLine(replacement))”"
                }
                if let reason = document.reason(for: darling.fingerprint) {
                    entry += "\n    - *Why:* \(oneLine(reason))"
                }
                out.append(entry)
            }
        }

        // Notes
        out.append("")
        out.append("## Notes")
        out.append("")
        let open = document.notes.filter { !$0.resolved }.sorted { $0.location < $1.location }
        let resolved = document.notes.filter { $0.resolved }
        if document.notes.isEmpty {
            out.append("No notes.")
        } else {
            for (heading, notes) in [("Open", open), ("Resolved", resolved)] where !notes.isEmpty {
                out.append("**\(heading)**")
                out.append("")
                for note in notes {
                    let anchor = note.isDetached ? "(text removed) “\(oneLine(note.anchorText))”" : "“\(oneLine(note.anchorText))”"
                    out.append("- **\(note.category.displayName)** on \(anchor): \(oneLine(note.text))")
                }
                out.append("")
            }
        }

        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: - Pieces

    /// One change as a list item, with its reason underneath if there is one.
    static func line(for change: ProseChange, in document: Document) -> String {
        let body: String
        switch change.kind {
        case .added:
            body = "**Added:** \(oneLine(change.after ?? ""))"
        case .cut:
            body = "**Cut:** \(wrap(oneLine(change.before ?? ""), "~~"))"
        case .moved:
            body = "**Moved:** \(oneLine(change.after ?? ""))"
        case .reworded:
            body = "**Reworded:** " + change.wordDiff.map { part in
                switch part.kind {
                case .same: return oneLine(part.text)
                case .removed: return wrap(oneLine(part.text), "~~")
                case .added: return wrap(oneLine(part.text), "**")
                }
            }.joined()
        case .rewritten:
            body = "**Rewritten:** \(wrap(oneLine(change.before ?? ""), "~~")) → \(oneLine(change.after ?? ""))"
        }
        if let reason = document.reason(for: change.fingerprint) {
            return "- \(body)\n    - *Why:* \(oneLine(reason))"
        }
        return "- \(body)"
    }

    static func summary(_ changes: [ProseChange]) -> String {
        let parts = ChangeKind.allCases.compactMap { kind -> String? in
            let n = changes.filter { $0.kind == kind }.count
            return n > 0 ? "\(n) \(kind.rawValue)" : nil
        }
        return parts.isEmpty ? "—" : parts.joined(separator: ", ")
    }

    /// Puts Markdown markers around the text but outside its surrounding spaces,
    /// since "**word **" isn't valid emphasis and "**word** " is.
    static func wrap(_ text: String, _ marker: String) -> String {
        let leading = String(text.prefix(while: { $0.isWhitespace }))
        let trailing = String(text.reversed().prefix(while: { $0.isWhitespace }).reversed())
        let core = text.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return text }
        return leading + marker + core + marker + trailing
    }

    /// Changes can span paragraphs; inside a list item each paragraph break becomes " ¶ ".
    static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ¶ ")
    }

    private static func cell(_ text: String) -> String {
        oneLine(text).replacingOccurrences(of: "|", with: "\\|")
    }

    private static func stamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func plural(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
