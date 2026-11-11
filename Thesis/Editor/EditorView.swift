// EditorView.swift — Thesis
// One document: title, the modal editor, the status bar, and the Evolution panel.

import SwiftUI
import Combine

struct EditorView: View {
    @ObservedObject var document: Document
    @EnvironmentObject private var documentManager: DocumentManager
    @StateObject private var engine: EditorEngine
    @AppStorage("showEvolutionPanel") private var showingPanel = false
    @AppStorage(MarkdownSettings.styleEditorKey) private var markdownStyling = true
    @State private var panelTab: PanelTab = .history
    @State private var showingPreview = false

    init(document: Document) {
        self.document = document
        _engine = StateObject(wrappedValue: EditorEngine(document: document))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        // The editor stays alive under the preview, so undo history,
                        // the cursor and the mode survive switching back and forth.
                        EditorTextView(document: document, engine: engine, markdownStyling: markdownStyling)
                            .border(engine.mode.color.opacity(0.5), width: 2)
                        if let op = engine.pendingOperator, !showingPreview {
                            OperatorHelp(op: op).padding(10)
                        }
                        if showingPreview {
                            MarkdownPreview(title: document.title, markdown: document.content,
                                            onClose: { togglePreview() })
                                .border(Color.gray.opacity(0.5), width: 2)
                        }
                    }
                    StatusBar(
                        isPreviewing: showingPreview,
                        mode: engine.mode,
                        pending: engine.pending,
                        message: engine.message,
                        stats: engine.stats,
                        snapshotInfo: snapshotInfo,
                        hasUnsnapshottedChanges: document.hasUnsnapshottedChanges,
                        openNotes: document.notes.filter { !$0.resolved }.count,
                        searchMatchCount: engine.searchMatchCount,
                        onShowStatistics: { engine.openStatistics() }
                    )
                }
                .frame(minWidth: 480)

                if showingPanel {
                    HistoryPanel(
                        document: document,
                        tab: $panelTab,
                        onJump: { engine.jump(to: $0) },
                        onRestore: { engine.restore($0) },
                        onReview: { engine.openReview() },
                        onPutInRegister: { engine.putInRegister($0) },
                        onExportLog: { format in Exporter.exportEvolutionLog(document, as: format) },
                        onClose: { showingPanel = false }
                    )
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 440)
                }
            }
        }
        .sheet(item: $engine.activeSheet) { sheet in
            switch sheet {
            case .review:
                ReviewSheet(document: document) { name, note in
                    engine.saveSnapshot(name: name, note: note)
                }
            case .note(let range, let anchor):
                NoteSheet(anchorText: anchor) { text, category in
                    document.addNote(text, category: category, range: range)
                }
            case .help:
                HelpSheet()
            case .statistics(let context):
                StatisticsSheet(
                    title: document.title,
                    context: context,
                    onJump: { range in DispatchQueue.main.async { engine.jump(to: range) } },
                    onFindWord: { word in DispatchQueue.main.async { engine.findWord(word) } }
                )
            }
        }
        // @Published notifies *before* storing the new value, so each request is cleared
        // on the next turn; clearing it inside the handler would be overwritten.
        .onReceive(engine.$panelRequest.compactMap { $0 }) { tab in
            panelTab = tab
            showingPanel = true
            DispatchQueue.main.async { engine.panelRequest = nil }
        }
        .onReceive(engine.$renameRequested.filter { $0 }) { _ in
            DispatchQueue.main.async {
                engine.renameRequested = false
                documentManager.requestName(for: document)
            }
        }
        .onReceive(engine.$previewRequested.filter { $0 }) { _ in
            DispatchQueue.main.async {
                engine.previewRequested = false
                togglePreview()
            }
        }
        .onReceive(engine.$exportRequest.compactMap { $0 }) { request in
            // Also lets the key event finish before the modal save panel takes over.
            DispatchQueue.main.async {
                engine.exportRequest = nil
                switch request {
                case .document(let format): Exporter.export(document, as: format)
                case .log(let format): Exporter.exportEvolutionLog(document, as: format)
                }
            }
        }
        .onDisappear { engine.flushSnapshots() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                documentManager.requestName(for: document)
            } label: {
                HStack(spacing: 6) {
                    Text(document.title.isEmpty ? "Untitled" : document.title)
                        .font(.title2)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rename (⇧⌘R or :rename)")
            .padding()
            Spacer()
            Button {
                engine.openStatistics()
            } label: {
                Label("Statistics", systemImage: "chart.bar.xaxis")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .help("Counts and sentence/paragraph lengths (⇧⌘I or :stats)")
            Button {
                togglePreview()
            } label: {
                Label(showingPreview ? "Edit" : "Preview",
                      systemImage: showingPreview ? "pencil.line" : "eye")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .help("Show the formatted document (⇧⌘P or :preview); ESC to go back")
            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.menuTitle) { Exporter.export(document, as: format) }
                }
                Divider()
                ForEach(EvolutionLogFormat.allCases) { format in
                    Button(format.menuTitle) { Exporter.exportEvolutionLog(document, as: format) }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button {
                showingPanel.toggle()
            } label: {
                Label(showingPanel ? "Hide Evolution" : "Evolution",
                      systemImage: showingPanel ? "sidebar.right" : "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("e", modifiers: [.command])
            .padding(.trailing)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func togglePreview() {
        if showingPreview {
            showingPreview = false
            DispatchQueue.main.async { engine.focusEditor() }
        } else {
            engine.prepareForPreview()
            showingPreview = true
        }
    }

    private var snapshotInfo: String {
        guard let latest = document.latestSnapshot else { return "No snapshots yet" }
        let when = latest.timestamp.formatted(.relative(presentation: .named))
        if let named = document.latestNamedSnapshot, named.id == latest.id {
            return "Saved “\(named.name ?? "")” \(when)"
        }
        return "Snapshot \(when)"
    }
}

// MARK: - Operator help

struct OperatorHelp: View {
    let op: Operator
    private static let objects: [(key: String, name: String)] = [
        ("w", "word"), ("c", "clause"), ("s", "sentence"), ("p", "paragraph"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(op.displayName.uppercased())…")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            Divider()
            ForEach(Self.objects, id: \.key) { item in
                HStack(spacing: 8) {
                    Text(item.key)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 14)
                    Text(item.name).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            Divider()
            Text("ESC to cancel").font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}

// MARK: - Status bar

extension EditorMode {
    var color: Color {
        switch self {
        case .normal: return .blue
        case .insert: return .green
        case .visual: return .orange
        case .command: return .purple
        case .search: return .teal
        }
    }
}

struct StatusBar: View {
    var isPreviewing = false
    let mode: EditorMode
    let pending: PendingKey
    let message: String?
    let stats: TextStats
    let snapshotInfo: String
    let hasUnsnapshottedChanges: Bool
    let openNotes: Int
    let searchMatchCount: Int
    var onShowStatistics: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(modeLabel)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isPreviewing ? Color.gray : mode.color)
                .cornerRadius(4)

            if let message = message {
                Text(message).font(.system(size: 11)).lineLimit(1)
            } else {
                Text(snapshotInfo)
                    .font(.system(size: 11))
                    .foregroundColor(hasUnsnapshottedChanges ? .orange : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            if openNotes > 0 {
                Label("\(openNotes)", systemImage: "note.text")
                    .font(.system(size: 11))
                    .foregroundColor(.purple)
            }
            Button {
                onShowStatistics?()
            } label: {
                Text("\(stats.paragraphs) ¶   \(stats.sentences) S   \(stats.words) W")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show statistics (⇧⌘I)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var modeLabel: String {
        if isPreviewing { return "PREVIEW" }
        switch mode {
        case .command(let text):
            return ":" + text
        case .search(let query):
            return "/" + query + (query.isEmpty ? "" : "  [\(searchMatchCount)]")
        default:
            switch pending {
            case .op(let op): return "\(mode.displayName)  \(op.rawValue)…"
            case .g: return "\(mode.displayName)  g…"
            case .none: return mode.displayName
            }
        }
    }
}
