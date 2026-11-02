//
//  NoteCategory.swift
//  Thesis
//
//  Created by Zhi Zheng Yeo on 2/11/26.
//


// Note.swift — Thesis
// Notes attached to a span of text. The span is kept up to date on every edit
// (typing, commands, undo), so notes stay attached to the words they describe.

import Foundation

enum NoteCategory: String, Codable, CaseIterable, Identifiable {
    case note, question, todo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .note: return "Note"
        case .question: return "Question"
        case .todo: return "To do"
        }
    }

    var icon: String {
        switch self {
        case .note: return "note.text"
        case .question: return "questionmark.circle"
        case .todo: return "checkmark.circle"
        }
    }

    /// Maps the six categories of earlier versions onto the current three.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "question", "research": self = .question
        case "todo", "fix": self = .todo
        default: self = .note
        }
    }
}

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var category: NoteCategory
    var resolved: Bool
    /// Current UTF-16 span of the annotated text.
    var location: Int
    var length: Int
    /// The annotated text when the note was made (shown if that text is later deleted).
    let anchorText: String
    let createdAt: Date
    var updatedAt: Date
    /// Set when decoded from an older format, whose positions need re-finding. Not saved.
    var needsReanchor = false

    var range: NSRange {
        get { NSRange(location: location, length: length) }
        set { location = newValue.location; length = newValue.length }
    }

    /// The annotated text has been deleted; the note is kept but no longer points anywhere.
    var isDetached: Bool { length == 0 }

    init(text: String, category: NoteCategory, range: NSRange, anchorText: String) {
        self.id = UUID()
        self.text = text
        self.category = category
        self.resolved = false
        self.location = range.location
        self.length = range.length
        self.anchorText = anchorText
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, category, resolved, location, length, anchorText, createdAt, updatedAt
        case anchorPosition   // earlier versions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        category = try c.decodeIfPresent(NoteCategory.self, forKey: .category) ?? .note
        resolved = try c.decodeIfPresent(Bool.self, forKey: .resolved) ?? false
        anchorText = try c.decodeIfPresent(String.self, forKey: .anchorText) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        if let storedLocation = try c.decodeIfPresent(Int.self, forKey: .location) {
            location = storedLocation
            length = try c.decodeIfPresent(Int.self, forKey: .length) ?? 0
        } else {
            location = try c.decodeIfPresent(Int.self, forKey: .anchorPosition) ?? 0
            length = anchorText.utf16Length
            needsReanchor = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(category, forKey: .category)
        try c.encode(resolved, forKey: .resolved)
        try c.encode(location, forKey: .location)
        try c.encode(length, forKey: .length)
        try c.encode(anchorText, forKey: .anchorText)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

enum NoteAnchor {
    /// Where a span ends up after the text in `editLocation ..< editLocation + removed`
    /// is replaced by `inserted` characters.
    /// - Edits entirely before the span shift it; edits entirely after leave it alone.
    /// - Typing exactly at the span's start or end does not join the span.
    /// - Typing inside the span grows it; deleting all of it leaves length 0 (detached).
    static func adjust(_ range: NSRange, editLocation: Int, removed: Int, inserted: Int) -> NSRange {
        let editEnd = editLocation + removed
        let delta = inserted - removed
        func mapStart(_ p: Int) -> Int {
            if p < editLocation { return p }
            if p >= editEnd { return p + delta }
            return editLocation
        }
        func mapEnd(_ p: Int) -> Int {
            if p <= editLocation { return p }
            if p >= editEnd { return p + delta }
            return editLocation + inserted
        }
        let start = mapStart(range.location)
        let end = mapEnd(NSMaxRange(range))
        return NSRange(location: max(0, start), length: max(0, end - start))
    }

    /// The occurrence of `anchor` closest to `position`.
    static func find(_ anchor: String, in text: NSString, near position: Int) -> NSRange? {
        guard !anchor.isEmpty, text.length > 0 else { return nil }
        var best: NSRange?
        var searchStart = 0
        while searchStart < text.length {
            let found = text.range(of: anchor, options: [],
                                   range: NSRange(location: searchStart, length: text.length - searchStart))
            if found.location == NSNotFound { break }
            if let current = best, abs(current.location - position) <= abs(found.location - position) {
                // keep current
            } else {
                best = found
            }
            searchStart = found.location + max(found.length, 1)
        }
        return best
    }
}
