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
                            DraftRow(
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

struct DraftRow: View {
    let draft: Draft
    let isCurrent: Bool
    let onRestore: () -> Void
    
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
                    
                    if !draft.comment.isEmpty {
                        Text(draft.comment)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(draft.displayTimestamp)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            // Preview of content (first line)
            Text(draft.content.components(separatedBy: .newlines).first ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.leading, 20)
        }
        .padding(12)
        .background(isCurrent ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}
