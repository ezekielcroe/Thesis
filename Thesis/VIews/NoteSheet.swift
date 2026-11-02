//
//  NoteSheet.swift
//  Thesis
//
//  Created by Zhi Zheng Yeo on 2/11/26.
//


// Sheets.swift — Thesis
// Adding a note, the key reference, and Settings.

import SwiftUI

// MARK: - Note

struct NoteSheet: View {
    let anchorText: String
    let onSave: (String, NoteCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var category: NoteCategory = .note

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add note").font(.headline)
            Text("“\(String(anchorText.prefix(160)))\(anchorText.count > 160 ? "…" : "")”")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.06))
                .cornerRadius(6)
            Picker("", selection: $category) {
                ForEach(NoteCategory.allCases) { Label($0.displayName, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("Your note…", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Note") {
                    onSave(text, category)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

// MARK: - Help

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(title: String, items: [(String, String)])] = [
        ("Modes", [
            ("i", "Insert at the cursor — type freely, ESC to finish"),
            ("a / A", "Append a new sentence after this one / at the end of the paragraph"),
            ("I", "Insert at the start of this sentence"),
            ("o / O", "New paragraph below / above"),
            ("v", "Visual: select whole sentences (or the units you move by)"),
            (":", "Command line"),
            ("/", "Search"),
        ]),
        ("Move", [
            ("h / l", "Previous / next sentence"),
            ("H / L", "Previous / next clause"),
            ("k / j", "Previous / next paragraph"),
            ("b / w", "Previous / next word"),
            ("K / J", "Up / down one displayed line"),
            ("gg / G", "Top / bottom"),
            ("[ / ]", "Previous / next note"),
            ("n / N", "Next / previous search match"),
        ]),
        ("Act on a unit: verb + w c s p (word, clause, sentence, paragraph)", [
            ("d", "Delete (kept in the register)"),
            ("c", "Change: delete and start typing in its place"),
            ("y", "Yank (copy to the register)"),
            ("m", "Add a note"),
            ("p / P", "Put the register after / before the current unit"),
            ("D / C", "Delete / change to the end of the sentence"),
            ("x", "Delete one character"),
            (".", "Repeat the last change"),
            ("u / Ctrl-r", "Undo / redo"),
        ]),
        ("Moving text", [
            ("ds … p", "Cut a sentence, move, put it after the sentence there"),
            ("dp … p", "Same for a paragraph"),
        ]),
        ("Commands", [
            ("⌘S  or  :w", "Review changes, give reasons, save a named snapshot"),
            (":w name", "Save a named snapshot straight away"),
            (":review", "Review changes since the last named snapshot"),
            (":history  :darlings  :notes", "Open the Evolution panel"),
            ("⌘,", "Settings — when automatic snapshots are taken"),
            (":help", "This sheet"),
        ]),
    ]

    var body: some View {
        VStack(spacing: 14) {
            Text("Quick reference").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.blue)
                            Divider()
                            ForEach(section.items, id: \.0) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(item.0)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .frame(width: 190, alignment: .trailing)
                                    Text(item.1).font(.system(size: 12)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 520)
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(width: 600)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage(SnapshotSettings.triggerKey) private var trigger: SnapshotTrigger = .pause
    @AppStorage(SnapshotSettings.pauseKey) private var pauseSeconds = SnapshotSettings.defaultPauseSeconds
    @AppStorage(SnapshotSettings.intervalKey) private var intervalMinutes = SnapshotSettings.defaultIntervalMinutes

    var body: some View {
        Form {
            Picker("Take snapshots:", selection: $trigger) {
                ForEach(SnapshotTrigger.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)

            switch trigger {
            case .pause:
                Stepper("After \(pauseSeconds) seconds without typing",
                        value: $pauseSeconds, in: 5...600, step: 5)
            case .interval:
                Stepper("Every \(intervalMinutes) minute\(intervalMinutes == 1 ? "" : "s")",
                        value: $intervalMinutes, in: 1...120)
            case .manual:
                EmptyView()
            }

            Text(trigger.detail)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Named snapshots (⌘S or :w) are always available, whichever you choose.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 460)
    }
}
