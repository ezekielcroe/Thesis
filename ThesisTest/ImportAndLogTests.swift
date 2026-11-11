import XCTest
@testable import Thesis

final class DocumentImportTests: XCTestCase {

    func testHardWrappedParagraphsAreJoined() {
        let text = "This paragraph was\nwrapped at a fixed\nwidth.\n\nSecond paragraph\ncontinues here."
        XCTAssertEqual(DocumentImport.unwrapHardWrappedLines(text),
                       "This paragraph was wrapped at a fixed width.\n\nSecond paragraph continues here.")
    }

    func testOneLinePerParagraphTextIsLeftAlone() {
        let text = "First paragraph.\nSecond paragraph.\nThird."
        XCTAssertEqual(DocumentImport.unwrapHardWrappedLines(text), text)
    }

    func testStructureIsKept() {
        let text = """
        Intro line one
        and two.

        - item one
          continues
        - item two

        > quoted line
        > goes on

        ```
        code stays
        as is
        ```
        Ends with a break.\u{20}\u{20}
        Next line.
        """
        XCTAssertEqual(DocumentImport.unwrapHardWrappedLines(text), """
        Intro line one and two.

        - item one continues
        - item two

        > quoted line goes on

        ```
        code stays
        as is
        ```
        Ends with a break.\u{20}\u{20}
        Next line.
        """)
    }

    func testMarkdownTitleAndLineEndings() {
        let raw = "\u{FEFF}# On Rivers\r\n\r\nRivers carve\r\nvalleys.\r\n\r\nThey carry\r\nsilt.\r\n"
        let prepared = DocumentImport.prepare(raw, isMarkdown: true, fallbackTitle: "rivers")
        XCTAssertEqual(prepared, DocumentImport.Prepared(title: "On Rivers",
                                                         content: "Rivers carve valleys.\n\nThey carry silt."))
    }

    func testBlankLineOnlyAfterTitleIsNotHardWrapping() {
        let prepared = DocumentImport.prepare("# Notes\n\nFirst paragraph.\nSecond paragraph.",
                                              isMarkdown: true, fallbackTitle: "x")
        XCTAssertEqual(prepared.content, "First paragraph.\nSecond paragraph.")
    }

    func testRichTextIsNeverUnwrapped() {
        let prepared = DocumentImport.prepare("One.\n\nTwo.\nThree.", isMarkdown: true, fallbackTitle: "x", unwrap: false)
        XCTAssertEqual(prepared.content, "One.\n\nTwo.\nThree.")
    }

    func testPlainTextKeepsFileNameAsTitle() {
        let prepared = DocumentImport.prepare("# not a title in .txt", isMarkdown: false, fallbackTitle: "notes")
        XCTAssertEqual(prepared.title, "notes")
        XCTAssertEqual(DocumentImport.title(fromFileName: "Chapter 1.docx"), "Chapter 1")
    }

    func testOurOwnMarkdownExportRoundTrips() {
        let doc = Document(title: "On Rivers")
        doc.content = "Rivers carve valleys.\nThey carry silt."
        let prepared = DocumentImport.prepare(DocumentExport.markdown(doc), isMarkdown: true, fallbackTitle: "x")
        XCTAssertEqual(prepared.title, "On Rivers")
        XCTAssertEqual(prepared.content, "Rivers carve valleys.\n\nThey carry silt.")
    }
}

final class EvolutionReportTests: XCTestCase {

    private func sampleDocument() -> Document {
        let doc = Document(title: "On Rivers")
        doc.content = "Rivers carve valleys. The anecdote about my uncle. They carry silt."
        doc.takeSnapshot(name: "First draft", note: "Got it down")
        doc.content = "Rivers slowly carve valleys. They carry silt."
        for change in doc.changesSinceLastNamedSnapshot() where change.kind == .cut {
            doc.setReason("Off topic", for: change.fingerprint)
        }
        doc.takeSnapshot(name: "Second draft")
        doc.addNote("cite this", category: .todo, range: NSRange(location: 0, length: 6))
        return doc
    }

    func testReportStructure() {
        let report = EvolutionReport.markdown(for: sampleDocument())
        XCTAssertTrue(report.hasPrefix("# Evolution of “On Rivers”"))
        for heading in ["## Summary", "## Timeline", "### 1. First draft", "### 2. Second draft", "## Darlings", "## Notes"] {
            XCTAssertTrue(report.contains(heading), "missing \(heading)")
        }
        XCTAssertTrue(report.contains("> Got it down"))
        XCTAssertTrue(report.contains("The starting point: 11 words."))
    }

    func testChangesReasonsAndDarlings() {
        let report = EvolutionReport.markdown(for: sampleDocument())
        XCTAssertTrue(report.contains("- **Cut:** ~~The anecdote about my uncle.~~\n    - *Why:* Off topic"), report)
        XCTAssertTrue(report.contains("**Reworded:** Rivers **slowly** carve valleys."), report)
        XCTAssertTrue(report.contains("- “The anecdote about my uncle.”"))
        XCTAssertTrue(report.contains("- **To do** on “Rivers”: cite this"))
    }

    func testWrapKeepsSpacesOutsideMarkers() {
        XCTAssertEqual(EvolutionReport.wrap("word ", "**"), "**word** ")
        XCTAssertEqual(EvolutionReport.wrap(" ", "**"), " ")
        XCTAssertEqual(EvolutionReport.oneLine("one\ntwo\n\nthree"), "one ¶ two ¶ three")
    }

    func testEmptyHistory() {
        let report = EvolutionReport.markdown(for: Document(title: "New"))
        XCTAssertTrue(report.contains("No named snapshots yet."))
        XCTAssertFalse(report.contains("## Timeline"))
    }
}
