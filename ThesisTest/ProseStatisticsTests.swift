import XCTest
@testable import Thesis

final class DistributionTests: XCTestCase {

    func testQuartilesInterpolate() throws {
        let d = try XCTUnwrap(Distribution([4, 1, 3, 2]))   // order doesn't matter
        XCTAssertEqual(d.min, 1)
        XCTAssertEqual(d.max, 4)
        XCTAssertEqual(d.range, 3)
        XCTAssertEqual(d.mean, 2.5)
        XCTAssertEqual(d.q1, 1.75)
        XCTAssertEqual(d.median, 2.5)
        XCTAssertEqual(d.q3, 3.25)
        XCTAssertEqual(d.interquartileRange, 1.5)
        XCTAssertEqual(d.standardDeviation, 1.25.squareRoot(), accuracy: 1e-9)   // population SD
    }

    func testOddCountMedianIsTheMiddleValue() throws {
        let d = try XCTUnwrap(Distribution([10, 2, 7]))
        XCTAssertEqual(d.median, 7)
        XCTAssertEqual(d.q1, 4.5)
        XCTAssertEqual(d.q3, 8.5)
    }

    func testSingleValueAndEmpty() throws {
        let d = try XCTUnwrap(Distribution([5]))
        XCTAssertEqual([d.q1, d.median, d.q3], [5, 5, 5])
        XCTAssertEqual(d.range, 0)
        XCTAssertNil(Distribution([]))
    }
}

final class ProseStatisticsTests: XCTestCase {

    func testCountsAndLengths() throws {
        let s = ProseStatistics(text: "One two three. Four five.\nSix seven eight nine.")
        XCTAssertEqual(s.words, 9)
        XCTAssertEqual(s.sentences, 3)
        XCTAssertEqual(s.paragraphs, 2)

        let sentences = try XCTUnwrap(s.sentenceLength)
        XCTAssertEqual(sentences.count, 3)
        XCTAssertEqual(sentences.min, 2)
        XCTAssertEqual(sentences.max, 4)
        XCTAssertEqual(sentences.median, 3)

        XCTAssertEqual(s.paragraphLengthInWords?.min, 4)
        XCTAssertEqual(s.paragraphLengthInWords?.max, 5)
        XCTAssertEqual(s.paragraphLengthInSentences?.max, 2)
    }

    func testLongestSentencesComeFirst() {
        let s = ProseStatistics(text: "Short one. This sentence is clearly the longest here. Medium length one.")
        XCTAssertEqual(s.longestSentences.map(\.words), [7, 3, 2])
        XCTAssertEqual(s.longestSentences.first?.text, "This sentence is clearly the longest here.")
    }

    func testHeadingsCodeAndTablesAreNotProse() throws {
        let text = """
        # Introduction
        A real sentence with six words.
        ```
        let x = 1
        ```
        | a | b |
        ---
        """
        let s = ProseStatistics(text: text)
        let sentences = try XCTUnwrap(s.sentenceLength)
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences.max, 6)
        XCTAssertEqual(s.paragraphLengthInWords?.count, 1)
    }

    func testEmptyDocument() {
        let s = ProseStatistics(text: "")
        XCTAssertEqual(s.words, 0)
        XCTAssertNil(s.sentenceLength)
        XCTAssertTrue(s.longestSentences.isEmpty)
    }

    // MARK: - Rhythm and repetition

    func testHistogramBins() {
        let bins = ProseStatistics.histogram([1, 5, 6, 12, 40, 41, 90])
        XCTAssertEqual(bins.map(\.label), ["1–5", "6–10", "11–15", "16–20", "21–25", "26–30", "31–35", "36–40", "41+"])
        XCTAssertEqual(bins.map(\.count), [2, 1, 1, 0, 0, 0, 0, 1, 2])
    }

    func testSimilarLengthRuns() {
        func sentences(_ lengths: [Int]) -> [RankedSentence] {
            lengths.enumerated().map { RankedSentence(range: NSRange(location: $0.offset * 10, length: 9), words: $0.element, text: "") }
        }
        // 10, 11, 12 is a run (spread 2); 30 breaks it; 5, 7, 6, 5 is another (spread 2).
        let runs = ProseStatistics.similarRuns(sentences([10, 11, 12, 30, 5, 7, 6, 5, 20]))
        XCTAssertEqual(runs.map(\.lengths), [[10, 11, 12], [5, 7, 6, 5]])
        XCTAssertEqual(runs.first?.range, NSRange(location: 0, length: 29))
        XCTAssertTrue(ProseStatistics.similarRuns(sentences([10, 13, 10, 13])).isEmpty, "spread 3 is too wide")
    }

    func testOpenersAndStreaks() {
        let text = "I went out. I saw rain. I came back. The end came. The light faded."
        let s = ProseStatistics(text: text)
        XCTAssertEqual(s.openers, [WordCount(word: "i", count: 3), WordCount(word: "the", count: 2)])
        XCTAssertEqual(s.openerStreaks.count, 1)
        XCTAssertEqual(s.openerStreaks.first?.word, "i")
        XCTAssertEqual(s.openerStreaks.first?.count, 3)
        XCTAssertEqual(s.openerStreaks.first?.range, NSRange(location: 0, length: ("I went out. I saw rain. I came back." as NSString).length))
    }

    func testMostUsedWordsSkipCommonWords() {
        let s = ProseStatistics(text: "The river ran. The river was very cold. It was very, very cold.")
        XCTAssertEqual(s.mostUsedWords.first, WordCount(word: "very", count: 3))
        XCTAssertTrue(s.mostUsedWords.contains(WordCount(word: "river", count: 2)))
        XCTAssertTrue(s.mostUsedWords.contains(WordCount(word: "cold", count: 2)))
        XCTAssertFalse(s.mostUsedWords.contains { ["the", "was", "it"].contains($0.word) })
    }

    // MARK: - Scope

    func testParagraphScope() throws {
        let text = "One two three. Four five.\nSix seven eight nine."
        let second = (text as NSString).range(of: "Six seven eight nine.")
        let s = ProseStatistics(text: text, scope: second)
        XCTAssertEqual(s.words, 4)
        XCTAssertEqual(s.sentences, 1)
        XCTAssertEqual(s.paragraphs, 1)
        XCTAssertEqual(try XCTUnwrap(s.sentenceLength).max, 4)
    }

    func testSelectionIsWidenedToWholeSentences() {
        let text = "One two three. Four five six seven."
        let partial = (text as NSString).range(of: "three. Four")   // ends mid-sentence
        let s = ProseStatistics(text: text, scope: partial)
        XCTAssertEqual(s.scope, NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(s.sentences, 2)
        XCTAssertEqual(s.words, 7)
    }
}
