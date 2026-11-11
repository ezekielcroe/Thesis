import XCTest
@testable import Thesis

final class DeliberateCutTests: XCTestCase {

    private func document(_ text: String) -> Document {
        let doc = Document()
        doc.content = text
        doc.takeSnapshot()
        return doc
    }

    func testCutIsKeptStraightAway() {
        let doc = document("Keep this. The anecdote about my uncle.")
        doc.recordCut("The anecdote about my uncle.")
        XCTAssertEqual(doc.darlings.map(\.text), ["The anecdote about my uncle."])
        XCTAssertEqual(doc.darlings.first?.isPending, true)
    }

    func testShortCutsAreIgnored() {
        let doc = document("Keep this.")
        doc.recordCut("quick")
        doc.recordCut("very quick")
        XCTAssertTrue(doc.darlings.isEmpty)
        doc.recordCut("a very quick")       // three words: a clause-sized cut
        XCTAssertEqual(doc.darlings.count, 1)
    }

    func testMovedTextIsNotADarling() {
        let doc = document("First idea here. Second idea here. Third idea here.")
        doc.recordCut("Second idea here.")
        doc.content = "First idea here. Third idea here. Second idea here."    // cut, then put elsewhere
        doc.takeSnapshot()
        XCTAssertTrue(doc.darlings.isEmpty)
    }

    func testUndoneCutIsDroppedEvenWithoutANewSnapshot() {
        let doc = document("First idea here. Second idea here.")
        doc.recordCut("Second idea here.")
        XCTAssertNil(doc.takeSnapshot(), "text is unchanged, so no snapshot")
        XCTAssertTrue(doc.darlings.isEmpty)
    }

    func testConfirmedCutIsNotDuplicatedBySnapshotComparison() {
        let doc = document("First idea here. Second idea here. Third idea here.")
        doc.recordCut("Second idea here.")
        doc.content = "First idea here. Third idea here."
        doc.takeSnapshot()
        XCTAssertEqual(doc.darlings.map(\.text), ["Second idea here."])
        XCTAssertEqual(doc.darlings.first?.isPending, false)
    }

    func testTextWrittenAndCutBetweenSnapshotsIsKept() {
        let doc = document("First idea here.")
        // Written after the snapshot and cut before the next one: no snapshot ever held it.
        doc.recordCut("A thought I had and then dropped.")
        doc.content = "First idea here. Something else instead."
        doc.takeSnapshot()
        XCTAssertEqual(doc.darlings.map(\.text), ["A thought I had and then dropped."])
    }

    func testClauseCutInsideASentenceIsKept() {
        let doc = document("The river, which was very cold, ran on.")
        doc.recordCut("which was very cold,")
        doc.content = "The river, ran on."
        doc.takeSnapshot()
        XCTAssertEqual(doc.darlings.map(\.text), ["which was very cold,"])
    }

    func testReasonGivenInReviewReachesAnOnTheSpotDarling() {
        let doc = Document()
        doc.content = "Keep this. The anecdote about my uncle."
        doc.takeSnapshot(name: "v1")
        doc.recordCut("The anecdote about my uncle.")
        doc.content = "Keep this."
        let change = doc.changesSinceLastNamedSnapshot()[0]
        doc.setReason("Off topic", for: change.fingerprint)
        doc.takeSnapshot()
        XCTAssertEqual(doc.darlings.count, 1)
        XCTAssertEqual(doc.reason(for: doc.darlings[0].fingerprint), "Off topic")
    }
}

final class LibraryTests: XCTestCase {

    private var shelf: LibraryGroup!
    private var novel: LibraryGroup!
    private var loose: LibraryGroup!
    private var groups: [LibraryGroup] = []
    private var documents: [Document] = []

    private func doc(_ title: String, in group: LibraryGroup? = nil, text: String = "Text.") -> Document {
        let d = Document(title: title)
        d.content = text
        d.groupID = group?.id
        return d
    }

    override func setUp() {
        shelf = LibraryGroup(name: "Fiction", kind: .shelf)
        novel = LibraryGroup(name: "The Novel", kind: .project, parentID: shelf.id)
        loose = LibraryGroup(name: "Essays", kind: .project)
        groups = [shelf, novel, loose]
        documents = [
            doc("Scratch"),
            doc("Chapter One", in: novel, text: "It began.\nIt went on."),
            doc("Chapter Two", in: novel),
            doc("Ideas", in: shelf),
            doc("On Rivers", in: loose),
        ]
    }

    private func titles(_ rows: [Library.Row]) -> [String] {
        rows.map {
            switch $0 {
            case .group(let g, let depth): return String(repeating: "  ", count: depth) + "[\(g.name)]"
            case .document(let d, let depth): return String(repeating: "  ", count: depth) + d.title
            }
        }
    }

    func testRowsFollowTheThreeLevels() {
        XCTAssertEqual(titles(Library.rows(documents: documents, groups: groups)), [
            "[Fiction]",
            "  [The Novel]",
            "    Chapter One",
            "    Chapter Two",
            "  Ideas",
            "[Essays]",
            "  On Rivers",
            "Scratch",
        ])
    }

    func testCollapsedGroupsHideTheirContents() {
        groups[0].isCollapsed = true
        XCTAssertEqual(titles(Library.rows(documents: documents, groups: groups)),
                       ["[Fiction]", "[Essays]", "  On Rivers", "Scratch"])
    }

    func testShelvesAreAlwaysTopLevelAndOrphansSurface() {
        XCTAssertNil(LibraryGroup(name: "S", kind: .shelf, parentID: UUID()).parentID)
        // A document or project whose group is gone shows at the top level rather than vanishing.
        let withoutShelf = groups.filter { $0.id != shelf.id }
        XCTAssertEqual(titles(Library.rows(documents: documents, groups: withoutShelf)), [
            "[The Novel]", "  Chapter One", "  Chapter Two", "[Essays]", "  On Rivers", "Scratch", "Ideas",
        ])
    }

    func testDestinationsAndCounts() {
        XCTAssertEqual(Library.destinations(groups).map(\.title), ["Fiction", "Fiction ▸ The Novel", "Essays"])
        XCTAssertEqual(Library.allDocuments(in: shelf, documents: documents, groups: groups).count, 3)
    }

    func testExportingAShelfKeepsItsStructure() {
        let export = Library.export(shelf, documents: documents, groups: groups, format: .markdown)
        XCTAssertEqual(export.folderName, "Fiction")
        XCTAssertEqual(export.directories, ["The Novel"])
        XCTAssertEqual(export.files.map(\.path), [
            "The Novel/01 Chapter One.md",
            "The Novel/02 Chapter Two.md",
            "01 Ideas.md",
        ])
        XCTAssertEqual(export.files.first?.contents, "# Chapter One\n\nIt began.\n\nIt went on.\n")
    }

    func testExportingAProjectAsText() {
        let export = Library.export(novel, documents: documents, groups: groups, format: .plainText)
        XCTAssertEqual(export.folderName, "The Novel")
        XCTAssertTrue(export.directories.isEmpty)
        XCTAssertEqual(export.files.map(\.path), ["01 Chapter One.txt", "02 Chapter Two.txt"])
        XCTAssertEqual(export.files.first?.contents, "It began.\nIt went on.\n")
    }

    func testLibraryBackupKeepsGroups() throws {
        let data = try DocumentExport.archiveData(documents, groups: groups)
        let restored = try DocumentExport.library(fromArchive: data)
        XCTAssertEqual(restored.groups, groups)
        XCTAssertEqual(restored.documents.map(\.groupID), documents.map(\.groupID))
    }
}
