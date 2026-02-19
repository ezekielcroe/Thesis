// DraftHistoryView.swift — Thesis
// Version history sidebar: commits (branch-aware), darlings, annotations (with categories)

import SwiftUI

struct DraftHistoryView: View {
    @ObservedObject var document: Document
    let onRestore: (Draft) -> Void
    let onNavigateToAnnotation: ((Annotation) -> Void)?
    let onClose: () -> Void
    
    @State private var selectedTab: HistoryTab = .commits
    @State private var editingAnnotation: Annotation?
    @State private var editText: String = ""
    
    enum HistoryTab: String, CaseIterable {
        case commits = "History"
        case darlings = "Darlings"
        case annotations = "Notes"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Evolution").font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            
            Picker("", selection: $selectedTab) {
                ForEach(HistoryTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.bottom, 8)
            
            Divider()
            
            switch selectedTab {
            case .commits:    commitsView
            case .darlings:   darlingsView
            case .annotations: annotationsView
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Commits
    
    private var commitsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Branch indicator
                if document.branches.count > 1 {
                    branchIndicator
                    Divider().padding(.horizontal, 12)
                }
                
                if document.hasUnsavedChanges {
                    sessionCard
                    Divider().padding(.horizontal, 12)
                }
                
                let branchDrafts = document.currentBranchDrafts.reversed()
                ForEach(Array(branchDrafts)) { draft in
                    draftCard(draft)
                    Divider().padding(.horizontal, 12)
                }
                
                if document.drafts.isEmpty {
                    emptyState("No commits yet", subtitle: "Press ESC in Free Text mode to save your first draft.")
                }
            }
        }
    }
    
    private var branchIndicator: some View {
        HStack {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 12))
                .foregroundColor(.purple)
            Text(document.activeBranchName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text("(\(document.branches.count) branches)")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
        .padding(12)
    }
    
    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("Working Draft").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("unsaved").font(.system(size: 10)).foregroundColor(.orange)
            }
            if !document.sessionChanges.isEmpty {
                Text(document.sessionChangeSummary).font(.system(size: 11)).foregroundColor(.secondary)
                ForEach(document.sessionChanges.suffix(5)) { change in
                    changeRow(change)
                }
                if document.sessionChanges.count > 5 {
                    Text("+ \(document.sessionChanges.count - 5) more")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
    }
    
    private func draftCard(_ draft: Draft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: draft.isMergeCommit ? "arrow.triangle.merge" :
                        draft.isFirstDraft ? "flag.fill" : "circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(draft.isFirstDraft ? .green : draft.isMergeCommit ? .purple : .blue)
                Text(draft.displayName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(draft.displayTimestamp).font(.system(size: 10)).foregroundColor(.secondary)
            }
            if !draft.comment.isEmpty {
                Text(draft.comment).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
            }
            if !draft.changes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(ChangeSummary(changes: draft.changes).breakdown, id: \.type) { item in
                        HStack(spacing: 2) {
                            Image(systemName: item.type.icon).font(.system(size: 9))
                            Text("\(item.count)").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(colorForSemanticType(item.type.color))
                    }
                }
            }
            Button("Restore") { onRestore(draft) }
                .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.blue)
        }
        .padding(12)
    }
    
    private func changeRow(_ change: SemanticChange) -> some View {
        HStack(spacing: 6) {
            Image(systemName: change.type.icon).font(.system(size: 10))
                .foregroundColor(colorForSemanticType(change.type.color))
            Text(change.summary).font(.system(size: 10, weight: .medium))
            Text(change.displayText).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
        }
    }
    
    // MARK: - Darlings
    
    private var darlingsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let darlings = document.allDarlings
                if darlings.isEmpty {
                    emptyState("No darlings yet",
                               subtitle: "Deleted and replaced text will appear here. You'll never lose a word.")
                } else {
                    ForEach(Array(darlings.enumerated()), id: \.offset) { _, darling in
                        darlingCard(text: darling.text, draft: darling.draft, date: darling.date)
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
        }
    }
    
    private func darlingCard(text: String, draft: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "text.badge.minus").font(.system(size: 10)).foregroundColor(.red)
                Text(draft).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                Spacer()
                Text(date, style: .relative).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Text(text).font(.system(size: 12)).lineLimit(4).textSelection(.enabled)
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.blue)
        }
        .padding(12)
    }
    
    // MARK: - Annotations (with categories, edit, navigate)
    
    private var annotationsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if document.annotations.isEmpty {
                    emptyState("No notes yet", subtitle: "Press m + object in Normal mode to annotate text.")
                } else {
                    // Group by category
                    let grouped = document.annotationsByCategory
                    let orderedCategories = AnnotationCategory.allCases.filter { grouped[$0] != nil }
                    
                    ForEach(orderedCategories, id: \.self) { category in
                        if let annotations = grouped[category] {
                            categoryHeader(category, count: annotations.count)
                            ForEach(annotations) { annotation in
                                annotationCard(annotation)
                                Divider().padding(.horizontal, 12)
                            }
                        }
                    }
                    
                    // Resolved annotations
                    let resolved = document.annotations.filter(\.resolved)
                    if !resolved.isEmpty {
                        categoryHeader(nil, count: resolved.count, label: "Resolved")
                        ForEach(resolved) { annotation in
                            annotationCard(annotation)
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    }
    
    private func categoryHeader(_ category: AnnotationCategory?, count: Int, label: String? = nil) -> some View {
        HStack {
            if let cat = category {
                Image(systemName: cat.icon).font(.system(size: 11))
                    .foregroundColor(colorForSemanticType(cat.color))
                Text(cat.displayName).font(.system(size: 12, weight: .semibold))
            } else {
                Image(systemName: "checkmark.circle").font(.system(size: 11)).foregroundColor(.green)
                Text(label ?? "").font(.system(size: 12, weight: .semibold))
            }
            Text("(\(count))").font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05))
    }
    
    private func annotationCard(_ annotation: Annotation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: annotation.resolved ? "checkmark.circle.fill" : annotation.category.icon)
                    .font(.system(size: 10))
                    .foregroundColor(annotation.resolved ? .green : colorForSemanticType(annotation.category.color))
                Text(annotation.displayTimestamp).font(.system(size: 10)).foregroundColor(.secondary)
                
                if annotation.isStale {
                    Text("stale").font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.1)).cornerRadius(3)
                }
                
                Spacer()
                
                // Navigate button
                Button {
                    onNavigateToAnnotation?(annotation)
                } label: {
                    Image(systemName: "location").font(.system(size: 10))
                }
                .buttonStyle(.borderless).foregroundColor(.blue)
            }
            
            Text("on: \"\(String(annotation.anchorText.prefix(60)))\"")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary).lineLimit(1)
            
            if editingAnnotation?.id == annotation.id {
                HStack {
                    TextField("Edit note", text: $editText)
                        .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    Button("Save") {
                        document.updateAnnotation(annotation.id, text: editText)
                        editingAnnotation = nil
                    }
                    .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.blue)
                }
            } else {
                Text(annotation.text).font(.system(size: 12))
                    .opacity(annotation.resolved ? 0.5 : 1)
            }
            
            HStack(spacing: 8) {
                if !annotation.resolved {
                    Button("Resolve") { document.resolveAnnotation(annotation) }
                        .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.green)
                    Button("Edit") {
                        editText = annotation.text
                        editingAnnotation = annotation
                    }
                    .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.blue)
                } else {
                    Button("Reopen") { document.unresolveAnnotation(annotation) }
                        .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.orange)
                }
                Button("Delete") { document.deleteAnnotation(annotation) }
                    .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.red)
            }
        }
        .padding(12)
    }
    
    private func emptyState(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
            Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(24)
    }
}
