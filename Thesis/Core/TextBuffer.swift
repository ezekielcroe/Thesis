// TextBuffer.swift — Thesis
// The editor engine edits text only through this protocol. In the app it is the
// NSTextView (so every edit is natively undoable); in tests it's a plain string.

import Foundation

protocol TextBuffer: AnyObject {
    var bufferText: String { get }
    /// The selection; the engine treats `location` as the cursor.
    var cursorRange: NSRange { get set }

    /// Replaces text as one undoable edit and puts the cursor after the replacement.
    func replaceText(in range: NSRange, with replacement: String)
    func undoEdit()
    func redoEdit()
    /// Ends the current run of typing, so the next undo stops here.
    func endTyping()
    /// Moves by one *displayed* line (wrapped lines count), like the arrow keys.
    func moveVisualLine(down: Bool)
    func revealCursor()
    /// Briefly flashes a range (yank, put, jump).
    func flash(_ range: NSRange)
    /// A persistent background highlight (visual selection, search preview). nil clears it.
    func setHighlight(_ range: NSRange?)
}
