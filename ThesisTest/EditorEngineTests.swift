import XCTest
@testable import Thesis

/// A plain-string stand-in for the NSTextView.
final class TestBuffer: TextBuffer {
    var bufferText: String
    var cursorRange = NSRange(location: 0, length: 0)
    var highlight: NSRange?
    var onChange: (() -> Void)?
    private var undoStack: [(String, NSRange)] = []
    private var redoStack: [(String, NSRange)] = []

    init(_ text: String) { bufferText = text }

    func replaceText(in range: NSRange, with replacement: String) {
        undoStack.append((bufferText, cursorRange))
        redoStack.removeAll()
        bufferText = (bufferText as NSString).replacingCharacters(in: range, with: replacement)
        cursorRange = NSRange(location: range.location + replacement.utf16Length, length: 0)
        onChange?()
    }

    func undoEdit() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append((bufferText, cursorRange))
        bufferText = last.0
        cursorRange = last.1
        onChange?()
    }

    func redoEdit() {
        guard let last = redoStack.popLast() else { return }
        undoStack.append((bufferText, cursorRange))
        bufferText = last.0
        cursorRange = last.1
        onChange?()
    }

    /// What typing in Insert mode does.
    func type(_ s: String) { replaceText(in: cursorRange, with: s) }

    func endTyping() {}
    func moveVisualLine(down: Bool) {}
    func revealCursor() {}
    func focus() {}
    func flash(_ range: NSRange) {}
    func setHighlight(_ range: NSRange?) { highlight = range }
}

final class EditorEngineTests: XCTestCase {
    private var buffer: TestBuffer!
    private var engine: EditorEngine!

    private func load(_ text: String, cursor: Int = 0) {
        let doc = Document()
        doc.content = text
        engine = EditorEngine(document: doc)
        buffer = TestBuffer(text)
        buffer.cursorRange = NSRange(location: cursor, length: 0)
        buffer.onChange = { [unowned self] in self.engine.textDidChange() }
        engine.attach(buffer)
    }

    private func press(_ keys: String) {
        for c in keys { engine.handle(.char(c)) }
    }

    private var cursor: Int { buffer.cursorRange.location }

    // MARK: Motions

    func testSentenceMotions() {
        load("One. Two. Three.")
        press("l"); XCTAssertEqual(cursor, 5)
        press("l"); XCTAssertEqual(cursor, 10)
        press("h"); XCTAssertEqual(cursor, 5)
        press("gg"); XCTAssertEqual(cursor, 0)
        press("G"); XCTAssertEqual(cursor, 16)
    }

    func testParagraphMotions() {
        load("First para.\n\nSecond para.\nThird.")
        press("j"); XCTAssertEqual(cursor, 13)
        press("j"); XCTAssertEqual(cursor, 26)
        press("k"); XCTAssertEqual(cursor, 13)
    }

    // MARK: Operators

    func testDeleteSentence() {
        load("One. Two. Three.", cursor: 5)
        press("ds")
        XCTAssertEqual(buffer.bufferText, "One. Three.")
        XCTAssertEqual(engine.register, Register(text: "Two.", kind: .sentence))
    }

    func testDeleteLastSentenceTakesPrecedingSpace() {
        load("One. Two.", cursor: 6)
        press("ds")
        XCTAssertEqual(buffer.bufferText, "One.")
    }

    func testDeleteOnlySentenceRemovesItsParagraph() {
        load("Alone.\nNext para.", cursor: 0)
        press("ds")
        XCTAssertEqual(buffer.bufferText, "Next para.")
    }

    func testDeleteWord() {
        load("The quick fox.", cursor: 4)
        press("dw")
        XCTAssertEqual(buffer.bufferText, "The fox.")
    }

    func testDeleteClause() {
        load("First part, second part.", cursor: 12)
        press("dc")
        XCTAssertEqual(buffer.bufferText, "First part,")
    }

    func testChangeSentenceAndRepeat() {
        load("One. Two. Three.", cursor: 5)
        press("cs")
        XCTAssertEqual(engine.mode, .insert)
        buffer.type("Deux.")
        engine.handle(.escape)
        XCTAssertEqual(buffer.bufferText, "One. Deux. Three.")
        XCTAssertEqual(engine.mode, .normal)

        buffer.cursorRange = NSRange(location: 11, length: 0)
        press(".")
        XCTAssertEqual(buffer.bufferText, "One. Deux. Deux.")
    }

    func testInsertModeAllowsFreeEditing() {
        load("One. Three.", cursor: 0)
        press("a")
        buffer.type("Too.")
        buffer.cursorRange = NSRange(location: 6, length: 0)      // click back into the word…
        buffer.replaceText(in: NSRange(location: 6, length: 2), with: "wo")   // …and fix a typo
        engine.handle(.escape)
        XCTAssertEqual(buffer.bufferText, "One. Two. Three.")
    }

    func testAppendWithoutTypingLeavesTextUnchanged() {
        load("One. Three.", cursor: 0)
        press("a")
        engine.handle(.escape)
        XCTAssertEqual(buffer.bufferText, "One. Three.")
    }

    func testOpenParagraphBelow() {
        load("First.\nSecond.", cursor: 0)
        press("o")
        buffer.type("Middle.")
        engine.handle(.escape)
        XCTAssertEqual(buffer.bufferText, "First.\nMiddle.\nSecond.")
    }

    // MARK: Moving text = cut + put

    func testMoveSentenceWithDeleteAndPut() {
        load("A one. B two. C three.", cursor: 7)
        press("ds")
        XCTAssertEqual(buffer.bufferText, "A one. C three.")
        press("p")
        XCTAssertEqual(buffer.bufferText, "A one. C three. B two.")
    }

    func testMoveParagraphWithDeleteAndPut() {
        load("Para one.\nPara two.", cursor: 0)
        press("dp")
        XCTAssertEqual(buffer.bufferText, "Para two.")
        press("p")
        XCTAssertEqual(buffer.bufferText, "Para two.\nPara one.")
    }

    // MARK: Visual

    func testVisualSelectsWholeSentences() {
        load("One. Two. Three.", cursor: 2)
        press("v")
        XCTAssertEqual(buffer.highlight, NSRange(location: 0, length: 4))
        press("l")
        XCTAssertEqual(buffer.highlight, NSRange(location: 0, length: 9))
        press("d")
        XCTAssertEqual(buffer.bufferText, "Three.")
        XCTAssertEqual(engine.mode, .normal)
    }

    // MARK: Undo, emoji, commands

    func testUndoRedo() {
        load("One. Two. Three.", cursor: 5)
        press("ds")
        press("u")
        XCTAssertEqual(buffer.bufferText, "One. Two. Three.")
        engine.handle(.ctrl("r"))
        XCTAssertEqual(buffer.bufferText, "One. Three.")
    }

    func testEmojiSafeDeletion() {
        let text = "😀 One. Two."
        load(text, cursor: (text as NSString).range(of: "Two").location)
        press("ds")
        XCTAssertEqual(buffer.bufferText, "😀 One.")
    }

    func testCommandLineOpensReview() {
        load("Some text.")
        press(":w")
        engine.handle(.enter)
        if case .review? = engine.activeSheet {} else { XCTFail("expected the review sheet") }
    }

    func testNamedSnapshotFromCommandLine() {
        load("Some text.")
        press(":w first draft")
        engine.handle(.enter)
        XCTAssertEqual(engine.document.latestNamedSnapshot?.name, "first draft")
    }

    func testSearch() {
        load("Alpha beta. Gamma beta.")
        press("/beta")
        engine.handle(.enter)
        XCTAssertEqual(cursor, 6)
        press("n")
        XCTAssertEqual(cursor, 18)
        press("n")
        XCTAssertEqual(cursor, 6, "wraps around")
    }

    func testFindWordMatchesWholeWordsOnly() {
        load("There is the cat. Then the dog.")
        engine.findWord("the")
        XCTAssertEqual(cursor, 9)
        press("n")
        XCTAssertEqual(cursor, 23, "skips “Then”")
        press("n")
        XCTAssertEqual(cursor, 9, "wraps around, skipping “There”")
    }

    func testStatisticsCaptureVisualSelection() {
        load("One. Two. Three.", cursor: 0)
        press("vl")
        engine.openStatistics()
        guard case .statistics(let context)? = engine.activeSheet else { return XCTFail("expected statistics") }
        XCTAssertEqual(context.selection, NSRange(location: 0, length: 9))
        XCTAssertEqual(context.paragraph, NSRange(location: 0, length: 16))
    }

    func testExportCommands() {
        load("Some text.")
        press(":export pdf"); engine.handle(.enter)
        XCTAssertEqual(engine.exportRequest, .document(.pdf))
        press(":export log"); engine.handle(.enter)
        XCTAssertEqual(engine.exportRequest, .log(.markdown))
        press(":export log docx"); engine.handle(.enter)
        XCTAssertEqual(engine.exportRequest, .log(.word))
    }

    // MARK: Mouse selection

    private func select(_ range: NSRange) {
        buffer.cursorRange = range
        engine.userSelected(range)
    }

    func testMouseSelectionEntersVisualModeWithExactlyThatText() {
        load("The quick fox.")
        select(NSRange(location: 5, length: 3))            // "uic", inside a word
        XCTAssertEqual(engine.mode, .visual)
        XCTAssertEqual(buffer.highlight, NSRange(location: 5, length: 3))
        press("d")
        XCTAssertEqual(buffer.bufferText, "The qk fox.")
        XCTAssertEqual(engine.mode, .normal)
    }

    func testSelectingAWholeWordOrSentenceTidiesSpacing() {
        load("The quick fox.")
        select(NSRange(location: 4, length: 5))            // "quick"
        press("d")
        XCTAssertEqual(buffer.bufferText, "The fox.")

        load("One. Two. Three.")
        select(NSRange(location: 5, length: 4))            // "Two."
        press("d")
        XCTAssertEqual(buffer.bufferText, "One. Three.")
        XCTAssertEqual(engine.register, Register(text: "Two.", kind: .sentence))
    }

    func testClickCancelsAMouseSelection() {
        load("One. Two. Three.")
        select(NSRange(location: 5, length: 3))
        select(NSRange(location: 12, length: 0))           // a plain click
        XCTAssertEqual(engine.mode, .normal)
        XCTAssertNil(buffer.highlight)
        XCTAssertEqual(cursor, 12)
    }

    func testMotionAfterMouseSelectionSnapsToWholeUnits() {
        load("One. Two. Three.")
        select(NSRange(location: 5, length: 3))            // "Two"
        press("l")
        XCTAssertEqual(buffer.highlight, NSRange(location: 5, length: 11))   // "Two. Three."
    }

    func testEscapeDropsTheSelection() {
        load("One. Two. Three.")
        select(NSRange(location: 5, length: 3))
        engine.handle(.escape)
        XCTAssertEqual(engine.mode, .normal)
        XCTAssertEqual(buffer.cursorRange, NSRange(location: 5, length: 0))
    }

    func testSelectionInInsertModeIsLeftAlone() {
        load("One. Two.")
        press("i")
        select(NSRange(location: 0, length: 4))
        XCTAssertEqual(engine.mode, .insert)
    }

    func testDeletingASentenceRecordsACut() {
        load("First idea here. Second idea here.", cursor: 17)
        press("ds")
        XCTAssertEqual(engine.document.darlings.map(\.text), ["Second idea here."])
        load("The quick fox.", cursor: 4)
        press("dw")
        XCTAssertTrue(engine.document.darlings.isEmpty, "a single word isn't a darling")
    }
}
