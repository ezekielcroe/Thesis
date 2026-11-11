// ProseStatistics.swift — Thesis
// Counts, length distributions and rhythm/repetition checks for analysing prose
// mechanically.
//
// Counts (words, sentences, paragraphs) cover all text in scope, matching the status
// bar. Everything else covers prose only: Markdown headings, ``` code blocks, tables
// and horizontal rules are left out, so a "## Method" heading isn't a two-word sentence.
// All ranges are in the document's coordinates, so results can be jumped to.

import Foundation

/// Summary of a list of whole-number measurements (e.g. words per sentence).
struct Distribution: Equatable {
    let count: Int
    let mean: Double
    let min: Int
    let max: Int
    /// Quartiles by linear interpolation between closest ranks (Excel QUARTILE.INC,
    /// NumPy's default), so they can fall between two values, e.g. 12.5.
    let q1: Double
    let median: Double
    let q3: Double
    let standardDeviation: Double

    var range: Int { max - min }
    var interquartileRange: Double { q3 - q1 }

    init?(_ values: [Int]) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        count = sorted.count
        min = sorted[0]
        max = sorted[sorted.count - 1]
        let total = Double(sorted.reduce(0, +))
        mean = total / Double(count)
        let variance = sorted.reduce(0.0) { $0 + pow(Double($1) - total / Double(sorted.count), 2) } / Double(count)
        standardDeviation = variance.squareRoot()
        q1 = Self.quantile(sorted, 0.25)
        median = Self.quantile(sorted, 0.5)
        q3 = Self.quantile(sorted, 0.75)
    }

    static func quantile(_ sorted: [Int], _ p: Double) -> Double {
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return Double(sorted[lower]) + fraction * Double(sorted[upper] - sorted[lower])
    }
}

struct RankedSentence: Equatable {
    let range: NSRange
    let words: Int
    let text: String
    /// 1-based number of the prose paragraph it belongs to, counted within the scope.
    var paragraphIndex: Int = 0
}

struct HistogramBin: Equatable {
    let label: String
    let count: Int
}

/// Consecutive sentences whose lengths are all within 2 words of each other.
struct SimilarLengthRun: Equatable {
    let range: NSRange
    let lengths: [Int]
}

struct WordCount: Equatable {
    /// Lowercased.
    let word: String
    let count: Int
}

/// Consecutive sentences starting with the same word.
struct OpenerStreak: Equatable {
    let word: String
    let count: Int
    let range: NSRange
}

struct ProseStatistics {
    /// The range analysed: the whole text, or the requested scope widened to whole sentences.
    let scope: NSRange

    // All text in scope
    let words: Int
    let sentences: Int
    let paragraphs: Int
    let characters: Int
    let charactersExcludingSpaces: Int

    // Prose only
    let sentenceLength: Distribution?          // words per sentence
    let paragraphLengthInWords: Distribution?
    let paragraphLengthInSentences: Distribution?
    let longestSentences: [RankedSentence]
    /// Every prose sentence in scope, in document order.
    let sentenceList: [RankedSentence]
    let sentenceLengthHistogram: [HistogramBin]
    let similarLengthRuns: [SimilarLengthRun]
    /// Words that start two or more sentences, most frequent first.
    let openers: [WordCount]
    let openerStreaks: [OpenerStreak]
    /// Most frequent words, excluding common function words (English).
    let mostUsedWords: [WordCount]

    /// At an average silent reading speed of 238 words a minute.
    var readingMinutes: Double { Double(words) / 238 }
    var proseSentenceCount: Int { sentenceLength?.count ?? 0 }

    static let runTolerance = 2
    static let minimumRunLength = 3
    static let minimumStreakLength = 3

    init(text: String, scope requested: NSRange? = nil, longestCount: Int = 5, topWordsCount: Int = 15) {
        let ns = text as NSString
        let units = TextUnits(text)

        // Scope: widen to whole sentences so lengths mean something.
        var scope = NSRange(location: 0, length: ns.length)
        if let requested = requested {
            let lo = max(0, min(requested.location, ns.length))
            let hi = max(lo, min(NSMaxRange(requested), ns.length))
            let touched = units.sentences.filter { $0.location < hi && $0.end > lo }
            if let first = touched.first, let last = touched.last {
                scope = NSRange(location: min(first.location, lo), length: max(last.end, hi) - min(first.location, lo))
            } else {
                scope = NSRange(location: lo, length: hi - lo)
            }
        }
        self.scope = scope
        let start = scope.location, end = NSMaxRange(scope)
        func inside(_ u: TextUnit) -> Bool { u.location >= start && u.end <= end }
        func overlaps(_ u: TextUnit) -> Bool { u.location < end && u.end > start }

        let allWords = units.words.filter(inside)
        let allSentences = units.sentences.filter(inside)
        let allParagraphs = units.paragraphs

        words = allWords.count
        sentences = allSentences.count
        paragraphs = allParagraphs.filter(overlaps).count
        let scopedText = ns.substring(with: scope)
        characters = scopedText.count
        charactersExcludingSpaces = scopedText.filter { !$0.isWhitespace }.count

        // Prose paragraphs (fence state is tracked from the start of the document).
        var prose: [TextUnit] = []
        var inFence = false
        for paragraph in allParagraphs {
            let kind = MarkdownSource.kind(of: paragraph.text)
            if kind == .fence { inFence.toggle(); continue }
            if inFence || kind == .heading || kind == .table || Self.isRule(paragraph.text) { continue }
            if overlaps(paragraph) { prose.append(paragraph) }
        }

        // Walk paragraphs, sentences and words together (all sorted by position).
        var sentenceWordCounts: [Int] = []
        var ranked: [RankedSentence] = []
        var openerSequence: [(word: String, range: NSRange)] = []
        var paragraphWordCounts: [Int] = []
        var paragraphSentenceCounts: [Int] = []
        var frequencies: [String: Int] = [:]
        var w = 0, s = 0
        for (paragraphNumber, paragraph) in prose.enumerated() {
            var wordsInParagraph = 0
            var sentencesInParagraph = 0
            while s < allSentences.count && allSentences[s].end <= paragraph.location { s += 1 }
            while s < allSentences.count && allSentences[s].location < paragraph.end {
                let sentence = allSentences[s]
                while w < allWords.count && allWords[w].end <= sentence.location { w += 1 }
                var count = 0
                var firstWord: String?
                while w < allWords.count && allWords[w].location < sentence.end {
                    if let key = Self.key(for: allWords[w].text) {
                        if firstWord == nil { firstWord = key }
                        if !Self.stopWords.contains(key) && key.count > 1 { frequencies[key, default: 0] += 1 }
                    }
                    count += 1
                    w += 1
                }
                if count > 0 {
                    sentenceWordCounts.append(count)
                    ranked.append(RankedSentence(range: sentence.range, words: count, text: sentence.text,
                                                 paragraphIndex: paragraphNumber + 1))
                    if let firstWord = firstWord { openerSequence.append((firstWord, sentence.range)) }
                    wordsInParagraph += count
                    sentencesInParagraph += 1
                }
                s += 1
            }
            if wordsInParagraph > 0 {
                paragraphWordCounts.append(wordsInParagraph)
                paragraphSentenceCounts.append(sentencesInParagraph)
            }
        }

        sentenceList = ranked
        sentenceLength = Distribution(sentenceWordCounts)
        paragraphLengthInWords = Distribution(paragraphWordCounts)
        paragraphLengthInSentences = Distribution(paragraphSentenceCounts)
        longestSentences = Array(
            ranked.sorted { $0.words != $1.words ? $0.words > $1.words : $0.range.location < $1.range.location }
                .prefix(longestCount)
        )
        sentenceLengthHistogram = Self.histogram(sentenceWordCounts)
        similarLengthRuns = Self.similarRuns(ranked)
        openers = Self.ranked(openerSequence.map(\.word), minimum: 2, limit: 8)
        openerStreaks = Self.streaks(openerSequence)
        mostUsedWords = Self.ranked(frequencies, minimum: 2, limit: topWordsCount)
    }

    // MARK: - Measures

    /// 1–5, 6–10, … 36–40, 41+ words.
    static func histogram(_ lengths: [Int]) -> [HistogramBin] {
        var bins = (0..<8).map { i in HistogramBin(label: "\(i * 5 + 1)–\(i * 5 + 5)", count: 0) }
        bins.append(HistogramBin(label: "41+", count: 0))
        var counts = Array(repeating: 0, count: bins.count)
        for length in lengths where length > 0 {
            counts[min((length - 1) / 5, bins.count - 1)] += 1
        }
        return zip(bins, counts).map { HistogramBin(label: $0.label, count: $1) }
    }

    /// Maximal runs of at least three consecutive sentences whose lengths differ by at
    /// most `runTolerance` words (longest minus shortest).
    static func similarRuns(_ sentences: [RankedSentence]) -> [SimilarLengthRun] {
        var runs: [SimilarLengthRun] = []
        var i = 0
        while i < sentences.count {
            var j = i
            var lo = sentences[i].words, hi = sentences[i].words
            while j + 1 < sentences.count {
                let next = sentences[j + 1].words
                guard max(hi, next) - min(lo, next) <= runTolerance else { break }
                lo = min(lo, next)
                hi = max(hi, next)
                j += 1
            }
            if j - i + 1 >= minimumRunLength {
                let startLocation = sentences[i].range.location
                runs.append(SimilarLengthRun(
                    range: NSRange(location: startLocation, length: NSMaxRange(sentences[j].range) - startLocation),
                    lengths: sentences[i...j].map(\.words)))
                i = j + 1
            } else {
                i += 1
            }
        }
        return runs
    }

    static func streaks(_ openers: [(word: String, range: NSRange)]) -> [OpenerStreak] {
        var result: [OpenerStreak] = []
        var i = 0
        while i < openers.count {
            var j = i
            while j + 1 < openers.count && openers[j + 1].word == openers[i].word { j += 1 }
            if j - i + 1 >= minimumStreakLength {
                let startLocation = openers[i].range.location
                result.append(OpenerStreak(
                    word: openers[i].word, count: j - i + 1,
                    range: NSRange(location: startLocation, length: NSMaxRange(openers[j].range) - startLocation)))
            }
            i = j + 1
        }
        return result
    }

    static func ranked(_ words: [String], minimum: Int, limit: Int) -> [WordCount] {
        ranked(words.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }, minimum: minimum, limit: limit)
    }

    static func ranked(_ counts: [String: Int], minimum: Int, limit: Int) -> [WordCount] {
        Array(counts.filter { $0.value >= minimum }
            .map { WordCount(word: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.word < $1.word }
            .prefix(limit))
    }

    /// Lowercased word without surrounding quotes/apostrophes; nil for fragments like "n't".
    static func key(for token: String) -> String? {
        if token.hasPrefix("'") || token.hasPrefix("’") { return nil }
        let trimmed = token.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .letters) != nil else { return nil }
        return trimmed
    }

    /// Function words that would otherwise top every list. Words writers often overuse
    /// on purpose to check (just, really, very, quite, actually…) are deliberately kept.
    static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "nor", "so", "yet", "for", "of", "in", "on", "at", "by",
        "to", "from", "with", "without", "into", "onto", "over", "under", "about", "above", "below",
        "after", "before", "between", "through", "during", "as", "than", "then", "if", "else", "when",
        "while", "where", "because", "since", "though", "although", "unless", "until", "upon", "within",
        "across", "against", "along", "among", "around", "behind", "beyond", "near", "off", "out", "up",
        "down", "per", "via", "i", "me", "my", "mine", "myself", "we", "us", "our", "ours", "ourselves",
        "you", "your", "yours", "yourself", "yourselves", "he", "him", "his", "himself", "she", "her",
        "hers", "herself", "it", "its", "itself", "they", "them", "their", "theirs", "themselves", "this",
        "that", "these", "those", "who", "whom", "whose", "which", "what", "there", "here", "is", "am",
        "are", "was", "were", "be", "been", "being", "have", "has", "had", "having", "do", "does", "did",
        "doing", "done", "will", "would", "shall", "should", "can", "could", "may", "might", "must",
        "not", "no", "all", "any", "each", "both", "few", "more", "most", "other", "some", "such", "only",
        "own", "same", "also", "too", "how", "why", "one", "s", "t", "d", "ll", "re", "ve", "m",
        "don", "doesn", "didn", "isn", "aren", "wasn", "weren", "won", "wouldn", "can't", "don't",
        "it's", "i'm", "i've", "i'd", "i'll", "that's", "there's",
    ]

    /// "---", "***", "___" (three or more, optionally spaced).
    private static func isRule(_ line: String) -> Bool {
        let chars = line.filter { !$0.isWhitespace }
        guard chars.count >= 3, let first = chars.first, "-*_".contains(first) else { return false }
        return chars.allSatisfy { $0 == first }
    }
}
