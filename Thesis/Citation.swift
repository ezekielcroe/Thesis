// Citation.swift — Thesis
// Lightweight inline citation system: [Key] markers with free-text source details

import Foundation

struct Citation: Identifiable, Codable, Equatable {
    let id: UUID
    var key: String              // e.g. "Miller2024" — appears as [Miller2024] in text
    var source: String           // Free-text: "Miller, J. (2024). On Thought. p.42"
    var anchorText: String       // The text being cited (for context in sidebar)
    let createdAt: Date
    var updatedAt: Date
    
    init(key: String, source: String, anchorText: String) {
        self.id = UUID()
        self.key = key
        self.source = source
        self.anchorText = anchorText
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// The inline marker string as it appears in the document
    var marker: String { "[\(key)]" }
    
    /// Find the marker's current range in the document, if it still exists
    func markerRange(in content: String) -> NSRange? {
        let nsContent = content as NSString
        let range = nsContent.range(of: marker)
        return range.location != NSNotFound ? range : nil
    }
    
    /// Whether the marker is missing from the document (user deleted it manually)
    func isOrphaned(in content: String) -> Bool {
        markerRange(in: content) == nil
    }
    
    var displayTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}
