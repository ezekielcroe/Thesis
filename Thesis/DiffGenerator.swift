import Foundation

struct DiffChange: Identifiable {
    let id = UUID()
    let type: ChangeType
    let range: NSRange
    let text: String
    
    enum ChangeType {
        case addition
        case deletion
        case unchanged
    }
}

class DiffGenerator {
    
    static func generateDiff(from oldText: String, to newText: String) -> [DiffChange] {
        var changes: [DiffChange] = []
        
        // Simple line-by-line diff for MVP
        let oldSentences = TextAnalyzer.getSentences(in: oldText)
        let newSentences = TextAnalyzer.getSentences(in: newText)
        
        // Create a map of sentence text to track changes
        let oldSentenceSet = Set(oldSentences.map { $0.text })
        let newSentenceSet = Set(newSentences.map { $0.text })
        
        var currentLocation = 0
        
        // Process new sentences
        for newSentence in newSentences {
            let text = newSentence.text
            
            if oldSentenceSet.contains(text) {
                // Unchanged
                changes.append(DiffChange(
                    type: .unchanged,
                    range: NSRange(location: currentLocation, length: text.count),
                    text: text
                ))
            } else {
                // Addition
                changes.append(DiffChange(
                    type: .addition,
                    range: NSRange(location: currentLocation, length: text.count),
                    text: text
                ))
            }
            
            currentLocation += text.count
        }
        
        // Find deletions (in old but not in new)
        for oldSentence in oldSentences {
            if !newSentenceSet.contains(oldSentence.text) {
                changes.append(DiffChange(
                    type: .deletion,
                    range: oldSentence.range,
                    text: oldSentence.text
                ))
            }
        }
        
        // Sort by location
        changes.sort { $0.range.location < $1.range.location }
        
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
