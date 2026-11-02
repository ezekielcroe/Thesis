//
//  TextUnits.swift
//  Thesis
//
//  Created by Zhi Zheng Yeo on 2/11/26.
//


// TextUnits.swift — Thesis
// Splits prose into words, clauses, sentences and paragraphs.
//
// Every range in this file is an NSRange in UTF-16 code units, the unit NSString and
// NSTextView use. Never mix these with `String.count` (grapheme clusters).

import Foundation
import NaturalLanguage

extension String {
    /// Length in UTF-16 code units — the unit NSRange, NSString and NSTextView use.
    var utf16Length: Int { (self as NSString).length }
}

enum UnitKind: String, Codable, CaseIterable {
    case word, clause, sentence, paragraph
}

/// A unit of text. `range` covers the unit itself, without surrounding whitespace.
struct TextUnit: Equatable {
    let range: NSRange
    let text: String
    var location: Int { range.location }
    var end: Int { NSMaxRange(range) }
}

struct TextStats: Equatable {
    var words = 0
    var sentences = 0
    var paragraphs = 0
    static let zero = TextStats()
}

/// Segmentation of one immutable string. Each kind is computed lazily on first use;
/// build a new `TextUnits` whenever the text changes.
///
/// Definitions (deliberately simple and consistent with each other):
/// - paragraph: a non-blank line. Blank lines are separators, not paragraphs.
/// - sentence:  NLTokenizer sentences, never crossing a paragraph boundary.
/// - clause:    a sentence split after , ; : (when followed by a space) and after — or –.
/// - word:      NLTokenizer words (whitespace and punctuation excluded).
final class TextUnits {
    let text: String
    private let ns: NSString

    init(_ text: String) {
        self.text = text
        self.ns = text as NSString
    }

    private(set) lazy var paragraphs: [TextUnit] = makeParagraphs()
    private(set) lazy var sentences: [TextUnit] = makeSentences()
    private(set) lazy var clauses: [TextUnit] = makeClauses()
    private(set) lazy var words: [TextUnit] = makeWords()

    var stats: TextStats {
        TextStats(words: words.count, sentences: sentences.count, paragraphs: paragraphs.count)
    }

    func units(_ kind: UnitKind) -> [TextUnit] {
        switch kind {
        case .word: return words
        case .clause: return clauses
        case .sentence: return sentences
        case .paragraph: return paragraphs
        }
    }

    /// The unit the cursor is "on": the one containing `position`, else the one ending
    /// exactly at `position` (cursor just after a full stop), else the next one, else the last.
    func unit(_ kind: UnitKind, at position: Int) -> TextUnit? {
        let all = units(kind)
        if let hit = all.first(where: { $0.location <= position && position < $0.end }) { return hit }
        if let ending = all.last(where: { $0.end == position }) { return ending }
        return all.first(where: { $0.location > position }) ?? all.last
    }

    func nextStart(_ kind: UnitKind, after position: Int) -> Int? {
        units(kind).first(where: { $0.location > position })?.location
    }

    /// Start of the current unit if the cursor is inside it, otherwise of the previous one.
    func previousStart(_ kind: UnitKind, before position: Int) -> Int? {
        units(kind).last(where: { $0.location < position })?.location
    }

    /// From `position` to the end of its sentence (for D and C).
    func restOfSentence(from position: Int) -> NSRange? {
        guard let sentence = unit(.sentence, at: position), position < sentence.end else { return nil }
        let start = max(position, sentence.location)
        return NSRange(location: start, length: sentence.end - start)
    }

    /// "\n\n" if the document separates paragraphs with blank lines, otherwise "\n".
    var paragraphSeparator: String {
        ns.range(of: "\n\n").location != NSNotFound ? "\n\n" : "\n"
    }

    /// What to remove when deleting `range` as a unit of `kind`, so the text around it
    /// stays correctly spaced:
    /// - words, clauses, sentences take the spaces after them, or — at the end of a
    ///   paragraph — the spaces before them. A sentence that is a whole paragraph is
    ///   deleted as a paragraph.
    /// - paragraphs take the line breaks after them, or — if last — the ones before.
    func deletionRange(for range: NSRange, kind: UnitKind) -> NSRange {
        if kind != .paragraph,
           let paragraph = unit(.paragraph, at: range.location),
           paragraph.location >= range.location, paragraph.end <= NSMaxRange(range) {
            return deletionRange(for: paragraph.range, kind: .paragraph)
        }
        let start = range.location, end = NSMaxRange(range)
        if kind == .paragraph {
            let after = scan(from: end, forward: true, over: .whitespacesAndNewlines)
            if after < ns.length { return NSRange(location: start, length: after - start) }
            let before = scan(from: start, forward: false, over: .whitespacesAndNewlines)
            return NSRange(location: before, length: ns.length - before)
        }
        let after = scan(from: end, forward: true, over: .whitespaces)
        if after > end { return NSRange(location: start, length: after - start) }
        let before = scan(from: start, forward: false, over: .whitespaces)
        return NSRange(location: before, length: end - before)
    }

    // MARK: - Segmentation

    private func makeParagraphs() -> [TextUnit] {
        var result: [TextUnit] = []
        var start = 0
        while start < ns.length {
            let line = ns.lineRange(for: NSRange(location: start, length: 0))
            guard line.length > 0 else { break }
            let core = trimmed(line)
            if core.length > 0 { result.append(makeUnit(core)) }
            start = NSMaxRange(line)
        }
        return result
    }

    private func makeSentences() -> [TextUnit] {
        let tokenizer = NLTokenizer(unit: .sentence)
        var result: [TextUnit] = []
        for paragraph in paragraphs {
            let paragraphText = paragraph.text
            tokenizer.string = paragraphText
            tokenizer.enumerateTokens(in: paragraphText.startIndex..<paragraphText.endIndex) { tokenRange, _ in
                let local = NSRange(tokenRange, in: paragraphText)
                let global = NSRange(location: paragraph.location + local.location, length: local.length)
                let core = self.trimmed(global)
                if core.length > 0 { result.append(self.makeUnit(core)) }
                return true
            }
        }
        return result
    }

    private func makeClauses() -> [TextUnit] {
        let comma: unichar = 44, semicolon: unichar = 59, colon: unichar = 58
        let emDash: unichar = 0x2014, enDash: unichar = 0x2013
        var result: [TextUnit] = []
        for sentence in sentences {
            var clauseStart = sentence.location
            var i = sentence.location
            while i < sentence.end {
                let c = ns.character(at: i)
                let afterMark = i + 1
                let isDash = (c == emDash || c == enDash)
                let isPause = (c == comma || c == semicolon || c == colon)
                if (isDash || isPause) && afterMark < sentence.end {
                    // "1,000" and "10:30" are not clause breaks; "word—word" is.
                    let followedBySpace = isMember(ns.character(at: afterMark), .whitespaces)
                    if isDash || followedBySpace {
                        let core = trimmed(NSRange(location: clauseStart, length: afterMark - clauseStart))
                        if core.length > 0 { result.append(makeUnit(core)) }
                        clauseStart = afterMark
                    }
                }
                i += 1
            }
            let core = trimmed(NSRange(location: clauseStart, length: sentence.end - clauseStart))
            if core.length > 0 { result.append(makeUnit(core)) }
        }
        return result
    }

    private func makeWords() -> [TextUnit] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [TextUnit] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            result.append(self.makeUnit(NSRange(tokenRange, in: self.text)))
            return true
        }
        return result
    }

    // MARK: - Helpers

    private func makeUnit(_ range: NSRange) -> TextUnit {
        TextUnit(range: range, text: ns.substring(with: range))
    }

    private func trimmed(_ range: NSRange) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isMember(ns.character(at: start), .whitespacesAndNewlines) { start += 1 }
        while end > start, isMember(ns.character(at: end - 1), .whitespacesAndNewlines) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Forward: first position at or after `position` whose character is not in `set`.
    /// Backward: smallest position such that everything from it up to `position` is in `set`.
    private func scan(from position: Int, forward: Bool, over set: CharacterSet) -> Int {
        var p = position
        if forward {
            while p < ns.length, isMember(ns.character(at: p), set) { p += 1 }
        } else {
            while p > 0, isMember(ns.character(at: p - 1), set) { p -= 1 }
        }
        return p
    }

    private func isMember(_ c: unichar, _ set: CharacterSet) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return false }   // surrogate halves aren't whitespace
        return set.contains(scalar)
    }
}
