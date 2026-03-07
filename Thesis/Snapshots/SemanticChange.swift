// SemanticChange.swift — Thesis
// Semantic change tracking: WHY edits happened, not just WHAT changed

import Foundation

// MARK: - Text Unit

struct TextUnit {
    let range: NSRange
    let text: String
    
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var endLocation: Int { range.location + range.length }
}

enum TextUnitType: String, Codable {
    case word
    case clause
    case sentence
    case paragraph
    case section
}

// MARK: - Semantic Change Type

enum SemanticChangeType: String, Codable, Equatable, CaseIterable {
    case added
    case deleted
    case replaced
    case moved
    
    // Backward compatibility: "refined" in persisted data decodes as .replaced
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "refined" {
            self = .replaced
        } else if let value = SemanticChangeType(rawValue: raw) {
            self = value
        } else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown SemanticChangeType: \(raw)"
            )
        }
    }
    
    var displayName: String {
        switch self {
        case .added:    return "Added"
        case .deleted:  return "Deleted"
        case .replaced: return "Replaced"
        case .moved:    return "Moved"
        }
    }
    
    var icon: String {
        switch self {
        case .added:    return "plus.circle.fill"
        case .deleted:  return "minus.circle.fill"
        case .replaced: return "arrow.triangle.2.circlepath"
        case .moved:    return "arrow.up.arrow.down"
        }
    }
    
    var color: String {
        switch self {
        case .added:    return "green"
        case .deleted:  return "red"
        case .replaced: return "orange"
        case .moved:    return "purple"
        }
    }
}

// MARK: - Semantic Change Record

struct SemanticChange: Identifiable, Codable, Equatable {
    let id: UUID
    let type: SemanticChangeType
    let unitType: TextUnitType
    let beforeText: String?
    let afterText: String?
    let position: Int
    let context: String
    let timestamp: Date
    
    init(
        type: SemanticChangeType,
        unitType: TextUnitType,
        beforeText: String? = nil,
        afterText: String? = nil,
        position: Int,
        context: String,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.type = type
        self.unitType = unitType
        self.beforeText = beforeText
        self.afterText = afterText
        self.position = position
        self.context = context
        self.timestamp = timestamp
    }
    
    var displayText: String {
        switch type {
        case .added:
            return afterText.map { "\"\(String($0.prefix(60)))\($0.count > 60 ? "…" : "")\"" } ?? ""
        case .deleted:
            return beforeText.map { "\"\(String($0.prefix(60)))\($0.count > 60 ? "…" : "")\"" } ?? ""
        case .replaced:
            let before = beforeText.map { String($0.prefix(30)) } ?? ""
            let after = afterText.map { String($0.prefix(30)) } ?? ""
            return "\"\(before)\" → \"\(after)\""
        case .moved:
            return context
        }
    }
    
    var summary: String { "\(type.displayName) \(unitType.rawValue)" }
    
    var isDarling: Bool { type == .deleted || type == .replaced }
    
    var lostText: String? {
        guard isDarling else { return nil }
        return beforeText
    }
}

// MARK: - Pending Change Tracker

class PendingChangeTracker {
    private(set) var change: SemanticChange?
    private(set) var insertStartPosition: Int?
    
    var hasPending: Bool { change != nil }
    
    func startChange(
        type: SemanticChangeType,
        unitType: TextUnitType,
        beforeText: String?,
        position: Int,
        context: String
    ) {
        change = SemanticChange(
            type: type,
            unitType: unitType,
            beforeText: beforeText,
            position: position,
            context: context
        )
        insertStartPosition = position
    }
    
    func completeChange(currentContent: String, cursorPosition: Int) -> SemanticChange? {
        guard let current = change else { return nil }
        let startPos = insertStartPosition ?? current.position
        let nsContent = currentContent as NSString
        
        let safeStart = max(0, min(startPos, nsContent.length))
        let safeEnd = max(safeStart, min(cursorPosition, nsContent.length))
        let insertedLength = safeEnd - safeStart
        
        var afterText = ""
        if insertedLength > 0 {
            let range = NSRange(location: safeStart, length: insertedLength)
            afterText = nsContent.substring(with: range)
        }
        
        let completed = SemanticChange(
            type: current.type,
            unitType: current.unitType,
            beforeText: current.beforeText,
            afterText: afterText.isEmpty ? nil : afterText,
            position: current.position,
            context: current.context,
            timestamp: current.timestamp
        )
        
        change = nil
        insertStartPosition = nil
        return completed
    }
    
    func completeChange(afterText: String) -> SemanticChange? {
        guard let current = change else { return nil }
        let completed = SemanticChange(
            type: current.type,
            unitType: current.unitType,
            beforeText: current.beforeText,
            afterText: afterText.isEmpty ? nil : afterText,
            position: current.position,
            context: current.context,
            timestamp: current.timestamp
        )
        change = nil
        insertStartPosition = nil
        return completed
    }
    
    func cancel() {
        change = nil
        insertStartPosition = nil
    }
}

// MARK: - Change Summary

struct ChangeSummary {
    let changes: [SemanticChange]
    
    var text: String {
        var counts: [SemanticChangeType: Int] = [:]
        for change in changes {
            counts[change.type, default: 0] += 1
        }
        let parts = counts.sorted { $0.key.displayName < $1.key.displayName }
            .map { "\($0.value) \($0.key.displayName.lowercased())" }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
    
    var breakdown: [(type: SemanticChangeType, count: Int)] {
        var counts: [SemanticChangeType: Int] = [:]
        for change in changes {
            counts[change.type, default: 0] += 1
        }
        return counts.map { (type: $0.key, count: $0.value) }
            .sorted { $0.type.displayName < $1.type.displayName }
    }
    
    var totalCount: Int { changes.count }
}
