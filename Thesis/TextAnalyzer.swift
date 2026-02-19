// TextAnalyzer.swift — Thesis
// NLP-powered text boundary detection with caching and invalidation
// Uses Apple NaturalLanguage framework for word, clause, sentence, paragraph parsing

import Foundation
import NaturalLanguage

// MARK: - Cached Text Analyzer (instance per editor, invalidated per edit)

class CachedTextAnalyzer {
    private var cachedText: String = ""
    private var _sentences: [TextUnit]?
    private var _clauses: [TextUnit]?
    private var _paragraphs: [TextUnit]?
    private var _words: [TextUnit]?
    private var _stats: TextAnalyzer.Stats?
    
    func invalidate() {
        _sentences = nil
        _clauses = nil
        _paragraphs = nil
        _words = nil
        _stats = nil
    }
    
    private func ensureText(_ text: String) {
        if text != cachedText {
            invalidate()
            cachedText = text
        }
    }
    
    func sentences(in text: String) -> [TextUnit] {
        ensureText(text)
        if let c = _sentences { return c }
        let r = TextAnalyzer.getSentences(in: text)
        _sentences = r
        return r
    }
    
    func clauses(in text: String) -> [TextUnit] {
        ensureText(text)
        if let c = _clauses { return c }
        let r = TextAnalyzer.getClauses(in: text)
        _clauses = r
        return r
    }
    
    func paragraphs(in text: String) -> [TextUnit] {
        ensureText(text)
        if let c = _paragraphs { return c }
        let r = TextAnalyzer.getParagraphs(in: text)
        _paragraphs = r
        return r
    }
    
    func words(in text: String) -> [TextUnit] {
        ensureText(text)
        if let c = _words { return c }
        let r = TextAnalyzer.getWords(in: text)
        _words = r
        return r
    }
    
    func stats(for text: String) -> TextAnalyzer.Stats {
        ensureText(text)
        if let c = _stats { return c }
        let r = TextAnalyzer.Stats(
            paragraphCount: paragraphs(in: text).count,
            sentenceCount: sentences(in: text).count,
            wordCount: words(in: text).count
        )
        _stats = r
        return r
    }
    
    // Convenience methods mirroring static API
    
    func sentenceAt(_ pos: Int, in text: String) -> TextUnit? {
        sentences(in: text).first { NSLocationInRange(pos, $0.range) }
    }
    
    func clauseAt(_ pos: Int, in text: String) -> TextUnit? {
        clauses(in: text).first { NSLocationInRange(pos, $0.range) }
    }
    
    func paragraphAt(_ pos: Int, in text: String) -> TextUnit? {
        paragraphs(in: text).first { NSLocationInRange(pos, $0.range) }
    }
    
    func wordAt(_ pos: Int, in text: String) -> TextUnit? {
        let ws = words(in: text)
        return ws.first(where: { NSLocationInRange(pos, $0.range) })
            ?? ws.first(where: { $0.range.location >= pos })
    }
    
    func nextSentence(from pos: Int, in text: String) -> TextUnit? {
        sentences(in: text).first { $0.range.location > pos }
    }
    
    func prevSentence(from pos: Int, in text: String) -> TextUnit? {
        sentences(in: text).last { $0.range.location < pos }
    }
    
    func nextWord(from pos: Int, in text: String) -> TextUnit? {
        words(in: text).first(where: {
            $0.range.location > pos &&
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
    }
    
    func prevWord(from pos: Int, in text: String) -> TextUnit? {
        let ws = words(in: text)
        let currentStart = ws.first(where: {
            NSLocationInRange(pos, $0.range) || $0.range.location == pos
        })?.range.location ?? pos
        return ws.last(where: {
            $0.range.location < currentStart &&
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
    }
}

// MARK: - TextAnalyzer (static methods)

class TextAnalyzer {
    
    // MARK: - Sentence Detection
    
    static func getSentences(in text: String) -> [TextUnit] {
        guard !text.isEmpty else { return [] }
        var sentences: [TextUnit] = []
        let nsText = text as NSString
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .sentence,
            scheme: .lexicalClass
        ) { _, range in
            let nsRange = NSRange(range, in: text)
            sentences.append(TextUnit(range: nsRange, text: nsText.substring(with: nsRange)))
            return true
        }
        return sentences
    }
    
    static func getSentenceAt(position: Int, in text: String) -> TextUnit? {
        getSentences(in: text).first { NSLocationInRange(position, $0.range) }
    }
    
    static func getNextSentence(from position: Int, in text: String) -> TextUnit? {
        getSentences(in: text).first { $0.range.location > position }
    }
    
    static func getPreviousSentence(from position: Int, in text: String) -> TextUnit? {
        getSentences(in: text).last { $0.range.location < position }
    }
    
    // MARK: - Clause Detection
    
    static func getClauses(in text: String) -> [TextUnit] {
        guard !text.isEmpty else { return [] }
        var clauses: [TextUnit] = []
        let sentences = getSentences(in: text)
        let nsText = text as NSString
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        
        for sentence in sentences {
            tagger.string = sentence.text
            var lastBoundary = 0
            
            tagger.enumerateTags(
                in: sentence.text.startIndex..<sentence.text.endIndex,
                unit: .word,
                scheme: .lexicalClass
            ) { tag, range in
                let wordRange = NSRange(range, in: sentence.text)
                let word = (sentence.text as NSString).substring(with: wordRange).lowercased()
                let isBoundaryPunct = (tag == .punctuation && (word == "," || word == ";" || word == ":"))
                let isConjunction = (tag == .conjunction)
                
                if isBoundaryPunct || isConjunction {
                    let length = wordRange.location - lastBoundary
                    if length > 0 {
                        let clauseRange = NSRange(location: sentence.range.location + lastBoundary, length: length)
                        clauses.append(TextUnit(range: clauseRange, text: nsText.substring(with: clauseRange)))
                    }
                    lastBoundary = wordRange.location
                }
                return true
            }
            
            let finalLength = sentence.range.length - lastBoundary
            if finalLength > 0 {
                let finalRange = NSRange(location: sentence.range.location + lastBoundary, length: finalLength)
                clauses.append(TextUnit(range: finalRange, text: nsText.substring(with: finalRange)))
            }
        }
        return clauses
    }
    
    static func getClauseAt(position: Int, in text: String) -> TextUnit? {
        getClauses(in: text).first { NSLocationInRange(position, $0.range) }
    }
    
    // MARK: - Paragraph Detection
    
    static func getParagraphs(in text: String) -> [TextUnit] {
        guard !text.isEmpty else { return [] }
        var paragraphs: [TextUnit] = []
        let nsText = text as NSString
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .paragraph,
            scheme: .lexicalClass
        ) { _, range in
            let nsRange = NSRange(range, in: text)
            let paraText = nsText.substring(with: nsRange)
            if !paraText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                paragraphs.append(TextUnit(range: nsRange, text: paraText))
            }
            return true
        }
        return paragraphs
    }
    
    static func getParagraphAt(position: Int, in text: String) -> TextUnit? {
        getParagraphs(in: text).first { NSLocationInRange(position, $0.range) }
    }
    
    // MARK: - Word Detection
    
    static func getWords(in text: String) -> [TextUnit] {
        guard !text.isEmpty else { return [] }
        var words: [TextUnit] = []
        let nsText = text as NSString
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass
        ) { _, range in
            let nsRange = NSRange(range, in: text)
            words.append(TextUnit(range: nsRange, text: nsText.substring(with: nsRange)))
            return true
        }
        return words
    }
    
    static func getWordAt(position: Int, in text: String) -> TextUnit? {
        let words = getWords(in: text)
        return words.first(where: { NSLocationInRange(position, $0.range) })
            ?? words.first(where: { $0.range.location >= position })
    }
    
    // MARK: - Line Navigation
    
    static func getNextLineStart(from position: Int, in text: String) -> Int {
        let nsText = text as NSString
        guard position < nsText.length else { return nsText.length }
        let range = NSRange(location: position, length: nsText.length - position)
        let next = nsText.range(of: "\n", options: [], range: range)
        return next.location != NSNotFound ? min(next.location + 1, nsText.length) : nsText.length
    }
    
    static func getPreviousLineStart(from position: Int, in text: String) -> Int {
        let nsText = text as NSString
        guard position > 0 else { return 0 }
        let range = NSRange(location: 0, length: min(position, nsText.length))
        let prev = nsText.range(of: "\n", options: .backwards, range: range)
        if prev.location != NSNotFound {
            if prev.location == position - 1 {
                let sub = NSRange(location: 0, length: prev.location)
                let p2 = nsText.range(of: "\n", options: .backwards, range: sub)
                return p2.location != NSNotFound ? p2.location + 1 : 0
            }
            return prev.location + 1
        }
        return 0
    }
    
    // MARK: - Helpers
    
    static func getRestOfSentence(from position: Int, in text: String) -> TextUnit? {
        guard let sentence = getSentenceAt(position: position, in: text) else { return nil }
        let restEnd = sentence.endLocation
        guard restEnd > position else { return nil }
        let restRange = NSRange(location: position, length: restEnd - position)
        let nsText = text as NSString
        guard restRange.location + restRange.length <= nsText.length else { return nil }
        return TextUnit(range: restRange, text: nsText.substring(with: restRange))
    }
    
    static func expandToTrailingSpace(_ range: NSRange, in text: String) -> NSRange {
        let nsText = text as NSString
        var expanded = range
        var endPos = expanded.location + expanded.length
        while endPos < nsText.length {
            let c = nsText.substring(with: NSRange(location: endPos, length: 1))
            if c == " " || c == "\t" { expanded.length += 1; endPos += 1 }
            else { break }
        }
        return expanded
    }
    
    static func expandToLeadingSpace(_ range: NSRange, in text: String) -> NSRange {
        let nsText = text as NSString
        var expanded = range
        while expanded.location > 0 {
            let c = nsText.substring(with: NSRange(location: expanded.location - 1, length: 1))
            if c == " " || c == "\t" { expanded.location -= 1; expanded.length += 1 }
            else { break }
        }
        return expanded
    }
    
    // MARK: - Safe Range Utilities
    
    static func safeRange(_ range: NSRange, in length: Int) -> NSRange {
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        let loc = max(0, min(range.location, length))
        let len = max(0, min(range.length, length - loc))
        return NSRange(location: loc, length: len)
    }
    
    static func safePosition(_ position: Int, in text: String) -> Int {
        max(0, min(position, (text as NSString).length))
    }
    
    // MARK: - Statistics
    
    struct Stats {
        let paragraphCount: Int
        let sentenceCount: Int
        let wordCount: Int
    }
    
    static func computeStats(for text: String) -> Stats {
        Stats(
            paragraphCount: getParagraphs(in: text).count,
            sentenceCount: getSentences(in: text).count,
            wordCount: getWords(in: text).count
        )
    }
}
