// EditorMode.swift — Thesis
// Modal states, verb-object grammar, insert contexts

import SwiftUI

enum EditorMode: Equatable {
    case freeText
    case normal
    case insert(InsertContext)
    case visual(VisualGranularity)      // Now tracks selection granularity
    case command(String)
    case comp
    case search(String)                  // / search with query
    
    var displayName: String {
        switch self {
        case .freeText:            return "FREE TEXT"
        case .normal:              return "NORMAL"
        case .insert(let c):       return "INSERT (\(c.displayName))"
        case .visual(let g):       return "VISUAL (\(g.rawValue))"
        case .command:             return "COMMAND"
        case .comp:                return "COMPARE"
        case .search:              return "SEARCH"
        }
    }
    
    var borderColor: Color {
        switch self {
        case .freeText:  return .green
        case .normal:    return .blue
        case .insert:    return .green
        case .visual:    return .yellow
        case .command:   return .purple
        case .comp:      return .orange
        case .search:    return .cyan
        }
    }
    
    var statusColor: Color { borderColor }
    
    static func == (lhs: EditorMode, rhs: EditorMode) -> Bool {
        switch (lhs, rhs) {
        case (.freeText, .freeText), (.normal, .normal), (.comp, .comp): return true
        case (.insert(let a), .insert(let b)):   return a == b
        case (.visual(let a), .visual(let b)):   return a == b
        case (.command(let a), .command(let b)):  return a == b
        case (.search(let a), .search(let b)):   return a == b
        default: return false
        }
    }
}

// MARK: - Visual Mode Granularity

/// Controls what unit visual selection snaps to
enum VisualGranularity: String, Equatable {
    case character = "char"    // Free-form (default)
    case word      = "word"    // Snap to word boundaries
    case sentence  = "sent"    // Snap to sentence boundaries
    case paragraph = "para"    // Snap to paragraph boundaries
}

// MARK: - Insert Context

enum InsertContext: Equatable {
    case word
    case clause
    case sentence
    case paragraph
    case line
    case freeform      // No auto-exit (for 'i' insert at cursor)
    
    var displayName: String {
        switch self {
        case .word:      return "word"
        case .clause:    return "clause"
        case .sentence:  return "sentence"
        case .paragraph: return "paragraph"
        case .line:      return "line"
        case .freeform:  return "free"
        }
    }
}

// MARK: - Pending Verb

struct PendingVerb: Equatable {
    let verb: EditVerb
    let timestamp: Date
    
    init(_ verb: EditVerb) {
        self.verb = verb
        self.timestamp = Date()
    }
}

// MARK: - Edit Verb

enum EditVerb: String, Equatable {
    case delete  = "d"
    case change  = "c"
    case refine  = "r"
    case yank    = "y"
    case markup  = "m"
    case move    = "x"      // Move sentence/paragraph to a target
    
    var displayName: String {
        switch self {
        case .delete: return "DELETE"
        case .change: return "CHANGE"
        case .refine: return "REFINE"
        case .yank:   return "YANK"
        case .markup: return "MARKUP"
        case .move:   return "MOVE"
        }
    }
    
    var helpItems: [(key: String, description: String)] {
        switch self {
        case .delete:
            return [
                ("w", "delete word"),
                ("b", "delete word backward"),
                ("c", "delete clause"),
                ("s", "delete sentence"),
                ("p", "delete paragraph"),
            ]
        case .change:
            return [
                ("w", "change word"),
                ("c", "change clause"),
                ("s", "change sentence"),
                ("p", "change paragraph"),
            ]
        case .refine:
            return [
                ("w", "refine word"),
                ("c", "refine clause"),
                ("s", "refine sentence"),
                ("p", "refine paragraph"),
            ]
        case .yank:
            return [
                ("w", "yank word"),
                ("c", "yank clause"),
                ("s", "yank sentence"),
                ("p", "yank paragraph"),
            ]
        case .markup:
            return [
                ("w", "annotate word"),
                ("c", "annotate clause"),
                ("s", "annotate sentence"),
                ("p", "annotate paragraph"),
            ]
        case .move:
            return [
                ("s", "move sentence (then j/k to place, Enter to confirm)"),
                ("p", "move paragraph (then j/k to place, Enter to confirm)"),
            ]
        }
    }
}

// MARK: - Edit Object

enum EditObject: String {
    case word      = "w"
    case wordBack  = "b"
    case clause    = "c"
    case sentence  = "s"
    case paragraph = "p"
}

// MARK: - Last Command (for repeat with '.')

struct LastCommand: Equatable {
    let verb: EditVerb
    let object: EditObject?
    let insertedText: String?
    
    static func == (lhs: LastCommand, rhs: LastCommand) -> Bool {
        lhs.verb == rhs.verb && lhs.object == rhs.object
    }
}

// MARK: - Argument Structure Type

enum ArgumentType: String, Equatable {
    case evidence       = "e"   // ie: Insert evidence after claim
    case counterargument = "c"  // ic: Insert counterargument
    case rebuttal       = "r"   // ir: Insert rebuttal to counter
    case bridge         = "b"   // ab: Add bridge between paragraphs
    case transition     = "t"   // at: Add transition sentence
    
    var displayName: String {
        switch self {
        case .evidence:        return "Evidence"
        case .counterargument: return "Counterargument"
        case .rebuttal:        return "Rebuttal"
        case .bridge:          return "Bridge"
        case .transition:      return "Transition"
        }
    }
    
    /// Prefix text to insert before the user starts typing
    var promptPrefix: String {
        switch self {
        case .evidence:        return "For example, "
        case .counterargument: return "However, "
        case .rebuttal:        return "Nevertheless, "
        case .bridge:          return ""
        case .transition:      return ""
        }
    }
    
    /// Semantic context string for version history
    var context: String {
        switch self {
        case .evidence:        return "evidence"
        case .counterargument: return "counterargument"
        case .rebuttal:        return "rebuttal"
        case .bridge:          return "bridge"
        case .transition:      return "transition"
        }
    }
    
    static var helpItems: [(key: String, description: String)] {
        [
            ("e", "insert evidence after claim"),
            ("c", "insert counterargument"),
            ("r", "insert rebuttal to counter"),
            ("b", "add bridge between paragraphs"),
            ("t", "add transition sentence"),
        ]
    }
}
