import SwiftUI

enum EditorMode: Equatable {
    case freeText        // Initial writing mode - full freedom
    case edit            // Navigation and commands
    case insert(InsertContext)  // Constrained insertion
    case command(String) // Command entry (:comp, :print)
    case comp            // Compare/diff view
    
    var displayName: String {
        switch self {
        case .freeText: return "FREE TEXT"
        case .edit: return "EDIT"
        case .insert: return "INSERT"
        case .command: return "COMMAND"
        case .comp: return "COMPARE"
        }
    }
    
    var borderColor: Color {
        switch self {
        case .freeText: return .green
        case .edit: return .blue
        case .insert: return .green
        case .command: return .purple
        case .comp: return .orange
        }
    }
    
    static func == (lhs: EditorMode, rhs: EditorMode) -> Bool {
        switch (lhs, rhs) {
        case (.freeText, .freeText): return true
        case (.edit, .edit): return true
        case (.insert, .insert): return true
        case (.command, .command): return true
        case (.comp, .comp): return true
        default: return false
        }
    }
}

// MARK: - Insert Context

enum InsertContext {
    case word           // Exit on: space
    case sentence       // Exit on: . ! ?
    case paragraph      // Exit on: double newline
    
    var exitTriggers: [String] {
        switch self {
        case .word: return [" "]
        case .sentence: return [".", "!", "?"]
        case .paragraph: return ["\n\n"]
        }
    }
}
