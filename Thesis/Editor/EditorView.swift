// EditorView.swift — Thesis
// One document: title, the modal editor, the status bar, and the Evolution panel.

import SwiftUI

struct EditorView: View {
    @ObservedObject var document: Document
    @StateObject private var engine: EditorEngine
    @AppStorage("showEvolutionPanel") private var showingPanel = false
    @State private var panelTab: PanelTab = .history

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
                        EditorTextView(document: document, engine: engine)
                            .border(engine.mode.color.opacity(0.5), width: 2)
                        if let op = engine.pendingOperator {
                            OperatorHelp(op: op).padding(10)
                        }
                    }
                    StatusBar(
                        mode: engine.mode,
                        pending: engine.pending,
                        message: engine.message,
                        stats: engine.stats,
                        snapshotInfo: snapshotInfo,
                        hasUnsnapshottedChanges: document.hasUnsnapshottedChanges,
                        openNotes: document.notes.filter { !$0.resolved }.count,
                        searchMatchCount: engine.searchMatchCount
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
            }
        }
        .onReceive(engine.$panelRequest.compactMap { $0 }) { tab in
            panelTab = tab
            showingPanel = true
            engine.panelRequest = nil
        }
        .onDisappear { engine.flushSnapshots() }
    }

    private var header: some View {
        HStack {
            TextField("Title", text: $document.title)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding()
            Spacer()
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
    let mode: EditorMode
    let pending: PendingKey
    let message: String?
    let stats: TextStats
    let snapshotInfo: String
    let hasUnsnapshottedChanges: Bool
    let openNotes: Int
    let searchMatchCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(modeLabel)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(mode.color)
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
            Text("\(stats.paragraphs) ¶   \(stats.sentences) S   \(stats.words) W")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var modeLabel: String {
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
