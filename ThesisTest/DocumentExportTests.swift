import XCTest
@testable import Thesis

final class DocumentExportTests: XCTestCase {

    private func sampleDocument() -> Document {
        let doc = Document(title: "On Rivers")
        doc.content = "Rivers carve valleys.\nThey also carry silt."
        doc.takeSnapshot(name: "First draft", note: "Got the idea down")
        doc.content = "Rivers carve valleys.\nThey carry silt to the sea."
        doc.addNote("cite this", category: .todo, range: NSRange(location: 0, length: 21))
        return doc
    }

    func testPlainTextIsTheTextAsWritten() {
        XCTAssertEqual(DocumentExport.plainText(sampleDocument()),
                       "Rivers carve valleys.\nThey carry silt to the sea.\n")
    }

    func testMarkdownHasTitleAndBlankLinesBetweenParagraphs() {
        XCTAssertEqual(DocumentExport.markdown(sampleDocument()),
                       "# On Rivers\n\nRivers carve valleys.\n\nThey carry silt to the sea.\n")
    }

    func testSuggestedFileNameIsSafe() {
        XCTAssertEqual(DocumentExport.suggestedFileName(title: "Draft 2/3: ideas", format: .pdf), "Draft 2-3- ideas.pdf")
        XCTAssertEqual(DocumentExport.suggestedFileName(title: "  ", format: .markdown), "Untitled.md")
    }

    func testExportFormatFromCommand() {
        XCTAssertEqual(ExportFormat(command: "MD"), .markdown)
        XCTAssertEqual(ExportFormat(command: "backup"), .archive)
        XCTAssertNil(ExportFormat(command: "docx"))
    }

    func testArchiveRoundTripKeepsEverything() throws {
        let doc = sampleDocument()
        let restored = try DocumentExport.documents(fromArchive: DocumentExport.archiveData([doc]))
        XCTAssertEqual(restored.count, 1)
        let copy = try XCTUnwrap(restored.first)
        XCTAssertEqual(copy.id, doc.id)
        XCTAssertEqual(copy.title, doc.title)
        XCTAssertEqual(copy.content, doc.content)
        // (Compared field by field: ISO 8601 dates drop fractions of a second.)
        XCTAssertEqual(copy.snapshots.map(\.id), doc.snapshots.map(\.id))
        XCTAssertEqual(copy.snapshots.map(\.content), doc.snapshots.map(\.content))
        XCTAssertEqual(copy.snapshots.map(\.name), ["First draft"])
        XCTAssertEqual(copy.notes.map(\.text), ["cite this"])
    }

    func testImportAcceptsTheAppsOwnLibraryFile() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let library = try encoder.encode([sampleDocument(), Document(title: "Second")])
        XCTAssertEqual(try DocumentExport.documents(fromArchive: library).map(\.title), ["On Rivers", "Second"])
    }

    func testImportRejectsOtherFiles() {
        XCTAssertThrowsError(try DocumentExport.documents(fromArchive: Data("{\"hello\": 1}".utf8)))
    }

    func testNewIdentityForKeepBoth() {
        let doc = Document()
        let original = doc.id
        doc.assignNewIdentity()
        XCTAssertNotEqual(doc.id, original)
    }
}
