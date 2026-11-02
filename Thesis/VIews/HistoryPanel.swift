// HistoryPanel.swift — Thesis
// The Evolution panel: snapshot history with the changes and reasons between named
// snapshots, darlings (everything ever cut), and notes.

import SwiftUI

struct HistoryPanel: View {
    @ObservedObject var document: Document
    @Binding var tab: PanelTab
    let onJump: (NSRange) -> Void
    let onRestore: (Snapshot) -> Void
    let onReview: () -> Void
    let onPutInRegister: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Evolution").font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Picker("", selection: $tab) {
                ForEach(PanelTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .history: historyTab
                    case .darlings: darlingsTab
                    case .notes: notesTab
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - History

    private enum HistoryRow: Identifiable {
        case named(Snapshot)
        case automatic([Snapshot])

        var id: String {
            switch self {
            case .named(let s): return s.id.uuidString
            case .automatic(let run): return "auto-" + (run.first?.id.uuidString ?? "")
            }
        }
    }

    /// Newest first; consecutive automatic snapshots are folded into one row.
    private var rows: [HistoryRow] {
        var rows: [HistoryRow] = []
        var run: [Snapshot] = []
        for snapshot in document.snapshots.reversed() {
            if snapshot.isAutomatic {
                run.append(snapshot)
            } else {
                if !run.isEmpty { rows.append(.automatic(run)); run = [] }
                rows.append(.named(snapshot))
            }
        }
        if !run.isEmpty { rows.append(.automatic(run)) }
        return rows
    }

    @ViewBuilder private var historyTab: some View {
        workingCard
        Divider().padding(.horizontal, 12)
        if document.snapshots.isEmpty {
            emptyState("No snapshots yet",
                       "Snapshots are taken as you write (see Settings), or save one with ⌘S.")
        }
        ForEach(rows) { row in
            switch row {
            case .named(let snapshot): namedCard(snapshot)
            case .automatic(let run): automaticCard(run)
            }
            Divider().padding(.horizontal, 12)
        }
    }

    private var workingCard: some View {
        let changes = document.changesSinceLastNamedSnapshot()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(changes.isEmpty ? Color.secondary : Color.orange).frame(width: 8, height: 8)
                Text("Now").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Review…", action: onReview)
                    .font(.system(size: 11))
                    .buttonStyle(.borderless)
                    .disabled(changes.isEmpty)
            }
            Text(changes.isEmpty
                 ? "No changes since the last named snapshot."
                 : "\(summary(changes)) since \(document.latestNamedSnapshot?.name.map { "“\($0)”" } ?? "you started")")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
    }

    private func namedCard(_ snapshot: Snapshot) -> some View {
        let changes = document.changes(from: document.namedSnapshot(before: snapshot), to: snapshot)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "flag.fill").font(.system(size: 9)).foregroundColor(.blue)
                Text(snapshot.name ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            if !snapshot.note.isEmpty {
                Text(snapshot.note).font(.system(size: 11)).foregroundColor(.secondary)
            }
            if !changes.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                            ChangeRow(change: change, reason: document.reason(for: change.fingerprint))
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text(summary(changes)).font(.system(size: 11))
                }
            }
            Button("Restore") { onRestore(snapshot) }
                .font(.system(size: 10))
                .buttonStyle(.borderless)
                .foregroundColor(.blue)
        }
        .padding(12)
    }

    private func automaticCard(_ run: [Snapshot]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(run) { snapshot in
                    HStack {
                        Text(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                        Spacer()
                        Button("Restore") { onRestore(snapshot) }
                            .font(.system(size: 10))
                            .buttonStyle(.borderless)
                    }
                }
            }
        } label: {
            Text(run.count == 1 ? "1 automatic snapshot" : "\(run.count) automatic snapshots")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
    }

    private func summary(_ changes: [ProseChange]) -> String {
        let counts = ChangeKind.allCases.compactMap { kind -> String? in
            let n = changes.filter { $0.kind == kind }.count
            return n > 0 ? "\(n) \(kind.rawValue)" : nil
        }
        return counts.isEmpty ? "No changes" : counts.joined(separator: ", ")
    }

    // MARK: - Darlings

    @ViewBuilder private var darlingsTab: some View {
        if document.darlings.isEmpty {
            emptyState("No darlings yet",
                       "Anything you cut or rewrite is kept here when a snapshot is taken. You'll never lose a sentence.")
        }
        ForEach(document.darlings.reversed()) { darling in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "scissors").font(.system(size: 10)).foregroundColor(.red)
                    Text(darling.cutAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                }
                Text(darling.text).font(.system(size: 12)).textSelection(.enabled)
                if let replacement = darling.replacedBy {
                    Text("Became: \(replacement)")
                        .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(3)
                }
                if let reason = document.reason(for: darling.fingerprint) {
                    Text("Why: \(reason)").font(.system(size: 11).italic()).foregroundColor(.secondary)
                }
                HStack(spacing: 10) {
                    Button("Put in register") { onPutInRegister(darling.text) }
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(darling.text, forType: .string)
                    }
                }
                .font(.system(size: 10))
                .buttonStyle(.borderless)
                .foregroundColor(.blue)
            }
            .padding(12)
            Divider().padding(.horizontal, 12)
        }
    }

    // MARK: - Notes

    @ViewBuilder private var notesTab: some View {
        if document.notes.isEmpty {
            emptyState("No notes yet", "In Normal mode press m then w, c, s or p to note a word, clause, sentence or paragraph.")
        }
        let open = document.notes.filter { !$0.resolved }.sorted { $0.location < $1.location }
        let resolved = document.notes.filter { $0.resolved }
        ForEach(open) { noteCard($0) }
        if !resolved.isEmpty {
            Text("Resolved")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            ForEach(resolved) { noteCard($0) }
        }
    }

    private func noteCard(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(note.category.displayName, systemImage: note.category.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(note.resolved ? .secondary : .purple)
                Spacer()
                if !note.isDetached {
                    Button { onJump(note.range) } label: { Image(systemName: "location") }
                        .buttonStyle(.borderless)
                        .help("Go to the annotated text")
                }
            }
            Text(note.isDetached ? "(text removed) “\(note.anchorText)”" : "“\(note.anchorText)”")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
            Text(note.text).font(.system(size: 12)).opacity(note.resolved ? 0.5 : 1)
            HStack(spacing: 10) {
                Button(note.resolved ? "Reopen" : "Resolve") { document.setResolved(note.id, !note.resolved) }
                Button("Delete") { document.deleteNote(note.id) }.foregroundColor(.red)
            }
            .font(.system(size: 10))
            .buttonStyle(.borderless)
        }
        .padding(12)
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
            Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
