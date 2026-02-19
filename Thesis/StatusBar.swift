// StatusBar.swift — Thesis
// Bottom status bar showing mode, stats, and contextual info

import SwiftUI

struct StatusBar: View {
    let mode: EditorMode
    let pendingVerb: EditVerb?
    let stats: TextAnalyzer.Stats
    let draftInfo: String
    let hasUnsavedChanges: Bool
    let branchInfo: String?
    let diffInfo: EditorDiffInfo?
    let undoPreview: String?
    let annotationCount: Int
    let sessionSummary: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(modeDisplayText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(mode.statusColor)
                .cornerRadius(4)
            
            Group {
                if let diff = diffInfo {
                    diffInfoView(diff)
                } else if let verb = pendingVerb {
                    verbPendingView(verb)
                } else {
                    defaultInfoView
                }
            }
            
            Spacer()
            
            if annotationCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "note.text")
                        .font(.system(size: 10))
                    Text("\(annotationCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(3)
            }
            
            HStack(spacing: 12) {
                Text("\(stats.paragraphCount) ¶")
                Text("\(stats.sentenceCount) S")
                Text("\(stats.wordCount) W")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var modeDisplayText: String {
        if let verb = pendingVerb {
            return "\(mode.displayName) → \(verb.displayName)…"
        }
        if case .command(let text) = mode {
            return ":\(text)"
        }
        return mode.displayName
    }
    
    private func diffInfoView(_ diff: EditorDiffInfo) -> some View {
        HStack(spacing: 8) {
            Text("Change \(diff.currentIndex + 1)/\(diff.totalChanges)")
                .font(.system(size: 11, design: .monospaced))
            if let change = diff.currentChange { changeBadge(for: change) }
            Text("n: next  p: prev  ESC: exit")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    private func changeBadge(for change: DiffChange) -> some View {
        Group {
            switch change.type {
            case .addition:
                let label = change.semanticType?.displayName.uppercased() ?? "ADDED"
                let color: Color = {
                    switch change.semanticType {
                    case .refined:  return .blue
                    case .replaced: return .orange
                    default:        return .green
                    }
                }()
                Text(label).font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color).cornerRadius(3)
            case .deletion:
                let preview = String(change.text.prefix(40))
                Text("DELETED: \"\(preview)\"")
                    .font(.system(size: 10)).foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red).cornerRadius(3).lineLimit(1)
            case .moved:
                Text("MOVED").font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.purple).cornerRadius(3)
            case .unchanged:
                EmptyView()
            }
        }
    }
    
    private func verbPendingView(_ verb: EditVerb) -> some View {
        HStack(spacing: 8) {
            Text("Waiting for object:")
                .font(.system(size: 11)).foregroundColor(.secondary)
            ForEach(verb.helpItems.prefix(5), id: \.key) { item in
                HStack(spacing: 2) {
                    Text(item.key).font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text(item.description).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var defaultInfoView: some View {
        HStack(spacing: 8) {
            Text(draftInfo)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(hasUnsavedChanges ? .orange : .secondary)
            if hasUnsavedChanges {
                Text("•").font(.system(size: 14, weight: .bold)).foregroundColor(.orange)
            }
            if let branch = branchInfo {
                Text(branch)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - Verb Help Overlay

struct VerbHelpOverlay: View {
    let verb: EditVerb
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verb.displayName)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            Divider()
            ForEach(verb.helpItems, id: \.key) { item in
                HStack(spacing: 8) {
                    Text(item.key)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 16, alignment: .center)
                        .foregroundColor(verb == .delete ? .red : verb == .refine ? .blue : .primary)
                    Text(item.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Divider()
            Text("ESC to cancel")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}
