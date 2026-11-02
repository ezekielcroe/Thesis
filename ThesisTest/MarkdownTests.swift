import XCTest
@testable import Thesis

final class MarkdownSourceTests: XCTestCase {

    func testLineKinds() {
        XCTAssertEqual(MarkdownSource.kind(of: "## Heading"), .heading)
        XCTAssertEqual(MarkdownSource.kind(of: "#hashtag"), .text)
        XCTAssertEqual(MarkdownSource.kind(of: "- item"), .listItem)
        XCTAssertEqual(MarkdownSource.kind(of: "  12. item"), .listItem)
        XCTAssertEqual(MarkdownSource.kind(of: "-not a list"), .text)
        XCTAssertEqual(MarkdownSource.kind(of: "> quoted"), .quote)
        XCTAssertEqual(MarkdownSource.kind(of: "```swift"), .fence)
        XCTAssertEqual(MarkdownSource.kind(of: "| a | b |"), .table)
        XCTAssertEqual(MarkdownSource.kind(of: "   "), .blank)
    }

    func testEachLineBecomesAParagraph() {
        XCTAssertEqual(MarkdownSource.normalizedForRendering("One.\nTwo."), "One.\n\nTwo.")
    }

    func testListsTablesAndCodeStayTogether() {
        let text = "Intro.\n- a\n- b\nAfter.\n```\nx = 1\ny = 2\n```\n| h |\n| - |"
        XCTAssertEqual(MarkdownSource.normalizedForRendering(text),
                       "Intro.\n\n- a\n- b\n\nAfter.\n```\nx = 1\ny = 2\n```\n| h |\n| - |")
    }

    func testQuoteLinesStayInOneQuote() {
        XCTAssertEqual(MarkdownSource.normalizedForRendering("> one\n> two"), "> one\n>\n> two")
    }

    func testAlreadySeparatedTextIsUnchanged() {
        XCTAssertEqual(MarkdownSource.normalizedForRendering("One.\n\nTwo."), "One.\n\nTwo.")
    }
}

/// Checks the renderer's reading of Foundation's Markdown parser: the visible text,
/// with markers removed and block separators in the right places.
final class MarkdownRendererTests: XCTestCase {

    private func rendered(_ markdown: String) -> NSAttributedString {
        MarkdownRenderer.render(title: nil, markdown: markdown, style: .print)
    }

    func testInlineMarkersAreRemoved() {
        XCTAssertEqual(rendered("Some **bold** and *italic* and `code`.").string,
                       "Some bold and italic and code.")
    }

    func testParagraphsAndHeadings() {
        XCTAssertEqual(rendered("# Title\nFirst para.\nSecond para.").string,
                       "Title\nFirst para.\nSecond para.")
    }

    func testLists() {
        XCTAssertEqual(rendered("- one\n- two").string, "•\tone\n•\ttwo")
        XCTAssertEqual(rendered("1. one\n2. two").string, "1.\tone\n2.\ttwo")
    }

    func testBoldIsBold() {
        let text = rendered("Some **bold** text.")
        let location = (text.string as NSString).range(of: "bold").location
        let font = text.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    func testLinksAreClickable() {
        let text = rendered("See [the site](https://example.com).")
        let location = (text.string as NSString).range(of: "the site").location
        XCTAssertEqual(text.attribute(.link, at: location, effectiveRange: nil) as? URL,
                       URL(string: "https://example.com"))
    }

    func testTitleComesFirst() {
        let text = MarkdownRenderer.render(title: "On Rivers", markdown: "Body.", style: .print)
        XCTAssertEqual(text.string, "On Rivers\nBody.")
    }
}
