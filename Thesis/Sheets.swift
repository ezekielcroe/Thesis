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
