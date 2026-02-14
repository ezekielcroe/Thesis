import Foundation

// MARK: - Enhanced DiffChange with Semantic Types

struct DiffChange: Identifiable {
    let id = UUID()
    let type: ChangeType
    let semanticType: SemanticChangeType?  // ENHANCED: Track why the change happened
    let range: NSRange
    let text: String
    let displayRange: NSRange?
    
    // NEW: Stores the previous version for phantom display
    let oldText: String?
    
    enum ChangeType {
        case addition
        case deletion
        case unchanged
    }
    
    init(type: ChangeType, range: NSRange, text: String, displayRange: NSRange? = nil, semanticType: SemanticChangeType? = nil, oldText: String? = nil) {
        self.type = type
        self.range = range
        self.text = text
        self.displayRange = displayRange
        self.semanticType = semanticType
        self.oldText = oldText
    }
}

class DiffGenerator {
    
    /// Generate a diff with semantic type information and phantom text support
    /// - Parameters:
    ///   - oldText: Previous version content
    ///   - newText: Current version content
    ///   - changes: Semantic changes that occurred (optional, for richer diffs)
    /// - Returns: Array of diff changes with semantic types
    static func generateDiff(from oldText: String, to newText: String, withChanges changes: [SemanticChange] = []) -> [DiffChange] {
        var diffChanges: [DiffChange] = []
        
        let oldSentences = TextAnalyzer.getSentences(in: oldText)
        let newSentences = TextAnalyzer.getSentences(in: newText)
        
        // Create maps for quick lookup
        let oldSentenceSet = Set(oldSentences.map { $0.text })
        let newSentenceSet = Set(newSentences.map { $0.text })
        
        // REFACTOR: Map to the full SemanticChange object, not just the type
        // This allows us to retrieve 'beforeText' (oldText) for inline display
        var semanticMap: [String: SemanticChange] = [:]
        for change in changes {
            if let afterText = change.afterText {
                semanticMap[afterText] = change
            }
        }
        
        // Track positions in new text
        var currentLocation = 0
        
        // Process new sentences - mark additions and unchanged
        for newSentence in newSentences {
            let text = newSentence.text
            let range = NSRange(location: currentLocation, length: text.count)
            
            if oldSentenceSet.contains(text) {
                // Unchanged sentence
                diffChanges.append(DiffChange(
                    type: .unchanged,
                    range: range,
                    text: text
                ))
            } else {
                // Added or refined sentence - check semantic type
                let changeRecord = semanticMap[text]
                let semanticType = changeRecord?.type ?? .added
                let previousVersion = changeRecord?.beforeText // Capture the old text
                
                diffChanges.append(DiffChange(
                    type: .addition,
                    range: range,
                    text: text,
                    displayRange: nil,
                    semanticType: semanticType,
                    oldText: previousVersion // Store it
                ))
            }
            
            currentLocation += text.count
        }
        
        // Find deletions
        for (index, oldSentence) in oldSentences.enumerated() {
            if !newSentenceSet.contains(oldSentence.text) {
                // Find where this deletion should be indicated in the new text
                var displayLocation = 0
                
                // Find a nearby sentence that exists in both to anchor the deletion indicator
                for i in (0..<index).reversed() {
                    if newSentenceSet.contains(oldSentences[i].text) {
                        // Find this sentence in new text
                        if let match = newSentences.first(where: { $0.text == oldSentences[i].text }) {
                            displayLocation = match.range.location + match.range.length
                            break
                        }
                    }
                }
                
                // Check if this was a refined sentence (deleted old, added new)
                let semanticType = findSemanticTypeForDeletion(oldSentence.text, in: changes)
                
                diffChanges.append(DiffChange(
                    type: .deletion,
                    range: oldSentence.range,
                    text: oldSentence.text,
                    displayRange: NSRange(location: displayLocation, length: 0),
                    semanticType: semanticType,
                    oldText: nil
                ))
            }
        }
        
        // Sort by display position
        diffChanges.sort { lhs, rhs in
            let lhsLoc = lhs.type == .deletion ? (lhs.displayRange?.location ?? 0) : lhs.range.location
            let rhsLoc = rhs.type == .deletion ? (rhs.displayRange?.location ?? 0) : rhs.range.location
            return lhsLoc < rhsLoc
        }
        
        return diffChanges
    }
    
    /// Find the semantic type for a deleted sentence
    private static func findSemanticTypeForDeletion(_ deletedText: String, in changes: [SemanticChange]) -> SemanticChangeType? {
        // Look for a change that deleted this text
        for change in changes {
            if change.beforeText == deletedText {
                return change.type
            }
        }
        return .deleted  // Default to simple deletion
    }
    
    static func getChangeIndices(in diff: [DiffChange]) -> [Int] {
        return diff.enumerated()
            .filter { $0.element.type != .unchanged }
            .map { $0.offset }
    }
    
    static func findNextChange(from currentIndex: Int, in diff: [DiffChange]) -> Int? {
        let changeIndices = getChangeIndices(in: diff)
        return changeIndices.first { $0 > currentIndex }
    }
    
    static func findPreviousChange(from currentIndex: Int, in diff: [DiffChange]) -> Int? {
        let changeIndices = getChangeIndices(in: diff)
        return changeIndices.last { $0 < currentIndex }
    }
    
    // MARK: - Statistics
    
    /// Get statistics about the diff
    static func statistics(for diff: [DiffChange]) -> DiffStatistics {
        var added = 0
        var deleted = 0
        var refined = 0
        var replaced = 0
        
        for change in diff {
            switch change.type {
            case .addition:
                if change.semanticType == .refined {
                    refined += 1
                } else if change.semanticType == .replaced {
                    replaced += 1
                } else {
                    added += 1
                }
            case .deletion:
                if change.semanticType == .refined || change.semanticType == .replaced {
                    // Don't double-count refinements/replacements
                } else {
                    deleted += 1
                }
            case .unchanged:
                break
            }
        }
        
        return DiffStatistics(
            added: added,
            deleted: deleted,
            refined: refined,
            replaced: replaced,
            totalChanges: added + deleted + refined + replaced
        )
    }
}

// MARK: - Diff Statistics

struct DiffStatistics {
    let added: Int
    let deleted: Int
    let refined: Int
    let replaced: Int
    let totalChanges: Int
    
    var summary: String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if deleted > 0 { parts.append("\(deleted) deleted") }
        if refined > 0 { parts.append("\(refined) refined") }
        if replaced > 0 { parts.append("\(replaced) replaced") }
        
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}
