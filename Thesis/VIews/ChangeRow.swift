// ChangeRow.swift — Thesis
// Shows one ProseChange: what kind it is and the text, with rewordings inline.

import SwiftUI

extension ChangeKind {
    var color: Color {
        switch self {
        case .added: return .green
        case .cut: return .red
        case .reworded: return .blue
        case .rewritten: return .orange
        case .moved: return .purple
        }
    }
}

struct ChangeRow: View {
    let change: ProseChange
    var reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(change.kind.displayName, systemImage: change.kind.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(change.kind.color)
            content(for: change)
                .font(.system(size: 12))
                .lineLimit(8)
                .textSelection(.enabled)
            if let reason = reason, !reason.isEmpty {
                Text("Why: \(reason)")
                    .font(.system(size: 11).italic())
                    .foregroundColor(.secondary)
            }
        }
    }

    private func content(for change: ProseChange) -> Text {
        switch change.kind {
        case .added:
            return Text(change.after ?? "")
        case .cut:
            return Text(change.before ?? "").strikethrough(color: .red).foregroundColor(.secondary)
        case .moved:
            return Text(change.after ?? "")
        case .reworded:
            return inlineDiff(change.wordDiff)
        case .rewritten:
            return Text(change.before ?? "").strikethrough(color: .red).foregroundColor(.secondary)
                + Text("\n")
                + Text(change.after ?? "")
        }
    }

    private func inlineDiff(_ parts: [WordDiffPart]) -> Text {
        parts.reduce(Text("")) { result, part in
            switch part.kind {
            case .same: return result + Text(part.text)
            case .removed: return result + Text(part.text).strikethrough(color: .red).foregroundColor(.red)
            case .added: return result + Text(part.text).foregroundColor(.green)
            }
        }
    }
}
