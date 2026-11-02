import XCTest
@testable import Thesis

final class ProseDiffTests: XCTestCase {

    func testIdenticalTextHasNoChanges() {
        XCTAssertTrue(ProseDiff.changes(from: "The cat sat. The dog ran.", to: "The cat sat. The dog ran.").isEmpty)
    }

    func testRespacingIsNotAChange() {
        XCTAssertTrue(ProseDiff.changes(from: "The cat sat.  The dog ran.", to: "The cat sat. The dog ran.").isEmpty)
    }

    func testAddedSentence() {
        let changes = ProseDiff.changes(from: "The cat sat.", to: "The cat sat. The dog ran.")
        XCTAssertEqual(changes.map(\.kind), [.added])
        XCTAssertEqual(changes.first?.after, "The dog ran.")
        XCTAssertNil(changes.first?.before)
    }

    func testCutSentence() {
        let changes = ProseDiff.changes(from: "The cat sat. The dog ran. The bird flew.",
                                        to: "The cat sat. The bird flew.")
        XCTAssertEqual(changes.map(\.kind), [.cut])
        XCTAssertEqual(changes.first?.before, "The dog ran.")
        XCTAssertEqual(changes.first?.lostText, "The dog ran.")
    }

    func testRewordedSentence() {
        let changes = ProseDiff.changes(from: "Intro here. The cat sat on the mat.",
                                        to: "Intro here. The cat sat quietly on the mat.")
        XCTAssertEqual(changes.map(\.kind), [.reworded])
        XCTAssertEqual(changes.first?.before, "The cat sat on the mat.")
        XCTAssertEqual(changes.first?.after, "The cat sat quietly on the mat.")
        XCTAssertNil(changes.first?.lostText, "a rewording isn't a darling")
    }

    func testRewrittenSentence() {
        let changes = ProseDiff.changes(from: "Rain fell all day. We stayed inside.",
                                        to: "Rain fell all day. Nobody wanted to leave the house.")
        XCTAssertEqual(changes.map(\.kind), [.rewritten])
        XCTAssertEqual(changes.first?.lostText, "We stayed inside.")
    }

    func testMovedSentence() {
        let changes = ProseDiff.changes(from: "First point. Second point. Third point.",
                                        to: "Second point. First point. Third point.")
        XCTAssertEqual(changes.map(\.kind), [.moved])
    }

    func testMovedParagraphIsOneChange() {
        let old = "Alpha one. Alpha two.\nBeta one. Beta two.\nGamma one."
        let new = "Beta one. Beta two.\nAlpha one. Alpha two.\nGamma one."
        let changes = ProseDiff.changes(from: old, to: new)
        XCTAssertEqual(changes.map(\.kind), [.moved])
    }

    func testAdjacentAdditionsAreGrouped() {
        let changes = ProseDiff.changes(from: "Intro.", to: "Intro. One more. And another.")
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.kind, .added)
        XCTAssertEqual(changes.first?.after, "One more. And another.")
    }

    func testChangesAreInDocumentOrder() {
        let changes = ProseDiff.changes(from: "A cat. B dog. C bird.",
                                        to: "New start. A cat. C bird. New end.")
        XCTAssertEqual(changes.map(\.kind), [.added, .cut, .added])
    }

    func testFingerprintIsStableAndKindSpecific() {
        let a = ProseDiff.changes(from: "Keep this. Lose this.", to: "Keep this.")
        let b = ProseDiff.changes(from: "Keep this. Lose this.", to: "Keep this.")
        XCTAssertEqual(a.first?.fingerprint, b.first?.fingerprint)
        XCTAssertNotEqual(ProseDiff.fingerprint(kind: .cut, before: "x", after: nil),
                          ProseDiff.fingerprint(kind: .added, before: nil, after: "x"))
    }

    func testWordDiff() {
        let parts = ProseDiff.wordDiff(from: "the cat sat", to: "the big cat sat")
        XCTAssertEqual(parts, [
            WordDiffPart(kind: .same, text: "the "),
            WordDiffPart(kind: .added, text: "big "),
            WordDiffPart(kind: .same, text: "cat sat"),
        ])
    }

    func testEmojiDoesNotBreakRanges() {
        let changes = ProseDiff.changes(from: "😀 One. Two.", to: "😀 One. Two. Three.")
        XCTAssertEqual(changes.first?.after, "Three.")
        XCTAssertEqual(changes.first?.location, ("😀 One. Two. " as NSString).length)
    }
}
