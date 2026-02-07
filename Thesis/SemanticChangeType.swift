//
//  SemanticChangeType.swift
//  Thesis
//
//  Created by Zhi Zheng Yeo on 7/2/26.
//


import Foundation

// MARK: - Semantic Change Types

/// Represents WHY an edit happened, not just WHAT changed
enum SemanticChangeType: String, Codable, Equatable {
    case added       // New thought introduced
    case deleted     // Idea removed/abandoned
    case replaced    // Changed position/argument (changed my mind)
    case refined     // Same idea, better expression (improved wording)
    case moved       // Reorganized structure (Phase 2)
    case evidenced   // Added supporting evidence (future)
    case rebutted    // Countered an argument (future)
    
    var displayName: String {
        switch self {
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .replaced: return "Replaced"
        case .refined: return "Refined"
        case .moved: return "Moved"
        case .evidenced: return "Evidenced"
        case .rebutted: return "Rebutted"
        }
    }
    
    var icon: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .replaced: return "arrow.triangle.2.circlepath"
        case .refined: return "sparkles"
        case .moved: return "arrow.up.arrow.down"
        case .evidenced: return "doc.text.magnifyingglass"
        case .rebutted: return "bubble.left.and.bubble.right"
        }
    }
    
    var color: String {
        switch self {
        case .added: return "green"
        case .deleted: return "red"
        case .replaced: return "orange"
        case .refined: return "blue"
        case .moved: return "purple"
        case .evidenced: return "cyan"
        case .rebutted: return "pink"
        }
    }
}

// MARK: - Text Unit Type

enum TextUnitType: String, Codable {
    case word
    case sentence
    case paragraph
    case section
}

// MARK: - Semantic Change Record

/// A single semantic change in a document
struct SemanticChange: Identifiable, Codable, Equatable {
    let id: UUID
    let type: SemanticChangeType
    let unitType: TextUnitType
    let beforeText: String?      // Text before change (for refined/replaced/deleted)
    let afterText: String?       // Text after change (for refined/replaced/added)
    let position: Int            // Cursor position where change occurred
    let context: String          // Human-readable context (e.g., "in paragraph 3")
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
    
    /// Display text for showing in history
    var displayText: String {
        switch type {
        case .added:
            return afterText.map { "\"\($0.prefix(50))\($0.count > 50 ? "..." : "")\"" } ?? ""
        case .deleted:
            return beforeText.map { "\"\($0.prefix(50))\($0.count > 50 ? "..." : "")\"" } ?? ""
        case .replaced:
            let before = beforeText?.prefix(30) ?? ""
            let after = afterText?.prefix(30) ?? ""
            return "\"\(before)\" → \"\(after)\""
        case .refined:
            let before = beforeText?.prefix(30) ?? ""
            let after = afterText?.prefix(30) ?? ""
            return "\"\(before)\" → \"\(after)\""
        case .moved, .evidenced, .rebutted:
            return context
        }
    }
    
    /// One-line summary for the change
    var summary: String {
        let unit = unitType.rawValue
        switch type {
        case .added:
            return "Added \(unit)"
        case .deleted:
            return "Deleted \(unit)"
        case .replaced:
            return "Replaced \(unit)"
        case .refined:
            return "Refined \(unit)"
        case .moved:
            return "Moved \(unit)"
        case .evidenced:
            return "Added evidence"
        case .rebutted:
            return "Added rebuttal"
        }
    }
}

// MARK: - Pending Change Tracker

/// Tracks a change in progress (during INSERT mode)
class PendingChangeTracker {
    var change: SemanticChange?
    
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
            afterText: nil,
            position: position,
            context: context
        )
    }
    
    func completeChange(afterText: String) -> SemanticChange? {
        guard var current = change else { return nil }
        
        // Create completed change with afterText
        let completed = SemanticChange(
            type: current.type,
            unitType: current.unitType,
            beforeText: current.beforeText,
            afterText: afterText,
            position: current.position,
            context: current.context,
            timestamp: current.timestamp
        )
        
        // Clear pending
        change = nil
        
        return completed
    }
    
    func cancel() {
        change = nil
    }
    
    var hasPending: Bool {
        return change != nil
    }
}

// MARK: - Change Summary Generator

struct ChangeSummary {
    let changes: [SemanticChange]
    
    /// Generate human-readable summary like "2 refined, 1 added, 1 deleted"
    var text: String {
        var counts: [SemanticChangeType: Int] = [:]
        
        for change in changes {
            counts[change.type, default: 0] += 1
        }
        
        let parts = counts.sorted { $0.key.displayName < $1.key.displayName }
            .map { "\($0.value) \($0.key.displayName.lowercased())" }
        
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
    
    /// Breakdown by change type
    var breakdown: [(type: SemanticChangeType, count: Int)] {
        var counts: [SemanticChangeType: Int] = [:]
        
        for change in changes {
            counts[change.type, default: 0] += 1
        }
        
        return counts.map { (type: $0.key, count: $0.value) }
            .sorted { $0.type.displayName < $1.type.displayName }
    }
    
    /// Total number of changes
    var totalCount: Int {
        return changes.count
    }
}