//
//  ChangeKind.swift
//  Thesis
//
//  Created by Zhi Zheng Yeo on 2/11/26.
//


// ProseDiff.swift — Thesis
// Works out what changed between two versions of a text, at the level writers think
// in: sentences added, cut, reworded, rewritten or moved.
//
// Nothing here is recorded while you type. Changes are derived by comparing two
// snapshots, so every way of editing (typing, pasting, commands) is covered equally.

import Foundation
import CryptoKit

enum ChangeKind: String, Codable, CaseIterable {
    case added       // new sentence(s) with no counterpart in the old text
    case cut         // sentence(s) removed with no counterpart in the new text
    case reworded    // same sentence, wording adjusted (high word overlap)
    case rewritten   // same slot, substantially different sentence (low word overlap)
    case moved       // identical sentence(s) in a different place

    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .added: return "plus.circle"
        case .cut: return "scissors"
        case .reworded: return "pencil"
        case .rewritten: return "arrow.triangle.2.circlepath"
        case .moved: return "arrow.up.arrow.down"
        }
    }
}

struct WordDiffPart: Equatable {
    enum Kind: Equatable { case same, added, removed }
    let kind: Kind
    let text: String
}

struct ProseChange: Equatable {
    let kind: ChangeKind
    /// Text in the old version (nil for additions).
    let before: String?
    /// Text in the new version (nil for cuts).
    let after: String?
    /// UTF-16 offset in the new text where the change sits (for cuts: where the text used to be).
    let location: Int

    /// Stable identity derived from the change itself, so a reason ("why") attached to it
    /// can be found again whenever the same change is recomputed.
    var fingerprint: String { ProseDiff.fingerprint(kind: kind, before: before, after: after) }

    var wordDiff: [WordDiffPart] { ProseDiff.wordDiff(from: before ?? "", to: after ?? "") }

    /// Text this change took out of the document — what becomes a darling.
    var lostText: String? { (kind == .cut || kind == .rewritten) ? before : nil }
}

enum ProseDiff {
    /// Below this word overlap, two sentences in the same gap aren't considered related.
    static let pairingThreshold = 0.3
    /// At or above this overlap a related pair counts as reworded, below it as rewritten.
    static let rewordedThreshold = 0.6

    static func changes(from oldText: String, to newText: String) -> [ProseChange] {
        let oldUnits = TextUnits(oldText).sentences
        let newUnits = TextUnits(newText).sentences
        let oldKeys = oldUnits.map { normalize($0.text) }
        let newKeys = newUnits.map { normalize($0.text) }

        // 1. Align unchanged sentences; what's between two aligned sentences is a gap.
        struct Gap { let old: [Int]; let new: [Int]; let location: Int }
        var gaps: [Gap] = []
        var nextOld = 0, nextNew = 0
        for (i, j) in alignedPairs(oldKeys, newKeys) + [(oldUnits.count, newUnits.count)] {
            let newIndices = Array(nextNew..<j)
            let location = newIndices.first.map { newUnits[$0].location }
                ?? (nextNew > 0 ? newUnits[nextNew - 1].end : 0)
            let gap = Gap(old: Array(nextOld..<i), new: newIndices, location: location)
            if !gap.old.isEmpty || !gap.new.isEmpty { gaps.append(gap) }
            nextOld = i + 1
            nextNew = j + 1
        }

        struct Item { var kind: ChangeKind; var old: [Int]; var new: [Int]; var location: Int; var rank: Int }
        var items: [Item] = []

        // 2. Moves: an identical sentence that left one gap and turned up in another.
        var unmatchedOld: [String: [Int]] = [:]
        for gap in gaps { for i in gap.old { unmatchedOld[oldKeys[i], default: []].append(i) } }
        var movedOld = Set<Int>(), movedNew = Set<Int>()
        for gap in gaps {
            for j in gap.new {
                guard var candidates = unmatchedOld[newKeys[j]], !candidates.isEmpty else { continue }
                let i = candidates.removeFirst()
                unmatchedOld[newKeys[j]] = candidates
                movedOld.insert(i)
                movedNew.insert(j)
                items.append(Item(kind: .moved, old: [i], new: [j], location: newUnits[j].location, rank: 1))
            }
        }

        // 3. Within each gap, pair related sentences by word overlap.
        for gap in gaps {
            let olds = gap.old.filter { !movedOld.contains($0) }
            let news = gap.new.filter { !movedNew.contains($0) }

            var candidates: [(i: Int, j: Int, score: Double)] = []
            for i in olds {
                for j in news {
                    let score = similarity(oldUnits[i].text, newUnits[j].text)
                    if score >= pairingThreshold { candidates.append((i: i, j: j, score: score)) }
                }
            }
            candidates.sort { $0.score > $1.score }

            var pairedOld = Set<Int>(), pairedNew = Set<Int>()
            for c in candidates where !pairedOld.contains(c.i) && !pairedNew.contains(c.j) {
                pairedOld.insert(c.i)
                pairedNew.insert(c.j)
                let kind: ChangeKind = c.score >= rewordedThreshold ? .reworded : .rewritten
                items.append(Item(kind: kind, old: [c.i], new: [c.j], location: newUnits[c.j].location, rank: 1))
            }

            let leftoverOld = olds.filter { !pairedOld.contains($0) }
            let leftoverNew = news.filter { !pairedNew.contains($0) }
            if pairedOld.isEmpty && leftoverOld.count == 1 && leftoverNew.count == 1 {
                // One sentence out, one in, same place: the writer replaced it.
                items.append(Item(kind: .rewritten, old: leftoverOld, new: leftoverNew,
                                  location: newUnits[leftoverNew[0]].location, rank: 1))
            } else {
                for i in leftoverOld {
                    items.append(Item(kind: .cut, old: [i], new: [], location: gap.location, rank: 0))
                }
                for j in leftoverNew {
                    items.append(Item(kind: .added, old: [], new: [j], location: newUnits[j].location, rank: 1))
                }
            }
        }

        // 4. Order by position in the new text (cuts just before what replaced them).
        items.sort { a, b in
            if a.location != b.location { return a.location < b.location }
            if a.rank != b.rank { return a.rank < b.rank }
            return (a.old.first ?? -1, a.new.first ?? -1) < (b.old.first ?? -1, b.new.first ?? -1)
        }

        // 5. Merge runs, so "added a paragraph" is one change rather than five.
        func follows(_ a: [Int], _ b: [Int]) -> Bool {
            guard let last = a.last, let first = b.first else { return false }
            return first == last + 1
        }
        var merged: [Item] = []
        for item in items {
            if var last = merged.last, last.kind == item.kind {
                let joinable: Bool
                switch item.kind {
                case .added: joinable = follows(last.new, item.new)
                case .cut: joinable = follows(last.old, item.old) && last.location == item.location
                case .moved: joinable = follows(last.old, item.old) && follows(last.new, item.new)
                case .reworded, .rewritten: joinable = false
                }
                if joinable {
                    last.old += item.old
                    last.new += item.new
                    merged[merged.count - 1] = last
                    continue
                }
            }
            merged.append(item)
        }

        // 6. Build the changes, taking text spans verbatim (keeps original spacing).
        let oldNS = oldText as NSString, newNS = newText as NSString
        func span(_ indices: [Int], _ units: [TextUnit], _ ns: NSString) -> String? {
            guard let first = indices.first, let last = indices.last else { return nil }
            let start = units[first].location
            return ns.substring(with: NSRange(location: start, length: units[last].end - start))
        }
        return merged.map {
            ProseChange(kind: $0.kind,
                        before: span($0.old, oldUnits, oldNS),
                        after: span($0.new, newUnits, newNS),
                        location: $0.location)
        }
    }

    // MARK: - Building blocks

    /// Collapses whitespace so re-spacing a sentence isn't reported as a change.
    static func normalize(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Word overlap in 0...1 (Dice coefficient over the longest common word sequence).
    static func similarity(_ a: String, _ b: String) -> Double {
        let wa = words(a), wb = words(b)
        if wa.isEmpty && wb.isEmpty { return 1 }
        guard !wa.isEmpty, !wb.isEmpty else { return 0 }
        return 2 * Double(lcs(wa, wb).count) / Double(wa.count + wb.count)
    }

    static func words(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func fingerprint(kind: ChangeKind, before: String?, after: String?) -> String {
        let key = [kind.rawValue, normalize(before ?? ""), normalize(after ?? "")].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Word-by-word comparison of two sentences, for showing a rewording inline.
    static func wordDiff(from old: String, to new: String) -> [WordDiffPart] {
        let a = tokens(old), b = tokens(new)
        let aKeys = a.map { normalize($0) }, bKeys = b.map { normalize($0) }
        var parts: [WordDiffPart] = []
        func add(_ kind: WordDiffPart.Kind, _ text: String) {
            if let last = parts.last, last.kind == kind {
                parts[parts.count - 1] = WordDiffPart(kind: kind, text: last.text + text)
            } else {
                parts.append(WordDiffPart(kind: kind, text: text))
            }
        }
        var i = 0, j = 0
        for (pi, pj) in lcs(aKeys, bKeys) + [(a.count, b.count)] {
            while i < pi { add(.removed, a[i]); i += 1 }
            while j < pj { add(.added, b[j]); j += 1 }
            if pi < a.count && pj < b.count {
                add(.same, b[pj])
                i += 1
                j += 1
            }
        }
        return parts
    }

    /// Splits into words that carry their trailing whitespace: "The cat " → ["The ", "cat "].
    static func tokens(_ s: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inTrailingSpace = false
        for ch in s {
            if ch.isWhitespace {
                current.append(ch)
                inTrailingSpace = true
            } else {
                if inTrailingSpace {
                    result.append(current)
                    current = ""
                    inTrailingSpace = false
                }
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Index pairs of a longest common subsequence. Trims the common prefix and suffix
    /// first, since consecutive snapshots are usually almost identical.
    static func alignedPairs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
              a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }

        let middleA = Array(a[prefix..<(a.count - suffix)])
        let middleB = Array(b[prefix..<(b.count - suffix)])
        var pairs: [(Int, Int)] = (0..<prefix).map { ($0, $0) }
        pairs += lcs(middleA, middleB).map { ($0.0 + prefix, $0.1 + prefix) }
        pairs += (0..<suffix).map { (a.count - suffix + $0, b.count - suffix + $0) }
        return pairs
    }

    static func lcs<T: Equatable>(_ a: [T], _ b: [T]) -> [(Int, Int)] {
        let m = a.count, n = b.count
        guard m > 0, n > 0 else { return [] }
        // dp[i][j] = LCS length of a[i...] and b[j...]
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < m && j < n {
            if a[i] == b[j] {
                pairs.append((i, j))
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
