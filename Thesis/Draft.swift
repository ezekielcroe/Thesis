import Foundation

struct Draft: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let content: String
    let timestamp: Date
    let comment: String
    let parentId: UUID?
    let isFirstDraft: Bool
    
    init(name: String, content: String, comment: String = "", parentId: UUID? = nil, isFirstDraft: Bool = false) {
        self.id = UUID()
        self.name = name
        self.content = content
        self.timestamp = Date()
        self.comment = comment
        self.parentId = parentId
        self.isFirstDraft = isFirstDraft
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
}

// Working draft that auto-saves but isn't committed
struct WorkingDraft: Codable {
    var content: String
    var lastSaved: Date
    
    init(content: String) {
        self.content = content
        self.lastSaved = Date()
    }
}
