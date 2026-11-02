import XCTest
@testable import Thesis

final class StatisticsTableTests: XCTestCase {

    private let text = "One two three. Four five.\nSix seven eight nine."
    private let date = Date(timeIntervalSince1970: 0)

    private func table(_ content: StatisticsTable.Content, text: String? = nil) -> StatisticsTable {
        StatisticsTable(statistics: ProseStatistics(text: text ?? self.text), documentTitle: "On Rivers",
                        scopeLabel: "Whole document", content: content, date: date)
    }

    func testSummaryTSV() {
        let lines = table(.summary).tsv(decimalSeparator: ".").components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "Statistics: On Rivers")
        XCTAssertTrue(lines.contains("Document\tOn Rivers"))
        XCTAssertTrue(lines.contains("Words\t9"))
        XCTAssertTrue(lines.contains("Measure\tCount\tMean\tMin\tQ1\tMedian\tQ3\tMax\tRange\tIQR\tSD"))
        // Sentence lengths 3, 2, 4: mean 3, quartiles 2.5 / 3 / 3.5, SD √(2/3) ≈ 0.82.
        XCTAssertTrue(lines.contains("Sentence length (words)\t3\t3\t2\t2.5\t3\t3.5\t4\t2\t1\t0.82"))
        XCTAssertFalse(lines.contains("Most-used words"), "summary leaves out the other sections")
    }

    func testCommaDecimalRegions() {
        let t = table(.summary)
        XCTAssertTrue(t.tsv(decimalSeparator: ",").contains("\t2,5\t"))
        let csv = t.csv(decimalSeparator: ",")
        XCTAssertTrue(csv.contains("Sentence length (words);3;3;2;2,5;3;3,5;4;2;1;0,82"), "semicolons where commas are decimals")
    }

    func testCSVQuotesWhenNeeded() {
        let t = table(.sentences, text: "He said \"no\", twice. Fine.")
        let csv = t.csv(decimalSeparator: ".")
        XCTAssertTrue(csv.contains("#,Paragraph,Words,Sentence"))
        XCTAssertTrue(csv.contains("\"He said \"\"no\"\", twice.\""), csv)
        XCTAssertTrue(csv.contains("2,1,1,Fine."))
    }

    func testSentenceRowsCarryParagraphNumbers() {
        let rows = table(.sentences).sections.first?.rows ?? []
        XCTAssertEqual(rows.map { $0[1] }, [.integer(1), .integer(1), .integer(2)])
        XCTAssertEqual(rows.map { $0[2] }, [.integer(3), .integer(2), .integer(4)])
    }

    func testHTMLIsEscapedAndRightAlignsNumbers() {
        let html = StatisticsTable(statistics: ProseStatistics(text: text), documentTitle: "Cats & <Dogs>",
                                   scopeLabel: "Whole document", content: .summary, date: date).html(decimalSeparator: ".")
        XCTAssertTrue(html.contains("Statistics: Cats &amp; &lt;Dogs&gt;"))
        XCTAssertTrue(html.contains("text-align:right;\">9</td>"))
        XCTAssertEqual(html.components(separatedBy: "<table").count - 1, 2, "one table per section")
    }

    func testAllIncludesEverySection() {
        let titles = table(.all).sections.map(\.title)
        XCTAssertEqual(titles.count, 8)
        XCTAssertTrue(titles.contains("Sentence-length histogram"))
        XCTAssertTrue(titles.contains("Most-used words"))
        XCTAssertTrue(titles.contains("Longest sentences"))
    }

    func testDecimalFormatting() {
        XCTAssertEqual(StatisticsTable.decimal(3, separator: "."), "3")
        XCTAssertEqual(StatisticsTable.decimal(12.5, separator: "."), "12.5")
        XCTAssertEqual(StatisticsTable.decimal(2.0 / 3.0, separator: ","), "0,67")
        XCTAssertEqual(StatisticsTable.format(.percent(0.336), decimalSeparator: "."), "34%")
    }
}
