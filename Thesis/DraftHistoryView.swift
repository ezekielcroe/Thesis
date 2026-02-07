import SwiftUI

struct DraftHistoryView: View {
    let document: Document
    let onRestore: (Draft) -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Evolution Timeline")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Draft list
            if document.drafts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No drafts saved yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Press ESC to save your first draft")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(document.drafts.reversed()) { draft in
                            EnhancedDraftRow(
                                draft: draft,
                                isCurrent: draft.id == document.latestDraft?.id,
                                onRestore: { onRestore(draft) }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct EnhancedDraftRow: View {
    let draft: Draft
    let isCurrent: Bool
    let onRestore: () -> Void
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Timeline indicator
                Circle()
                    .fill(isCurrent ? Color.blue : Color.gray)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(draft.displayName)
                            .font(.system(size: 14, weight: .semibold))
                        
                        if isCurrent {
                            Text("CURRENT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(3)
                        }
                        
                        Spacer()
                        
                        if !isCurrent {
                            Button("Restore") {
                                onRestore()
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                        }
                    }
                    
                    // Comment
                    if !draft.comment.isEmpty {
                        Text(draft.comment)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    // ENHANCED: Semantic change summary
                    if !draft.changes.isEmpty {
                        HStack(spacing: 8) {
                            // Change summary
                            Text(draft.changeSummary)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            // Expand/collapse button
                            Button(action: { isExpanded.toggle() }) {
                                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Text(draft.displayTimestamp)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            // ENHANCED: Expanded change details
            if isExpanded && !draft.changes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draft.changes) { change in
                        SemanticChangeRow(change: change)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 4)
            }
            
            // Preview of content (first line)
            if !isExpanded {
                Text(draft.content.components(separatedBy: .newlines).first ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 20)
            }
        }
        .padding(12)
        .background(isCurrent ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Semantic Change Row

struct SemanticChangeRow: View {
    let change: SemanticChange
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Icon
            Image(systemName: change.type.icon)
                .font(.system(size: 10))
                .foregroundColor(colorForType(change.type))
            
            VStack(alignment: .leading, spacing: 2) {
                // Type and unit
                HStack(spacing: 4) {
                    Text(change.type.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(colorForType(change.type))
                    
                    Text(change.unitType.rawValue)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                // Change details
                Text(change.displayText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // Context
                if !change.context.isEmpty {
                    Text(change.context)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                        .italic()
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(colorForType(change.type).opacity(0.1))
        .cornerRadius(4)
    }
    
    private func colorForType(_ type: SemanticChangeType) -> Color {
        switch type {
        case .added: return .green
        case .deleted: return .red
        case .replaced: return .orange
        case .refined: return .blue
        case .moved: return .purple
        case .evidenced: return .cyan
        case .rebutted: return .pink
        }
    }
}

// MARK: - Preview

struct DraftHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        let doc = Document(title: "Test")
        
        // Create sample drafts with changes
        let change1 = SemanticChange(
            type: .added,
            unitType: .sentence,
            beforeText: nil,
            afterText: "This is a new sentence.",
            position: 0,
            context: "added at beginning"
        )
        
        let change2 = SemanticChange(
            type: .refined,
            unitType: .word,
            beforeText: "good",
            afterText: "excellent",
            position: 10,
            context: "word 'good'"
        )
        
        let draft1 = Draft(
            name: "Initial thoughts",
            content: "This is a new sentence.",
            comment: "First capture",
            isFirstDraft: true
        )
        
        let draft2 = Draft(
            name: "Refined version",
            content: "This is an excellent sentence.",
            comment: "Improved wording",
            parentId: draft1.id,
            changes: [change1, change2]
        )
        
        doc.drafts = [draft1, draft2]
        
        return DraftHistoryView(
            document: doc,
            onRestore: { _ in },
            onClose: { }
        )
        .frame(width: 340, height: 600)
    }
}
