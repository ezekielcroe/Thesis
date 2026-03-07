// DraftHistoryView.swift — Thesis
// Version history sidebar: commits (branch-aware), darlings, annotations (simplified)

import SwiftUI

struct DraftHistoryView: View {
    @ObservedObject var document: Document
    let onRestore: (Draft) -> Void
    let onNavigateToAnnotation: ((Annotation) -> Void)?
    let onClose: () -> Void
    
    @State private var selectedTab: HistoryTab = .commits
    @State private var editingAnnotation: Annotation?
    @State private var editText: String = ""
    @State private var editingCitation: Citation?
    @State private var editCitationKey: String = ""
    @State private var editCitationSource: String = ""
    
    enum HistoryTab: String, CaseIterable {
        case commits = "History"
        case darlings = "Darlings"
        case annotations = "Notes"
        case citations = "Cites"
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
            case .citations:  citationsView
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Commits
    
    private var commitsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
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
    
    // MARK: - Annotations (simplified — flat list, no categories)
    
    private var annotationsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if document.annotations.isEmpty {
                    emptyState("No notes yet", subtitle: "Press m + object in Normal mode to annotate text, or c + object to add a citation.")
                } else {
                    // Active (unresolved) annotations
                    let active = document.annotations.filter { !$0.resolved }
                    if !active.isEmpty {
                        sectionHeader("Active", count: active.count, color: .purple)
                        ForEach(active) { annotation in
                            annotationCard(annotation)
                            Divider().padding(.horizontal, 12)
                        }
                    }
                    
                    // Resolved annotations
                    let resolved = document.annotations.filter(\.resolved)
                    if !resolved.isEmpty {
                        sectionHeader("Resolved", count: resolved.count, color: .green)
                        ForEach(resolved) { annotation in
                            annotationCard(annotation)
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    }
    
    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text("(\(count))").font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05))
    }
    
    private func annotationCard(_ annotation: Annotation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: annotation.resolved ? "checkmark.circle.fill" : "note.text")
                    .font(.system(size: 10))
                    .foregroundColor(annotation.resolved ? .green : .purple)
                Text(annotation.displayTimestamp).font(.system(size: 10)).foregroundColor(.secondary)
                
                if annotation.isStale {
                    Text("stale").font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.1)).cornerRadius(3)
                }
                
                Spacer()
                
                // Navigate to anchor in editor
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
    
    // MARK: - Citations
    
    private var citationsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if document.citations.isEmpty {
                    emptyState("No citations yet", subtitle: "Press c + object in Normal mode to cite text.\nA [Key] marker will be inserted inline.")
                } else {
                    // Active citations (marker still in text)
                    let active = document.citations.filter { !$0.isOrphaned(in: document.currentContent) }
                    let orphaned = document.citations.filter { $0.isOrphaned(in: document.currentContent) }
                    
                    if !active.isEmpty {
                        sectionHeader("Active", count: active.count, color: .teal)
                        ForEach(active) { citation in
                            citationCard(citation, isOrphaned: false)
                            Divider().padding(.horizontal, 12)
                        }
                    }
                    
                    if !orphaned.isEmpty {
                        sectionHeader("Orphaned", count: orphaned.count, color: .orange)
                        ForEach(orphaned) { citation in
                            citationCard(citation, isOrphaned: true)
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    }
    
    private func citationCard(_ citation: Citation, isOrphaned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(citation.marker)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(isOrphaned ? .orange : .teal)
                
                if isOrphaned {
                    Text("marker missing")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.1)).cornerRadius(3)
                }
                
                Spacer()
                
                Text(citation.displayTimestamp)
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            
            // Show what text is being cited
            Text("on: \"\(String(citation.anchorText.prefix(60)))\"")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary).lineLimit(1)
            
            if editingCitation?.id == citation.id {
                // Editing mode
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text("Key:").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                        TextField("Key", text: $editCitationKey)
                            .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    }
                    HStack(spacing: 4) {
                        Text("Src:").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                        TextField("Source", text: $editCitationSource)
                            .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    }
                    HStack(spacing: 6) {
                        Button("Save") {
                            let cleanKey = editCitationKey
                                .replacingOccurrences(of: "[", with: "")
                                .replacingOccurrences(of: "]", with: "")
                                .trimmingCharacters(in: .whitespaces)
                            if !cleanKey.isEmpty && cleanKey != citation.key {
                                document.renameCitationKey(citation.id, newKey: cleanKey)
                            }
                            document.updateCitationSource(citation.id, source: editCitationSource)
                            editingCitation = nil
                        }
                        .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.blue)
                        Button("Cancel") { editingCitation = nil }
                            .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.secondary)
                    }
                }
            } else {
                // Display mode
                if !citation.source.isEmpty {
                    Text(citation.source)
                        .font(.system(size: 11)).foregroundColor(.primary)
                        .lineLimit(3)
                } else {
                    Text("No source details")
                        .font(.system(size: 11)).foregroundColor(.secondary).italic()
                }
            }
            
            HStack(spacing: 8) {
                if !isOrphaned {
                    Button("Jump") {
                        // Navigate to the marker in the editor
                        if let range = citation.markerRange(in: document.currentContent) {
                            onNavigateToAnnotation?(
                                // Reuse the annotation navigation callback with a dummy Annotation
                                // to position the editor at the citation's location
                                Annotation(text: "", anchorText: citation.marker, anchorPosition: range.location)
                            )
                        }
                    }
                    .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.blue)
                }
                Button("Edit") {
                    editCitationKey = citation.key
                    editCitationSource = citation.source
                    editingCitation = citation
                }
                .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.blue)
                Button("Delete") { document.deleteCitation(citation) }
                    .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(.red)
            }
        }
        .padding(12)
        .opacity(isOrphaned ? 0.7 : 1)
    }
    
    private func emptyState(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
            Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(24)
    }
}
