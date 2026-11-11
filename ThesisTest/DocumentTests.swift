import XCTest
@testable import Thesis

final class NoteAnchorTests: XCTestCase {
    private let span = NSRange(location: 10, length: 5)   // [10, 15)

    func testEditBeforeShifts() {
        XCTAssertEqual(NoteAnchor.adjust(span, editLocation: 2, removed: 0, inserted: 3), NSRange(location: 13, length: 5))
        XCTAssertEqual(NoteAnchor.adjust(span, editLocation: 2, removed: 4, inserted: 0), NSRange(location: 6, length: 5))
    }

    func testEditAfterLeavesAlone() {
        XCTAssertEqual(NoteAnchor.adjust(span, editLocation: 20, removed: 2, inserted: 9), span)
    }

    func testTypingAtEitherEdgeDoesNotJoin() {
        XCTAssertEqual(NoteAnchor.adjust(span, editLocation: 10, removed: 0, inserted: 2), NSRange(location: 12, length: 5))
        XCTAssertEqual(NoteAnchor.adjust(span, editLocation: 15, removed: 0, inserted: 2), span)
    }

    func testTypingInsideGrows() {
        XCTAssertEqual(NoteAnchor.adjust(span, editLocation: 12, removed: 0, inserted: 4), NSRange(location: 10, length: 9))
    }

    func testDeletingOverlapTrims() {
        XCTAssertEqual(NoteAnchor.adjust(span, editLocation: 8, removed: 4, inserted: 0), NSRange(location: 8, length: 3))
    }

    func testDeletingAllDetaches() {
        XCTAssertEqual(NoteAnchor.adjust(span, editLocation: 10, removed: 5, inserted: 0).length, 0)
    }
}

final class DocumentTests: XCTestCase {

    func testAutomaticSnapshotSkipsUnchangedText() {
        let doc = Document()
        doc.content = "Hello."
        XCTAssertNotNil(doc.takeSnapshot())
        XCTAssertNil(doc.takeSnapshot())
        XCTAssertEqual(doc.snapshots.count, 1)
    }

    func testNamingUnchangedAutomaticSnapshotPromotesIt() {
        let doc = Document()
        doc.content = "Hello."
        doc.takeSnapshot()
        doc.takeSnapshot(name: "First draft", note: "Got it down")
        XCTAssertEqual(doc.snapshots.count, 1)
        XCTAssertEqual(doc.latestNamedSnapshot?.name, "First draft")
    }

    func testCutTextBecomesADarling() {
        let doc = Document()
        doc.content = "Keep this. Cut me."
        doc.takeSnapshot()
        doc.content = "Keep this."
        doc.takeSnapshot()
        XCTAssertEqual(doc.darlings.map(\.text), ["Cut me."])
    }

    func testReasonFollowsTheChange() {
        let doc = Document()
        doc.content = "Keep this. Cut me."
        doc.takeSnapshot(name: "v1")
        doc.content = "Keep this."
        let change = doc.changesSinceLastNamedSnapshot()[0]
        doc.setReason("It repeated the intro", for: change.fingerprint)
        doc.takeSnapshot()
        XCTAssertEqual(doc.reason(for: doc.darlings[0].fingerprint), "It repeated the intro")
    }

    func testNotesFollowEdits() {
        let doc = Document()
        doc.content = "One. Two."
        doc.addNote("check", category: .question, range: NSRange(location: 5, length: 4))
        doc.content = "Hey. One. Two."
        doc.applyEdit(location: 0, removed: 0, inserted: 5, newText: doc.content)
        XCTAssertEqual(doc.notes[0].range, NSRange(location: 10, length: 4))
    }

    func testNotesSurviveWholeTextReplacement() {
        let doc = Document()
        doc.content = "One. Two."
        doc.addNote("check", category: .note, range: NSRange(location: 5, length: 4))
        let restored = "Zero. One. Two. Three."
        doc.content = restored
        doc.applyEdit(location: 0, removed: 9, inserted: restored.utf16Length, newText: restored)
        XCTAssertEqual(doc.notes[0].range, NSRange(location: 11, length: 4))
    }

    /// Files written by the previous version (branches, drafts, annotations) still open.
    func testLoadsPreviousVersionFormat() throws {
        let json = """
        {"id":"8C1B6B8E-6B1E-4C3B-9C2F-1D2E3F4A5B6C","title":"Old","currentContent":"Alpha. Beta.",
         "drafts":[{"id":"1C1B6B8E-6B1E-4C3B-9C2F-1D2E3F4A5B6C","name":"First","content":"Alpha. Gamma.",
                    "timestamp":"2026-01-01T10:00:00Z","comment":"Initial capture","branchName":"main",
                    "isFirstDraft":true,"changes":[]},
                   {"id":"2C1B6B8E-6B1E-4C3B-9C2F-1D2E3F4A5B6C","name":"Second","content":"Alpha.",
                    "timestamp":"2026-01-02T10:00:00Z","comment":"","branchName":"main",
                    "isFirstDraft":false,"changes":[]}],
         "branches":[],"activeBranchName":"main","workingDraft":null,"lastModified":"2026-01-02T10:00:00Z",
         "annotations":[{"id":"3C1B6B8E-6B1E-4C3B-9C2F-1D2E3F4A5B6C","text":"check","anchorText":"Beta.",
                         "anchorPosition":7,"category":"fix","resolved":false,
                         "createdAt":"2026-01-01T10:00:00Z","updatedAt":"2026-01-01T10:00:00Z"}],
         "sessionChanges":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(Document.self, from: Data(json.utf8))
        XCTAssertEqual(doc.content, "Alpha. Beta.")
        XCTAssertEqual(doc.snapshots.map(\.name), ["First", "Second"])
        XCTAssertEqual(doc.snapshots.first?.note, "Initial capture")
        XCTAssertEqual(doc.darlings.map(\.text), ["Gamma."], "darlings are rebuilt from the old drafts")
        XCTAssertEqual(doc.notes.first?.category, .todo)
        XCTAssertEqual(doc.notes.first?.range, NSRange(location: 7, length: 5))

        // And it round-trips in the new format.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let again = try decoder.decode(Document.self, from: try encoder.encode(doc))
        XCTAssertEqual(again.content, doc.content)
        XCTAssertEqual(again.snapshots, doc.snapshots)
        XCTAssertEqual(again.notes.first?.range, NSRange(location: 7, length: 5))
    }
}
