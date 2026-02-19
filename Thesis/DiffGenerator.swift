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
    let wordDiffs: [WordDiff]?    // Word-level sub-diff for modified sentences
    
    enum ChangeType {
        case addition
        case deletion
        case unchanged
        case moved                // Sentence exists in both but different position
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

// MARK: - Word-Level Diff (for showing changes within a modified sentence)

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
    let refined: Int
    let replaced: Int
    let moved: Int
    let totalChanges: Int
    
    var summary: String {
        var parts: [String] = []
        if added > 0    { parts.append("+\(added) added") }
        if deleted > 0  { parts.append("-\(deleted) deleted") }
        if refined > 0  { parts.append("~\(refined) refined") }
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
        
        // Build semantic change lookup
        var semanticMap: [String: SemanticChange] = [:]
        for change in changes {
            if let afterText = change.afterText {
                semanticMap[normalize(afterText)] = change
            }
        }
        
        // LCS to find longest common subsequence of sentences
        let lcs = longestCommonSubsequence(oldNorm, newNorm)
        
        // Build sets for quick lookup
        let oldNormSet = NSCountedSet(array: oldNorm)
        let newNormSet = NSCountedSet(array: newNorm)
        
        // Detect moves: sentences present in both but not in LCS alignment
        var movedSentences = Set<String>()
        for sentence in oldNorm {
            if newNormSet.contains(sentence) && !lcs.contains(sentence) {
                movedSentences.insert(sentence)
            }
        }
        
        var diffChanges: [DiffChange] = []
        var currentLocation = 0
        
        // Process new sentences
        for (i, newSentence) in newSentences.enumerated() {
            let norm = newNorm[i]
            let range = NSRange(location: currentLocation, length: newSentence.text.count)
            
            if lcs.contains(norm) || (oldNormSet.contains(norm) && !movedSentences.contains(norm)) {
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
                
                // Generate word-level sub-diff if we have the old version
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
            currentLocation += newSentence.text.count
        }
        
        // Find deletions (sentences in old but not in new)
        for (index, oldSentence) in oldSentences.enumerated() {
            let norm = oldNorm[index]
            guard !newNormSet.contains(norm) else { continue }
            
            // Find display anchor position
            var displayLocation = 0
            for i in (0..<index).reversed() {
                if newNormSet.contains(oldNorm[i]) {
                    if let match = newSentences.first(where: { normalize($0.text) == oldNorm[i] }) {
                        displayLocation = match.range.location + match.range.length
                        break
                    }
                }
            }
            
            let semanticType = findSemanticTypeForDeletion(norm, in: changes)
            
            diffChanges.append(DiffChange(
                type: .deletion, range: oldSentence.range, text: oldSentence.text,
                displayRange: NSRange(location: displayLocation, length: 0),
                semanticType: semanticType
            ))
        }
        
        // Sort by display position
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
    
    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> Set<String> {
        let m = a.count, n = b.count
        guard m > 0 && n > 0 else { return [] }
        
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
        
        var result = Set<String>()
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i-1] == b[j-1] {
                result.insert(a[i-1])
                i -= 1; j -= 1
            } else if dp[i-1][j] > dp[i][j-1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result
    }
    
    // MARK: - Word-Level Sub-Diff
    
    static func generateWordDiff(from oldText: String, to newText: String) -> [WordDiff] {
        let oldWords = oldText.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let newWords = newText.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        
        let m = oldWords.count, n = newWords.count
        guard m > 0 || n > 0 else { return [] }
        
        // Simple LCS for words
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
        
        // Backtrack
        var diffs: [WordDiff] = []
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
        var added = 0, deleted = 0, refined = 0, replaced = 0, moved = 0
        for change in diff {
            switch change.type {
            case .addition:
                switch change.semanticType {
                case .refined:  refined += 1
                case .replaced: replaced += 1
                default:        added += 1
                }
            case .deletion:
                if change.semanticType != .refined && change.semanticType != .replaced {
                    deleted += 1
                }
            case .moved: moved += 1
            case .unchanged: break
            }
        }
        return DiffStatistics(
            added: added, deleted: deleted, refined: refined,
            replaced: replaced, moved: moved,
            totalChanges: added + deleted + refined + replaced + moved
        )
    }
    
    // MARK: - Three-Way Merge (for branch merging)
    
    /// Generate a three-way merge from common ancestor, ours, and theirs
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
        
        // Walk through our sentences
        for sentence in ourSentences {
            let norm = normalize(sentence.text)
            
            if ancestorNorm.contains(norm) && theirNorm.contains(norm) {
                // Unchanged in both — keep
                merged += sentence.text
            } else if ancestorNorm.contains(norm) && !theirNorm.contains(norm) {
                // Deleted by theirs — omit (theirs wins for deletions)
            } else if !ancestorNorm.contains(norm) {
                // Added by us — keep
                merged += sentence.text
            } else {
                // Modified — potential conflict
                merged += sentence.text
            }
        }
        
        // Add sentences that theirs added (not in ancestor, not in ours)
        for sentence in theirSentences {
            let norm = normalize(sentence.text)
            if !ancestorNorm.contains(norm) && !Set(ourNorm).contains(norm) {
                merged += sentence.text
            }
        }
        
        // Detect conflicts: sentences modified in both branches differently
        for ancestorSentence in ancestorSentences {
            let norm = normalize(ancestorSentence.text)
            let inOurs = Set(ourNorm).contains(norm)
            let inTheirs = theirNorm.contains(norm)
            
            if !inOurs && !inTheirs {
                // Both branches modified/deleted this sentence — conflict
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
