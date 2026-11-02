// StatisticsSheet.swift — Thesis
// Counts, length distributions, rhythm and repetition (:stats, ⇧⌘I, the header's
// chart button, or the status bar counts). Scope: the whole document, the current
// paragraph, or the Visual-mode selection.

import SwiftUI

struct StatisticsSheet: View {
    let title: String
    let context: StatisticsContext
    let onJump: (NSRange) -> Void
    let onFindWord: (String) -> Void

    enum Scope: String, CaseIterable, Identifiable {
        case document = "Document", paragraph = "This paragraph", selection = "Selection"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var scope: Scope = .document
    @State private var stats: ProseStatistics?
    @State private var copiedNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Statistics").font(.headline)
                Text(title.isEmpty ? "Untitled" : title).foregroundColor(.secondary).lineLimit(1)
                Spacer()
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if scope == .selection && context.selection == nil {
                Text("Select text in Visual mode (v), then open Statistics (⇧⌘I) to analyse just that passage.")
                    .font(.callout).foregroundColor(.secondary)
            }

            ScrollView {
                if let stats = stats {
                    VStack(alignment: .leading, spacing: 18) {
                        totals(stats)
                        Divider()
                        distributions(stats)
                        Divider()
                        HStack(alignment: .top, spacing: 28) {
                            histogram(stats).frame(maxWidth: .infinity, alignment: .topLeading)
                            similarRuns(stats).frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        Divider()
                        HStack(alignment: .top, spacing: 28) {
                            mostUsedWords(stats).frame(maxWidth: .infinity, alignment: .topLeading)
                            openers(stats).frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        if !stats.longestSentences.isEmpty {
                            Divider()
                            longest(stats)
                        }
                        Text("Counts cover all text in scope. Everything else covers prose only (headings, code blocks and tables are left out). A selection is widened to whole sentences. Quartiles are interpolated, as in Excel's QUARTILE.INC. The common-word filter is English.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.trailing, 8)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .frame(minHeight: 420, maxHeight: 640)

            HStack(spacing: 12) {
                Menu {
                    Button("All Statistics") { copy(.all, note: "all statistics") }
                    Button("Summary (Counts and Lengths)") { copy(.summary, note: "the summary") }
                    Button("Sentence Lengths (One Row per Sentence)") { copy(.sentences, note: "one row per sentence") }
                    Divider()
                    Button("Save All as CSV…") {
                        if let table = table(.all) { Exporter.saveCSV(table, documentTitle: title) }
                    }
                } label: {
                    Label("Copy as Table", systemImage: "tablecells")
                }
                .fixedSize()
                .disabled(stats == nil)
                .help("Copy for Excel, Numbers, Word or Pages")
                if let note = copiedNote {
                    Text(note).font(.callout).foregroundColor(.secondary).transition(.opacity)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 760)
        .onAppear {
            if context.selection != nil { scope = .selection }
            recompute()
        }
        .onChange(of: scope) { recompute() }
    }

    private func recompute() {
        let range: NSRange?
        switch scope {
        case .document: range = nil
        case .paragraph: range = context.paragraph ?? NSRange(location: 0, length: 0)
        case .selection: range = context.selection ?? NSRange(location: 0, length: 0)
        }
        stats = ProseStatistics(text: context.text, scope: range)
    }

    private func table(_ content: StatisticsTable.Content) -> StatisticsTable? {
        guard let stats = stats else { return nil }
        return StatisticsTable(statistics: stats, documentTitle: title, scopeLabel: scopeLabel, content: content)
    }

    private var scopeLabel: String {
        switch scope {
        case .document: return "Whole document"
        case .paragraph: return "One paragraph"
        case .selection: return "Selected passage"
        }
    }

    private func copy(_ content: StatisticsTable.Content, note: String) {
        guard let table = table(content) else { return }
        Exporter.copy(table)
        withAnimation { copiedNote = "Copied \(note). Paste into Excel, Numbers, Word or Pages." }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { copiedNote = nil }
        }
    }

    private func jump(_ range: NSRange) {
        dismiss()
        onJump(range)
    }

    private func find(_ word: String) {
        dismiss()
        onFindWord(word)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold))
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.callout).foregroundColor(.secondary)
    }

    // MARK: - Totals

    private func totals(_ s: ProseStatistics) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
            GridRow {
                total("Words", s.words.formatted())
                total("Sentences", s.sentences.formatted())
                total("Paragraphs", s.paragraphs.formatted())
            }
            GridRow {
                total("Characters", s.characters.formatted())
                total("Without spaces", s.charactersExcludingSpaces.formatted())
                total("Reading time", readingTime(s.readingMinutes))
            }
        }
    }

    private func total(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }

    private func readingTime(_ minutes: Double) -> String {
        if minutes < 1 { return "< 1 min" }
        let m = Int(minutes.rounded())
        return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }

    // MARK: - Distributions

    private func distributions(_ s: ProseStatistics) -> some View {
        let rows: [(String, Distribution?)] = [
            ("Sentence length (words)", s.sentenceLength),
            ("Paragraph length (words)", s.paragraphLengthInWords),
            ("Paragraph length (sentences)", s.paragraphLengthInSentences),
        ]
        return Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                ForEach(["Mean", "Min", "Q1", "Median", "Q3", "Max", "Range", "IQR", "SD"], id: \.self) {
                    Text($0).font(.caption.weight(.semibold)).foregroundColor(.secondary)
                }
                Text("")
            }
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0).font(.system(size: 12)).gridColumnAlignment(.leading)
                    if let d = row.1 {
                        number(d.mean)
                        number(Double(d.min))
                        number(d.q1)
                        number(d.median).fontWeight(.semibold)
                        number(d.q3)
                        number(Double(d.max))
                        number(Double(d.range))
                        number(d.interquartileRange)
                        number(d.standardDeviation)
                        BoxPlot(distribution: d).frame(width: 120, height: 14)
                    } else {
                        Text("—").foregroundColor(.secondary).gridCellColumns(10)
                    }
                }
            }
        }
    }

    private func number(_ value: Double) -> Text {
        let rounded = (value * 10).rounded() / 10
        let string = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return Text(string).font(.system(size: 12)).monospacedDigit()
    }

    // MARK: - Rhythm

    private func histogram(_ s: ProseStatistics) -> some View {
        let peak = max(1, s.sentenceLengthHistogram.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Sentence lengths")
            if s.proseSentenceCount == 0 {
                emptyNote("No sentences in scope.")
            } else {
                ForEach(s.sentenceLengthHistogram, id: \.label) { bin in
                    HStack(spacing: 8) {
                        Text(bin.label)
                            .font(.system(size: 11)).monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(bin.count == 0 ? 0 : 0.7))
                                .frame(width: max(bin.count == 0 ? 0 : 2,
                                                  geo.size.width * CGFloat(bin.count) / CGFloat(peak)))
                        }
                        .frame(height: 12)
                        Text("\(bin.count)")
                            .font(.system(size: 11)).monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .leading)
                    }
                }
                Text("words per sentence")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.leading, 52)
            }
        }
    }

    private func similarRuns(_ s: ProseStatistics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Runs of similar-length sentences")
            Text("\(ProseStatistics.minimumRunLength)+ in a row within ±\(ProseStatistics.runTolerance) words; read them aloud.")
                .font(.caption).foregroundColor(.secondary)
            if s.similarLengthRuns.isEmpty {
                emptyNote("None. Your sentence lengths vary.")
            } else {
                ForEach(Array(s.similarLengthRuns.prefix(12).enumerated()), id: \.offset) { _, run in
                    jumpRow(range: run.range) {
                        Text("\(run.lengths.count) sentences")
                            .font(.system(size: 12, weight: .semibold))
                        Text(run.lengths.map { String($0) }.joined(separator: " · ") + " words")
                            .font(.system(size: 11)).monospacedDigit().foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                if s.similarLengthRuns.count > 12 {
                    Text("+ \(s.similarLengthRuns.count - 12) more").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Repetition

    private func mostUsedWords(_ s: ProseStatistics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Most-used words")
            Text("Common words like “the” and “and” left out. Click to find them.")
                .font(.caption).foregroundColor(.secondary)
            if s.mostUsedWords.isEmpty {
                emptyNote("No word appears more than once.")
            } else {
                let peak = s.mostUsedWords.first?.count ?? 1
                ForEach(s.mostUsedWords, id: \.word) { item in
                    Button { find(item.word) } label: {
                        HStack(spacing: 8) {
                            Text(item.word).font(.system(size: 12)).frame(width: 110, alignment: .leading).lineLimit(1)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.purple.opacity(0.55))
                                    .frame(width: max(2, geo.size.width * CGFloat(item.count) / CGFloat(peak)))
                            }
                            .frame(height: 10)
                            Text("\(item.count)").font(.system(size: 11)).monospacedDigit()
                                .foregroundColor(.secondary).frame(width: 28, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Find “\(item.word)” (then n / N)")
                }
            }
        }
    }

    private func openers(_ s: ProseStatistics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Sentence openers")
            Text("The first word of each sentence.")
                .font(.caption).foregroundColor(.secondary)
            if s.openers.isEmpty {
                emptyNote("Every sentence starts differently.")
            } else {
                ForEach(s.openers, id: \.word) { item in
                    Button { find(item.word) } label: {
                        HStack(spacing: 8) {
                            Text(item.word.capitalized).font(.system(size: 12)).frame(width: 110, alignment: .leading).lineLimit(1)
                            Text("\(item.count)").font(.system(size: 11)).monospacedDigit().foregroundColor(.secondary)
                            Text(percent(item.count, of: s.proseSentenceCount))
                                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Find “\(item.word)” (then n / N)")
                }
            }

            if !s.openerStreaks.isEmpty {
                Text("In a row").font(.caption.weight(.semibold)).padding(.top, 6)
                ForEach(Array(s.openerStreaks.enumerated()), id: \.offset) { _, streak in
                    jumpRow(range: streak.range) {
                        Text("\(streak.count) in a row start with “\(streak.word.capitalized)”")
                            .font(.system(size: 12))
                    }
                }
            }
        }
    }

    private func percent(_ count: Int, of total: Int) -> String {
        guard total > 0 else { return "" }
        return "\(Int((Double(count) / Double(total) * 100).rounded()))%"
    }

    // MARK: - Longest sentences

    private func longest(_ s: ProseStatistics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Longest sentences")
            ForEach(Array(s.longestSentences.enumerated()), id: \.offset) { _, sentence in
                jumpRow(range: sentence.range) {
                    Text("\(sentence.words)")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                    Text(sentence.text)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// A row that closes the sheet and puts the cursor on `range`.
    private func jumpRow<Content: View>(range: NSRange, @ViewBuilder content: () -> Content) -> some View {
        Button { jump(range) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                content()
                Spacer(minLength: 0)
                Image(systemName: "arrow.right.circle").foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Go there")
    }
}

/// Min–max whisker, Q1–Q3 box, median line and mean dot, scaled to this row's own range.
struct BoxPlot: View {
    let distribution: Distribution

    var body: some View {
        GeometryReader { geo in
            let d = distribution
            let low = Double(d.min), high = Double(max(d.max, d.min + 1))
            let x: (Double) -> CGFloat = { CGFloat(($0 - low) / (high - low)) * geo.size.width }
            let midY = geo.size.height / 2
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: x(Double(d.min)), y: midY))
                    p.addLine(to: CGPoint(x: x(Double(d.max)), y: midY))
                }
                .stroke(Color.secondary, lineWidth: 1)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                    .frame(width: max(1, x(d.q3) - x(d.q1)), height: geo.size.height)
                    .offset(x: x(d.q1))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: geo.size.height)
                    .offset(x: x(d.median) - 1)
                Circle()
                    .fill(Color.primary)
                    .frame(width: 4, height: 4)
                    .offset(x: x(d.mean) - 2, y: midY - 2)
            }
        }
        .help("Whisker: min–max · box: Q1–Q3 · line: median · dot: mean")
    }
}
