// DiffGenerator.swift — Thesis
// Sentence-level semantic diff with LCS matching, move detection, word-level sub-diffs

import Foundation

// MARK: - DiffChange

struct DiffChange: Identifiable {
    let id = UUID()
    let type: ChangeType
    let semanticType: SemanticChangeType?
    let range: NSRange
    let text: String
    let displayRange: NSRange?
    let oldText: String?
    let wordDiffs: [WordDiff]?
    
    enum ChangeType {
        case addition
        case deletion
        case unchanged
        case moved
    }
    
    init(
        type: ChangeType,
        range: NSRange,
        text: String,
        displayRange: NSRange? = nil,
        semanticType: SemanticChangeType? = nil,
        oldText: String? = nil,
        wordDiffs: [WordDiff]? = nil
    ) {
        self.type = type
        self.range = range
        self.text = text
        self.displayRange = displayRange
        self.semanticType = semanticType
        self.oldText = oldText
        self.wordDiffs = wordDiffs
    }
}

// MARK: - Word-Level Diff

struct WordDiff: Identifiable {
    let id = UUID()
    let type: DiffChange.ChangeType
    let text: String
}

// MARK: - Diff Statistics

struct EditorDiffInfo {
    let currentIndex: Int
    let totalChanges: Int
    let currentChange: DiffChange?
}

struct DiffStatistics {
    let added: Int
    let deleted: Int
    let replaced: Int
    let moved: Int
    let totalChanges: Int
    
    var summary: String {
        var parts: [String] = []
        if added > 0    { parts.append("+\(added) added") }
        if deleted > 0  { parts.append("-\(deleted) deleted") }
        if replaced > 0 { parts.append("⇄\(replaced) replaced") }
        if moved > 0    { parts.append("↕\(moved) moved") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}

// MARK: - DiffGenerator

class DiffGenerator {
    
    /// Generate a sentence-level diff using LCS matching with semantic enrichment
    static func generateDiff(
        from oldText: String,
        to newText: String,
        withChanges changes: [SemanticChange] = []
    ) -> [DiffChange] {
        let oldSentences = TextAnalyzer.getSentences(in: oldText)
        let newSentences = TextAnalyzer.getSentences(in: newText)
        
        let normalize: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        let oldNorm = oldSentences.map { normalize($0.text) }
        let newNorm = newSentences.map { normalize($0.text) }
        
        var semanticMap: [String: SemanticChange] = [:]
        for change in changes {
            if let afterText = change.afterText {
                semanticMap[normalize(afterText)] = change
            }
        }
        
        // Grab the precise mapping map alongside the sets
        let lcs = longestCommonSubsequence(oldNorm, newNorm)
        
        let oldNormSet = NSCountedSet(array: oldNorm)
        let newNormSet = NSCountedSet(array: newNorm)
        
        var movedSentences = Set<String>()
        for (index, sentence) in oldNorm.enumerated() {
            if newNormSet.contains(sentence) && !lcs.oldIndices.contains(index) {
                movedSentences.insert(sentence)
            }
        }
        
        var diffChanges: [DiffChange] = []
        
        for (i, newSentence) in newSentences.enumerated() {
            let norm = newNorm[i]
            let range = newSentence.range
            
            // FIX 1: Removed the fallback. If it's not strictly unchanged or moved, it's an addition.
            if lcs.newIndices.contains(i) {
                diffChanges.append(DiffChange(type: .unchanged, range: range, text: newSentence.text))
            } else if movedSentences.contains(norm) {
                diffChanges.append(DiffChange(
                    type: .moved, range: range, text: newSentence.text,
                    semanticType: .moved
                ))
            } else {
                let changeRecord = semanticMap[norm]
                let semanticType = changeRecord?.type ?? .added
                let previousVersion = changeRecord?.beforeText
                
                var wordDiffs: [WordDiff]? = nil
                if let oldVersion = previousVersion, !oldVersion.isEmpty {
                    wordDiffs = generateWordDiff(from: oldVersion, to: newSentence.text)
                }
                
                diffChanges.append(DiffChange(
                    type: .addition, range: range, text: newSentence.text,
                    semanticType: semanticType, oldText: previousVersion,
                    wordDiffs: wordDiffs
                ))
            }
        }
        
        for (index, oldSentence) in oldSentences.enumerated() {
            let norm = oldNorm[index]
            guard !newNormSet.contains(norm) else { continue }
            
            // FIX 2: Use exact LCS mapping to find the anchor position for deletions
            var displayLocation = 0
            for i in (0..<index).reversed() {
                if let newIndex = lcs.oldToNewMap[i] {
                    let match = newSentences[newIndex]
                    displayLocation = match.range.location + match.range.length
                    break
                }
            }
            
            let semanticType = findSemanticTypeForDeletion(norm, in: changes)
            
            diffChanges.append(DiffChange(
                type: .deletion, range: oldSentence.range, text: oldSentence.text,
                displayRange: NSRange(location: displayLocation, length: 0),
                semanticType: semanticType
            ))
        }
        
        diffChanges.sort { lhs, rhs in
            let lhsLoc = lhs.type == .deletion ? (lhs.displayRange?.location ?? 0) : lhs.range.location
            let rhsLoc = rhs.type == .deletion ? (rhs.displayRange?.location ?? 0) : rhs.range.location
            if lhsLoc == rhsLoc {
                if lhs.type == .deletion && rhs.type != .deletion { return true }
                if lhs.type != .deletion && rhs.type == .deletion { return false }
            }
            return lhsLoc < rhsLoc
        }
        
        return diffChanges
    }
    
    // MARK: - LCS (Longest Common Subsequence)
    
    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> (oldIndices: Set<Int>, newIndices: Set<Int>, oldToNewMap: [Int: Int]) {
        let m = a.count, n = b.count
        guard m > 0 && n > 0 else { return ([], [], [:]) }
        
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if a[i-1] == b[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }
        
        var oldIndices = Set<Int>()
        var newIndices = Set<Int>()
        var oldToNewMap = [Int: Int]()
        
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i-1] == b[j-1] {
                oldIndices.insert(i-1)
                newIndices.insert(j-1)
                oldToNewMap[i-1] = j-1
                i -= 1; j -= 1
            } else if dp[i-1][j] > dp[i][j-1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return (oldIndices, newIndices, oldToNewMap)
    }
    
    // MARK: - Word-Level Sub-Diff
    
    static func generateWordDiff(from oldText: String, to newText: String) -> [WordDiff] {
        let oldWords = oldText.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let newWords = newText.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        
        let m = oldWords.count, n = newWords.count
        guard m > 0 || n > 0 else { return [] }
        
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(1, m) {
            for j in 1...max(1, n) {
                if i <= m && j <= n && oldWords[i-1] == newWords[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(i > 0 ? dp[i-1][j] : 0, j > 0 ? dp[i][j-1] : 0)
                }
            }
        }
        
        var i = m, j = n
        var stack: [WordDiff] = []
        
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldWords[i-1] == newWords[j-1] {
                stack.append(WordDiff(type: .unchanged, text: newWords[j-1]))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                stack.append(WordDiff(type: .addition, text: newWords[j-1]))
                j -= 1
            } else if i > 0 {
                stack.append(WordDiff(type: .deletion, text: oldWords[i-1]))
                i -= 1
            }
        }
        
        return stack.reversed()
    }
    
    // MARK: - Helpers
    
    private static func findSemanticTypeForDeletion(
        _ deletedText: String,
        in changes: [SemanticChange]
    ) -> SemanticChangeType? {
        let normalize: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for change in changes {
            if let before = change.beforeText, normalize(before) == deletedText {
                return change.type
            }
        }
        return .deleted
    }
    
    static func getChangeIndices(in diff: [DiffChange]) -> [Int] {
        diff.enumerated()
            .filter { $0.element.type != .unchanged }
            .map { $0.offset }
    }
    
    static func findNextChange(from currentIndex: Int, in diff: [DiffChange]) -> Int? {
        getChangeIndices(in: diff).first { $0 > currentIndex }
    }
    
    static func findPreviousChange(from currentIndex: Int, in diff: [DiffChange]) -> Int? {
        getChangeIndices(in: diff).last { $0 < currentIndex }
    }
    
    static func statistics(for diff: [DiffChange]) -> DiffStatistics {
        var added = 0, deleted = 0, replaced = 0, moved = 0
        for change in diff {
            switch change.type {
            case .addition:
                switch change.semanticType {
                case .replaced: replaced += 1
                default:        added += 1
                }
            case .deletion:
                if change.semanticType != .replaced {
                    deleted += 1
                }
            case .moved: moved += 1
            case .unchanged: break
            }
        }
        return DiffStatistics(
            added: added, deleted: deleted,
            replaced: replaced, moved: moved,
            totalChanges: added + deleted + replaced + moved
        )
    }
    
    // MARK: - Three-Way Merge

    static func threeWayMerge(
        ancestor: String,
        ours: String,
        theirs: String
    ) -> MergeResult {
        let ancestorSentences = TextAnalyzer.getSentences(in: ancestor)
        let ourSentences = TextAnalyzer.getSentences(in: ours)
        let theirSentences = TextAnalyzer.getSentences(in: theirs)
        
        let normalize: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        let ancestorNorm = Set(ancestorSentences.map { normalize($0.text) })
        let ourNorm = ourSentences.map { normalize($0.text) }
        let theirNorm = Set(theirSentences.map { normalize($0.text) })
        
        var merged = ""
        var conflicts: [MergeConflict] = []
        
        for sentence in ourSentences {
            let norm = normalize(sentence.text)
            
            if ancestorNorm.contains(norm) && theirNorm.contains(norm) {
                merged += sentence.text
            } else if ancestorNorm.contains(norm) && !theirNorm.contains(norm) {
                // Deleted by theirs — omit
            } else if !ancestorNorm.contains(norm) {
                merged += sentence.text
            } else {
                merged += sentence.text
            }
        }
        
        for sentence in theirSentences {
            let norm = normalize(sentence.text)
            if !ancestorNorm.contains(norm) && !Set(ourNorm).contains(norm) {
                merged += sentence.text
            }
        }
        
        for ancestorSentence in ancestorSentences {
            let norm = normalize(ancestorSentence.text)
            let inOurs = Set(ourNorm).contains(norm)
            let inTheirs = theirNorm.contains(norm)
            
            if !inOurs && !inTheirs {
                conflicts.append(MergeConflict(
                    position: ancestorSentence.range.location,
                    ourText: "Modified in current branch",
                    theirText: "Modified in other branch",
                    commonAncestorText: ancestorSentence.text
                ))
            }
        }
        
        return MergeResult(
            mergedContent: merged,
            conflicts: conflicts,
            hasUnresolvedConflicts: !conflicts.isEmpty
        )
    }
}
