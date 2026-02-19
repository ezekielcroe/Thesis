// Annotation.swift — Thesis
// Positional annotations with categories, fuzzy anchor tracking, and navigation

import Foundation

// MARK: - Annotation Category

enum AnnotationCategory: String, Codable, CaseIterable, Equatable {
    case note       = "note"
    case todo       = "todo"
    case question   = "question"
    case research   = "research"
    case fix        = "fix"
    case idea       = "idea"
    
    var displayName: String {
        switch self {
        case .note:     return "Note"
        case .todo:     return "To Do"
        case .question: return "Question"
        case .research: return "Research"
        case .fix:      return "Fix"
        case .idea:     return "Idea"
        }
    }
    
    var icon: String {
        switch self {
        case .note:     return "note.text"
        case .todo:     return "checkmark.circle"
        case .question: return "questionmark.circle"
        case .research: return "magnifyingglass"
        case .fix:      return "wrench"
        case .idea:     return "lightbulb"
        }
    }
    
    var color: String {
        switch self {
        case .note:     return "purple"
        case .todo:     return "orange"
        case .question: return "blue"
        case .research: return "green"
        case .fix:      return "red"
        case .idea:     return "yellow"
        }
    }
}

// MARK: - Annotation

struct Annotation: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var anchorText: String
    var anchorPosition: Int
    var category: AnnotationCategory
    var resolved: Bool
    let createdAt: Date
    var updatedAt: Date
    
    init(
        text: String,
        anchorText: String,
        anchorPosition: Int,
        category: AnnotationCategory = .note
    ) {
        self.id = UUID()
        self.text = text
        self.anchorText = anchorText
        self.anchorPosition = anchorPosition
        self.category = category
        self.resolved = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Find the current range of this annotation's anchor text in the document.
    /// Uses progressive search: exact near original position → exact full doc → fuzzy.
    func currentRange(in content: String) -> NSRange? {
        let nsContent = content as NSString
        guard nsContent.length > 0, !anchorText.isEmpty else { return nil }
        
        // 1. Exact match near original position (fast path)
        let searchRadius = 500
        let searchStart = max(0, anchorPosition - searchRadius)
        let searchEnd = min(nsContent.length, anchorPosition + anchorText.count + searchRadius)
        if searchEnd > searchStart {
            let localRange = NSRange(location: searchStart, length: searchEnd - searchStart)
            let found = nsContent.range(of: anchorText, options: [], range: localRange)
            if found.location != NSNotFound { return found }
        }
        
        // 2. Exact match anywhere in document
        let fullRange = nsContent.range(of: anchorText)
        if fullRange.location != NSNotFound { return fullRange }
        
        // 3. Fuzzy match: try with first 30 characters (handles partial edits to anchor text)
        if anchorText.count > 30 {
            let prefix = String(anchorText.prefix(30))
            let prefixRange = nsContent.range(of: prefix)
            if prefixRange.location != NSNotFound {
                // Extend to a reasonable length
                let endPos = min(prefixRange.location + anchorText.count + 20, nsContent.length)
                return NSRange(location: prefixRange.location, length: endPos - prefixRange.location)
            }
        }
        
        // 4. Case-insensitive match
        let ciRange = nsContent.range(of: anchorText, options: .caseInsensitive)
        if ciRange.location != NSNotFound { return ciRange }
        
        return nil
    }
    
    /// Update the anchor position to match current document state
    mutating func updateAnchorPosition(in content: String) {
        if let range = currentRange(in: content) {
            anchorPosition = range.location
        }
    }
    
    var displayTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    var isStale: Bool {
        // An annotation is stale if created more than 30 days ago and unresolved
        !resolved && createdAt.timeIntervalSinceNow < -2_592_000
    }
}
