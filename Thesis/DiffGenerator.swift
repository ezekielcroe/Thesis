import Foundation

struct DiffChange: Identifiable {
    let id = UUID()
    let type: ChangeType
    let range: NSRange      // Range in the NEW text (for additions/unchanged) or OLD text (for deletions)
    let text: String
    let displayRange: NSRange?  // Where to show indicator in current buffer (for deletions)
    
    enum ChangeType {
        case addition
        case deletion
        case unchanged
    }
    
    init(type: ChangeType, range: NSRange, text: String, displayRange: NSRange? = nil) {
        self.type = type
        self.range = range
        self.text = text
        self.displayRange = displayRange
    }
}

class DiffGenerator {
    
    /// Generate a diff that can be visualized in the current (new) text buffer
    /// - Additions: highlighted in green at their position in new text
    /// - Deletions: marked with red indicator at the position where they were removed
    static func generateDiff(from oldText: String, to newText: String) -> [DiffChange] {
        var changes: [DiffChange] = []
        
        let oldSentences = TextAnalyzer.getSentences(in: oldText)
        let newSentences = TextAnalyzer.getSentences(in: newText)
        
        // Create maps for quick lookup
        let oldSentenceSet = Set(oldSentences.map { $0.text })
        let newSentenceSet = Set(newSentences.map { $0.text })
        
        // Track positions in new text
        var currentLocation = 0
        
        // Process new sentences - mark additions and unchanged
        for newSentence in newSentences {
            let text = newSentence.text
            let range = NSRange(location: currentLocation, length: text.count)
            
            if oldSentenceSet.contains(text) {
                changes.append(DiffChange(
                    type: .unchanged,
                    range: range,
                    text: text
                ))
            } else {
                changes.append(DiffChange(
                    type: .addition,
                    range: range,
                    text: text
                ))
            }
            
            currentLocation += text.count
        }
        
        // Find deletions and calculate where they should be indicated
        // We'll show deletion markers at the position of the nearest remaining sentence
        for (index, oldSentence) in oldSentences.enumerated() {
            if !newSentenceSet.contains(oldSentence.text) {
                // Find where this deletion should be indicated in the new text
                // Look for the next sentence that still exists
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
                
                changes.append(DiffChange(
                    type: .deletion,
                    range: oldSentence.range,  // Original range in old text
                    text: oldSentence.text,
                    displayRange: NSRange(location: displayLocation, length: 0)  // Where to show in new text
                ))
            }
        }
        
        // Sort by display position (use range.location for additions, displayRange for deletions)
        changes.sort { lhs, rhs in
            let lhsLoc = lhs.type == .deletion ? (lhs.displayRange?.location ?? 0) : lhs.range.location
            let rhsLoc = rhs.type == .deletion ? (rhs.displayRange?.location ?? 0) : rhs.range.location
            return lhsLoc < rhsLoc
        }
        
        return changes
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
}
