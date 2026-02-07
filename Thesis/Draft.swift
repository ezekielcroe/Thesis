import Foundation

struct Draft: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let content: String
    let timestamp: Date
    let comment: String
    let parentId: UUID?
    let isFirstDraft: Bool
    
    // ENHANCED: Semantic change tracking
    let changes: [SemanticChange]
    
    init(
        name: String,
        content: String,
        comment: String = "",
        parentId: UUID? = nil,
        isFirstDraft: Bool = false,
        changes: [SemanticChange] = []
    ) {
        self.id = UUID()
        self.name = name
        self.content = content
        self.timestamp = Date()
        self.comment = comment
        self.parentId = parentId
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
        if isFirstDraft {
            return "First Draft: \(name)"
        }
        return name
    }
    
    // ENHANCED: Change summary
    var changeSummary: String {
        guard !changes.isEmpty else {
            return isFirstDraft ? "Initial capture" : "No changes"
        }
        
        return ChangeSummary(changes: changes).text
    }
    
    // Breakdown of changes by type
    var changeBreakdown: [(type: SemanticChangeType, count: Int)] {
        return ChangeSummary(changes: changes).breakdown
    }
    
    // Total number of semantic changes
    var changeCount: Int {
        return changes.count
    }
}

// Working draft that auto-saves but isn't committed
struct WorkingDraft: Codable {
    var content: String
    var lastSaved: Date
    var pendingChanges: [SemanticChange]  // ENHANCED: Track changes in progress
    
    init(content: String, pendingChanges: [SemanticChange] = []) {
        self.content = content
        self.lastSaved = Date()
        self.pendingChanges = pendingChanges
    }
}
