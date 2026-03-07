// Sheets.swift — Thesis
// Modal sheets: FirstDraft, SaveDraft, Annotation (with categories), Branch, Merge

import SwiftUI

// MARK: - First Draft Sheet

struct FirstDraftSheet: View {
    @State private var draftName: String = ""
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "flag.fill").font(.system(size: 28)).foregroundColor(.green)
            Text("Save First Draft").font(.headline)
            Text("This becomes the baseline for tracking how your thinking evolves.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            TextField("Name (optional — auto-named if empty)", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { dismiss(); onSave(draftName) }
            HStack(spacing: 12) {
                Button("Cancel") { dismiss(); onCancel() }.keyboardShortcut(.escape)
                Button("Save") { dismiss(); onSave(draftName) }
                    .keyboardShortcut(.return).buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 420)
    }
}

// MARK: - Save Draft Sheet

struct SaveDraftSheet: View {
    let sessionSummary: String
    let onSave: (String, String) -> Void
    @State private var draftName: String = ""
    @State private var comment: String = ""
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) var dismiss
    enum Field { case name, comment }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.down").font(.system(size: 28)).foregroundColor(.blue)
            Text("Save Draft").font(.headline)
            if sessionSummary != "No changes" {
                Text(sessionSummary).font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary).padding(8)
                    .background(Color.secondary.opacity(0.1)).cornerRadius(6)
            }
            TextField("Draft name", text: $draftName)
                .textFieldStyle(.roundedBorder).focused($focusedField, equals: .name)
                .onSubmit { focusedField = .comment }
            TextField("What changed in your thinking?", text: $comment)
                .textFieldStyle(.roundedBorder).focused($focusedField, equals: .comment)
                .onSubmit { if !draftName.isEmpty && !comment.isEmpty { dismiss(); onSave(draftName, comment) } }
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save") { dismiss(); onSave(draftName, comment) }
                    .disabled(draftName.isEmpty || comment.isEmpty)
                    .keyboardShortcut(.return).buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 420).onAppear { focusedField = .name }
    }
}

// MARK: - Annotation Sheet (with categories)

struct AnnotationSheet: View {
    let anchorText: String
    let onSave: (String, AnnotationCategory) -> Void
    @State private var noteText: String = ""
    @State private var category: AnnotationCategory = .note
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text").font(.system(size: 28)).foregroundColor(.purple)
            Text("Add Note").font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Annotating:").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                Text("\"\(String(anchorText.prefix(100)))\(anchorText.count > 100 ? "…" : "")\"")
                    .font(.system(size: 12)).padding(8)
                    .background(Color.purple.opacity(0.05)).cornerRadius(6)
            }
            
            // Category picker
            Picker("Category", selection: $category) {
                ForEach(AnnotationCategory.allCases, id: \.self) { cat in
                    Label(cat.displayName, systemImage: cat.icon).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            
            TextField("Your note…", text: $noteText, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(3...6)
                .onSubmit { if !noteText.isEmpty { dismiss(); onSave(noteText, category) } }
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save Note") { dismiss(); onSave(noteText, category) }
                    .disabled(noteText.isEmpty)
                    .keyboardShortcut(.return).buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 440)
    }
}

// MARK: - Branch Sheet

struct BranchSheet: View {
    @ObservedObject var document: Document
    let onCreateBranch: (String, String) -> Void
    let onSwitchBranch: (String) -> Void
    let onDeleteBranch: (String) -> Void
    
    @State private var newBranchName: String = ""
    @State private var branchDescription: String = ""
    @State private var showingCreate = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 28)).foregroundColor(.purple)
            Text("Branches").font(.headline)
            
            // Existing branches
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(document.branches) { branch in
                        HStack {
                            Image(systemName: branch.name == document.activeBranchName ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(branch.name == document.activeBranchName ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(branch.name).font(.system(size: 13, weight: .medium))
                                if !branch.description.isEmpty {
                                    Text(branch.description).font(.system(size: 11)).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if branch.name != document.activeBranchName {
                                Button("Switch") { dismiss(); onSwitchBranch(branch.name) }
                                    .font(.system(size: 11)).buttonStyle(.borderless)
                                if branch.name != "main" {
                                    Button("Delete") { onDeleteBranch(branch.name) }
                                        .font(.system(size: 11)).buttonStyle(.borderless).foregroundColor(.red)
                                }
                            }
                        }
                        .padding(8)
                        .background(branch.name == document.activeBranchName ? Color.green.opacity(0.05) : Color.clear)
                        .cornerRadius(6)
                    }
                }
            }
            .frame(maxHeight: 200)
            
            Divider()
            
            // Create new branch
            if showingCreate {
                VStack(spacing: 8) {
                    TextField("Branch name", text: $newBranchName).textFieldStyle(.roundedBorder)
                    TextField("Description (optional)", text: $branchDescription).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") { showingCreate = false }.buttonStyle(.borderless)
                        Button("Create") {
                            if !newBranchName.isEmpty {
                                dismiss()
                                onCreateBranch(newBranchName, branchDescription)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newBranchName.isEmpty)
                    }
                }
            } else {
                Button("New Branch") { showingCreate = true }.buttonStyle(.borderedProminent)
            }
            
            Button("Close") { dismiss() }.keyboardShortcut(.escape)
        }
        .padding(24).frame(width: 400)
    }
}

// MARK: - Merge Sheet

struct MergeSheet: View {
    @ObservedObject var document: Document
    let onMerge: (String) -> Void
    
    @State private var selectedBranch: String = ""
    @Environment(\.dismiss) var dismiss
    
    var mergeCandidates: [Branch] {
        document.branches.filter { $0.name != document.activeBranchName }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.merge").font(.system(size: 28)).foregroundColor(.blue)
            Text("Merge Branch").font(.headline)
            Text("Merge another branch into '\(document.activeBranchName)'")
                .font(.subheadline).foregroundColor(.secondary)
            
            if mergeCandidates.isEmpty {
                Text("No other branches to merge.").foregroundColor(.secondary).padding()
            } else {
                Picker("Source branch", selection: $selectedBranch) {
                    Text("Select…").tag("")
                    ForEach(mergeCandidates) { branch in
                        Text(branch.name).tag(branch.name)
                    }
                }
                .onAppear { selectedBranch = mergeCandidates.first?.name ?? "" }
            }
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Merge") { dismiss(); onMerge(selectedBranch) }
                    .disabled(selectedBranch.isEmpty)
                    .keyboardShortcut(.return).buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 400)
    }
}

// MARK: - Help Sheet

struct HelpSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard").font(.system(size: 28)).foregroundColor(.blue)
            Text("Quick Reference").font(.headline)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    helpSection("Modes", items: [
                        ("ESC", "Return to Normal mode / Save first draft"),
                        ("i", "Insert at cursor (freeform)"),
                        ("a", "Append after sentence"),
                        ("v", "Visual selection mode"),
                        (":", "Command mode"),
                        ("/", "Search"),
                    ])
                    helpSection("Navigation", items: [
                        ("h / l", "Previous / next sentence"),
                        ("H / L", "Previous / next clause"),
                        ("j / k", "Next / previous paragraph"),
                        ("J / K", "Next / previous line"),
                        ("w / b", "Next / previous word"),
                        ("gg", "Jump to top"),
                        ("G", "Jump to bottom"),
                        ("n / N", "Next / previous search result"),
                    ])
                    helpSection("Editing (verb + object)", items: [
                        ("d + s/c/p/w", "Delete sentence/clause/paragraph/word"),
                        ("c + s/c/p/w", "Change (replace) sentence/clause/paragraph/word"),
                        ("r + s/c/p/w", "Refine (improve wording) sentence/clause/paragraph/word"),
                        ("y + s/c/p/w", "Yank (copy) to register"),
                        ("p", "Paste from register"),
                        ("x + s/p", "Move sentence/paragraph (then j/k, Enter)"),
                        ("m + s/c/p/w", "Annotate (add note)"),
                        ("D / C / R", "Delete/Change/Refine to end of sentence"),
                        (".", "Repeat last command"),
                        ("u", "Undo"),
                        ("Ctrl+r", "Redo"),
                    ])
                    helpSection("Argument Structure ('prefix)", items: [
                        ("'e", "Insert evidence after claim"),
                        ("'c", "Insert counterargument"),
                        ("'r", "Insert rebuttal"),
                        ("'b", "Add bridge between paragraphs"),
                        ("'t", "Add transition sentence"),
                    ])
                    helpSection("Commands", items: [
                        (":save / :commit", "Save draft with message"),
                        (":comp / :diff", "Compare with last draft"),
                        (":branch", "Manage branches"),
                        (":merge", "Merge a branch"),
                        (":log", "View commit history"),
                        (":help", "Show this help"),
                        (":ie :ic :ir :ab :at", "Argument commands (long form)"),
                    ])
                }
            }
            .frame(maxHeight: 500)
            
            Button("Close") { dismiss() }
                .keyboardShortcut(.escape).buttonStyle(.borderedProminent)
        }
        .padding(24).frame(width: 520)
    }
    
    private func helpSection(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.blue)
            Divider()
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 12) {
                    Text(item.0)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 160, alignment: .trailing)
                        .foregroundColor(.primary)
                    Text(item.1)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Log Sheet (Inline History)

struct LogSheet: View {
    @ObservedObject var document: Document
    let onRestore: (Draft) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 28)).foregroundColor(.blue)
            Text("Commit History").font(.headline)
            
            if document.branches.count > 1 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundColor(.purple)
                    Text(document.activeBranchName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            }
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    if document.hasUnsavedChanges {
                        logEntry(
                            icon: "circle.fill", iconColor: .orange,
                            title: "Working Draft (unsaved)",
                            subtitle: document.sessionChangeSummary,
                            timestamp: "now", isHead: true
                        )
                    }
                    
                    let branchDrafts = document.currentBranchDrafts.reversed()
                    ForEach(Array(branchDrafts)) { draft in
                        logEntry(
                            icon: draft.isFirstDraft ? "flag.fill" : draft.isMergeCommit ? "arrow.triangle.merge" : "circle.fill",
                            iconColor: draft.isFirstDraft ? .green : draft.isMergeCommit ? .purple : .blue,
                            title: draft.displayName,
                            subtitle: draft.comment.isEmpty ? draft.changeSummary : draft.comment,
                            timestamp: draft.displayTimestamp,
                            isHead: false
                        )
                        .contextMenu {
                            Button("Restore to this draft") { dismiss(); onRestore(draft) }
                        }
                    }
                    
                    if document.drafts.isEmpty {
                        Text("No commits yet").foregroundColor(.secondary).padding(20)
                    }
                }
            }
            .frame(maxHeight: 400)
            
            Button("Close") { dismiss() }
                .keyboardShortcut(.escape).buttonStyle(.borderedProminent)
        }
        .padding(24).frame(width: 480)
    }
    
    private func logEntry(icon: String, iconColor: Color, title: String, subtitle: String, timestamp: String, isHead: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Image(systemName: icon).font(.system(size: 8)).foregroundColor(iconColor)
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1)
            }
            .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(timestamp).font(.system(size: 10)).foregroundColor(.secondary)
                }
                Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isHead ? Color.orange.opacity(0.05) : Color.clear)
    }
}
