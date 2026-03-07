// Annotation.swift — Thesis
// Positional annotations with fuzzy anchor tracking and navigation

import Foundation

// MARK: - Annotation

struct Annotation: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var anchorText: String
    var anchorPosition: Int
    var resolved: Bool
    let createdAt: Date
    var updatedAt: Date
    
    // CodingKeys includes legacy "category" so old data doesn't crash
    enum CodingKeys: String, CodingKey {
        case id, text, anchorText, anchorPosition, resolved, createdAt, updatedAt, category
    }
    
    init(
        text: String,
        anchorText: String,
        anchorPosition: Int
    ) {
        self.id = UUID()
        self.text = text
        self.anchorText = anchorText
        self.anchorPosition = anchorPosition
        self.resolved = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        anchorText = try container.decode(String.self, forKey: .anchorText)
        anchorPosition = try container.decode(Int.self, forKey: .anchorPosition)
        resolved = try container.decode(Bool.self, forKey: .resolved)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // Old "category" field is silently ignored
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(anchorText, forKey: .anchorText)
        try container.encode(anchorPosition, forKey: .anchorPosition)
        try container.encode(resolved, forKey: .resolved)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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
        
        // 3. Fuzzy match: try with first 30 characters
        if anchorText.count > 30 {
            let prefix = String(anchorText.prefix(30))
            let prefixRange = nsContent.range(of: prefix)
            if prefixRange.location != NSNotFound {
                let endPos = min(prefixRange.location + anchorText.count + 20, nsContent.length)
                return NSRange(location: prefixRange.location, length: endPos - prefixRange.location)
            }
        }
        
        // 4. Case-insensitive match
        let ciRange = nsContent.range(of: anchorText, options: .caseInsensitive)
        if ciRange.location != NSNotFound { return ciRange }
        
        return nil
    }
    
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
        !resolved && createdAt.timeIntervalSinceNow < -2_592_000
    }
}
