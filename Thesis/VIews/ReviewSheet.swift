// ReviewSheet.swift — Thesis
// "What did I change, and why?" Lists the changes since the last named snapshot,
// lets the writer note a reason against any of them, and saves a named snapshot.
// Opened with ⌘S, :w, or :review.

import SwiftUI

struct ReviewSheet: View {
    @ObservedObject var document: Document
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var changes: [ProseChange] = []
    @State private var name = ""
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review changes").font(.headline)
            Text(sinceLabel).font(.subheadline).foregroundColor(.secondary)

            if changes.isEmpty {
                Text("Nothing has changed since then.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                            VStack(alignment: .leading, spacing: 6) {
                                ChangeRow(change: change)
                                TextField("Why? (optional)", text: reasonBinding(for: change.fingerprint))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.07))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(minHeight: 200, maxHeight: 420)
            }

            Divider()

            Text("Save as a named snapshot").font(.subheadline.weight(.semibold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            TextField("What changed in your thinking? (optional)", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            HStack {
                Text("Reasons are kept even if you close without saving.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Snapshot") {
                    onSave(name, note)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 580)
        .onAppear {
            changes = document.changesSinceLastNamedSnapshot()
            if name.isEmpty { name = Date().formatted(date: .abbreviated, time: .shortened) }
        }
    }

    private var sinceLabel: String {
        guard let named = document.latestNamedSnapshot else { return "Since you started" }
        return "Since “\(named.name ?? "")”, \(named.timestamp.formatted(date: .abbreviated, time: .shortened))"
    }

    private func reasonBinding(for fingerprint: String) -> Binding<String> {
        Binding(
            get: { document.reason(for: fingerprint) ?? "" },
            set: { document.setReason($0, for: fingerprint) }
        )
    }
}
