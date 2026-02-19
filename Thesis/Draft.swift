// Draft.swift — Thesis
// Version snapshots (commits) and branch management

import Foundation

// MARK: - Draft (a committed snapshot)

struct Draft: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let content: String
    let timestamp: Date
    let comment: String
    let parentId: UUID?
    let secondParentId: UUID?    // Non-nil for merge commits
    let branchName: String
    let isFirstDraft: Bool
    let changes: [SemanticChange]
    
    init(
        name: String,
        content: String,
        comment: String = "",
        parentId: UUID? = nil,
        secondParentId: UUID? = nil,
        branchName: String = "main",
        isFirstDraft: Bool = false,
        changes: [SemanticChange] = []
    ) {
        self.id = UUID()
        self.name = name
        self.content = content
        self.timestamp = Date()
        self.comment = comment
        self.parentId = parentId
        self.secondParentId = secondParentId
        self.branchName = branchName
        self.isFirstDraft = isFirstDraft
        self.changes = changes
    }
    
    var displayTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var displayName: String {
        if isFirstDraft { return "First Draft: \(name)" }
        if isMergeCommit { return "Merge: \(name)" }
        return name
    }
    
    var isMergeCommit: Bool { secondParentId != nil }
    
    var changeSummary: String {
        guard !changes.isEmpty else {
            return isFirstDraft ? "Initial capture" : "No changes"
        }
        return ChangeSummary(changes: changes).text
    }
    
    var changeCount: Int { changes.count }
    
    var darlings: [String] {
        changes.compactMap { $0.lostText }.filter { !$0.isEmpty }
    }
}

// MARK: - Branch

struct Branch: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var headDraftId: UUID
    let createdAt: Date
    let branchPoint: UUID        // Draft where this branch diverged
    var description: String
    
    init(name: String, headDraftId: UUID, branchPoint: UUID, description: String = "") {
        self.id = UUID()
        self.name = name
        self.headDraftId = headDraftId
        self.createdAt = Date()
        self.branchPoint = branchPoint
        self.description = description
    }
}

// MARK: - Working Draft

struct WorkingDraft: Codable {
    var content: String
    var lastSaved: Date
    var pendingChanges: [SemanticChange]
    
    init(content: String, pendingChanges: [SemanticChange] = []) {
        self.content = content
        self.lastSaved = Date()
        self.pendingChanges = pendingChanges
    }
}

// MARK: - Merge Conflict

struct MergeConflict: Identifiable {
    let id = UUID()
    let position: Int
    let ourText: String
    let theirText: String
    let commonAncestorText: String?
    var resolution: MergeResolution = .unresolved
}

enum MergeResolution: Equatable {
    case unresolved
    case keepOurs
    case keepTheirs
    case combined(String)
}

// MARK: - Merge Result

struct MergeResult {
    let mergedContent: String
    let conflicts: [MergeConflict]
    let hasUnresolvedConflicts: Bool
    
    var isClean: Bool { conflicts.isEmpty }
}
