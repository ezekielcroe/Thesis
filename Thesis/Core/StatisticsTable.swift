// StatisticsTable.swift — Thesis
// Statistics laid out as tables for pasting into Excel, Numbers, Word or Pages, or
// saving as CSV. The same tables are written three ways:
//   TSV  — plain-text clipboard; spreadsheets split it into cells
//   HTML — rich clipboard; Word and Pages paste it as a real table
//   CSV  — file
// Numbers are written without thousands separators so spreadsheets read them as
// numbers, using the given decimal separator (the Mac's, by default).

import Foundation

struct StatisticsTable {

    enum Content: CaseIterable {
        case all          // every section
        case summary      // counts and the length distributions
        case sentences    // one row per sentence: raw data for your own charts
    }

    enum Cell: Equatable {
        case text(String)
        case integer(Int)
        case decimal(Double)
        case percent(Double)      // 0.34 → "34%"
        case empty
    }

    struct Section {
        let title: String
        let header: [String]
        let rows: [[Cell]]
    }

    let title: String
    let details: [(String, String)]
    let sections: [Section]

    init(statistics s: ProseStatistics, documentTitle: String, scopeLabel: String,
         content: Content, date: Date = Date()) {
        let name = documentTitle.isEmpty ? "Untitled" : documentTitle
        title = "Statistics: \(name)"
        details = [
            ("Document", name),
            ("Scope", scopeLabel),
            ("Generated", date.formatted(date: .abbreviated, time: .shortened)),
        ]

        var sections: [Section] = []
        if content == .all || content == .summary {
            sections.append(Section(title: "Counts", header: ["Measure", "Value"], rows: [
                [.text("Words"), .integer(s.words)],
                [.text("Sentences"), .integer(s.sentences)],
                [.text("Paragraphs"), .integer(s.paragraphs)],
                [.text("Characters"), .integer(s.characters)],
                [.text("Characters (no spaces)"), .integer(s.charactersExcludingSpaces)],
                [.text("Reading time (minutes)"), .decimal(s.readingMinutes)],
            ]))
            let distributions: [(String, Distribution?)] = [
                ("Sentence length (words)", s.sentenceLength),
                ("Paragraph length (words)", s.paragraphLengthInWords),
                ("Paragraph length (sentences)", s.paragraphLengthInSentences),
            ]
            sections.append(Section(
                title: "Lengths (prose only)",
                header: ["Measure", "Count", "Mean", "Min", "Q1", "Median", "Q3", "Max", "Range", "IQR", "SD"],
                rows: distributions.map { label, d in
                    guard let d = d else { return [.text(label)] + Array(repeating: Cell.empty, count: 10) }
                    return [.text(label), .integer(d.count), .decimal(d.mean), .integer(d.min), .decimal(d.q1),
                            .decimal(d.median), .decimal(d.q3), .integer(d.max), .integer(d.range),
                            .decimal(d.interquartileRange), .decimal(d.standardDeviation)]
                }))
        }

        if content == .all {
            sections.append(Section(title: "Sentence-length histogram", header: ["Words per sentence", "Sentences"],
                                    rows: s.sentenceLengthHistogram.map { [.text($0.label), .integer($0.count)] }))
            sections.append(Section(title: "Most-used words", header: ["Word", "Count"],
                                    rows: s.mostUsedWords.map { [.text($0.word), .integer($0.count)] }))
            let total = max(1, s.proseSentenceCount)
            sections.append(Section(title: "Sentence openers", header: ["Opener", "Sentences", "Share"],
                                    rows: s.openers.map {
                                        [.text($0.word.capitalized), .integer($0.count),
                                         .percent(Double($0.count) / Double(total))]
                                    }))
            sections.append(Section(title: "Same opener in a row", header: ["Opener", "Sentences in a row"],
                                    rows: s.openerStreaks.map { [.text($0.word.capitalized), .integer($0.count)] }))
            sections.append(Section(
                title: "Runs of similar-length sentences (within \(ProseStatistics.runTolerance) words)",
                header: ["Sentences", "Lengths (words)"],
                rows: s.similarLengthRuns.map {
                    [.integer($0.lengths.count), .text($0.lengths.map { String($0) }.joined(separator: ", "))]
                }))
            sections.append(Section(title: "Longest sentences", header: ["Words", "Sentence"],
                                    rows: s.longestSentences.map { [.integer($0.words), .text($0.text)] }))
        }

        if content == .sentences {
            sections.append(Section(title: "Sentences (prose only)", header: ["#", "Paragraph", "Words", "Sentence"],
                                    rows: s.sentenceList.enumerated().map { index, sentence in
                                        [.integer(index + 1), .integer(sentence.paragraphIndex),
                                         .integer(sentence.words), .text(sentence.text)]
                                    }))
        }
        self.sections = sections
    }

    /// The Mac's decimal separator ("." or ",").
    static var systemDecimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    // MARK: - Output

    func tsv(decimalSeparator: String = StatisticsTable.systemDecimalSeparator) -> String {
        delimited(separator: "\t", decimalSeparator: decimalSeparator) { cell in
            cell.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
        }
    }

    /// Comma-separated, or semicolon-separated where the decimal separator is a comma
    /// (what Excel expects in those regions). Fields are quoted when needed (RFC 4180).
    func csv(decimalSeparator: String = StatisticsTable.systemDecimalSeparator) -> String {
        let separator = decimalSeparator == "," ? ";" : ","
        return delimited(separator: separator, decimalSeparator: decimalSeparator) { cell in
            guard cell.contains(separator) || cell.contains("\"") || cell.contains("\n") else { return cell }
            return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
    }

    func html(decimalSeparator: String = StatisticsTable.systemDecimalSeparator) -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        let cellStyle = "border:1px solid #bbb;padding:3px 8px;"
        var out = "<html><head><meta charset=\"utf-8\"></head><body>\n"
        out += "<h2>\(escape(title))</h2>\n<p>"
        out += details.map { "<b>\(escape($0.0)):</b> \(escape($0.1))" }.joined(separator: "<br>")
        out += "</p>\n"
        for section in sections {
            out += "<h3>\(escape(section.title))</h3>\n"
            out += "<table style=\"border-collapse:collapse;\">\n<tr>"
            out += section.header.map { "<th style=\"\(cellStyle)text-align:left;background:#eee;\">\(escape($0))</th>" }.joined()
            out += "</tr>\n"
            if section.rows.isEmpty {
                out += "<tr><td style=\"\(cellStyle)\" colspan=\"\(section.header.count)\">None</td></tr>\n"
            }
            for row in section.rows {
                out += "<tr>"
                out += row.map { cell in
                    let align = cell.isNumeric ? "text-align:right;" : ""
                    return "<td style=\"\(cellStyle)\(align)\">\(escape(Self.format(cell, decimalSeparator: decimalSeparator)))</td>"
                }.joined()
                out += "</tr>\n"
            }
            out += "</table>\n"
        }
        out += "</body></html>\n"
        return out
    }

    /// Title, details, then each section as a title row, a header row and data rows,
    /// separated by blank lines.
    private func delimited(separator: String, decimalSeparator: String, escape: (String) -> String) -> String {
        var lines: [String] = [escape(title)]
        lines += details.map { escape($0.0) + separator + escape($0.1) }
        for section in sections {
            lines.append("")
            lines.append(escape(section.title))
            lines.append(section.header.map(escape).joined(separator: separator))
            for row in section.rows {
                lines.append(row.map { escape(Self.format($0, decimalSeparator: decimalSeparator)) }
                    .joined(separator: separator))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func format(_ cell: Cell, decimalSeparator: String) -> String {
        switch cell {
        case .text(let s): return s
        case .integer(let n): return String(n)
        case .decimal(let x): return decimal(x, separator: decimalSeparator)
        case .percent(let x): return String(Int((x * 100).rounded())) + "%"
        case .empty: return ""
        }
    }

    /// Up to two decimal places, without trailing zeros: 12.5, 3, 0.67.
    static func decimal(_ x: Double, separator: String) -> String {
        var s = String(format: "%.2f", (x * 100).rounded() / 100)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: separator)
    }
}

private extension StatisticsTable.Cell {
    var isNumeric: Bool {
        switch self {
        case .integer, .decimal, .percent: return true
        case .text, .empty: return false
        }
    }
}
