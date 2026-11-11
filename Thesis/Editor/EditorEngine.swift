// EditorEngine.swift — Thesis
// The modal editing grammar. Platform-independent: it edits text only through
// `TextBuffer`, so it can be tested without AppKit.
//
// Three ways of being in the text:
//   NORMAL — move and act on units of prose (words, clauses, sentences, paragraphs)
//   INSERT — write. Ordinary typing: arrows, mouse, backspace all work. ESC to leave.
//   VISUAL — select whole units by moving, then act on the selection
// plus the `:` command line and `/` search.

import Foundation
import Combine

enum EditorMode: Equatable {
    case normal
    case insert
    case visual
    case command(String)
    case search(String)

    var displayName: String {
        switch self {
        case .normal: return "NORMAL"
        case .insert: return "INSERT"
        case .visual: return "VISUAL"
        case .command: return "COMMAND"
        case .search: return "SEARCH"
        }
    }
}

enum Operator: Character, CaseIterable {
    case delete = "d", change = "c", yank = "y", note = "m"

    var displayName: String {
        switch self {
        case .delete: return "Delete"
        case .change: return "Change"
        case .yank: return "Yank"
        case .note: return "Note"
        }
    }
}

enum PendingKey: Equatable {
    case none
    case g
    case op(Operator)
}

enum KeyInput: Equatable {
    case char(Character)
    case escape
    case enter
    case backspace
    case ctrl(Character)
}

struct Register: Equatable {
    var text: String
    var kind: UnitKind
}

enum ExportRequest: Equatable {
    case document(ExportFormat)
    case log(EvolutionLogFormat)
}

/// What the statistics sheet can be scoped to, captured when it opens.
struct StatisticsContext {
    let text: String
    /// The paragraph the cursor is in.
    let paragraph: NSRange?
    /// The Visual-mode selection, if statistics were opened from Visual mode.
    let selection: NSRange?
}

enum EditorSheet: Identifiable {
    case review
    case note(range: NSRange, anchor: String)
    case help
    case statistics(StatisticsContext)

    var id: String {
        switch self {
        case .review: return "review"
        case .note: return "note"
        case .help: return "help"
        case .statistics: return "statistics"
        }
    }
}

enum PanelTab: String, CaseIterable, Identifiable {
    case history = "History", darlings = "Darlings", notes = "Notes"
    var id: String { rawValue }
}

final class EditorEngine: ObservableObject {
    let document: Document
    private(set) weak var buffer: TextBuffer?
    let snapshots: SnapshotScheduler

    @Published private(set) var mode: EditorMode
    @Published private(set) var pending: PendingKey = .none
    @Published private(set) var message: String?
    @Published private(set) var stats = TextStats.zero
    @Published private(set) var searchMatchCount = 0
    @Published var activeSheet: EditorSheet?
    @Published var panelRequest: PanelTab?
    /// Set by `:rename` with no name; the view shows the rename prompt.
    @Published var renameRequested = false
    /// Set by `:export <format>` or `:export log [format]`; the view shows the save panel.
    @Published var exportRequest: ExportRequest?
    /// Set by `:preview`; the view toggles the formatted preview.
    @Published var previewRequested = false

    var register: Register?

    private enum Repeatable {
        case operate(Operator, UnitKind, insertedText: String?)
        case deleteCharacter
    }
    private var lastRepeatable: Repeatable?
    private var changeStart: Int?             // where typing began after `c`, so `.` can replay it
    private var helperInsertion: NSRange?     // space/line break added by a/o/O, removed if nothing is typed
    private var lengthAtInsertEntry = 0
    private var visualAnchor = 0
    /// Set while Visual mode holds a mouse selection rather than whole units.
    private var visualFreeRange: NSRange?
    private var visualKind: UnitKind = .sentence
    private var lastSearch = ""
    /// Set when searching from the statistics sheet: match "the" but not "there".
    private var lastSearchWholeWord = false
    private var cachedUnits: TextUnits?
    private var statsTimer: Timer?

    init(document: Document) {
        self.document = document
        self.mode = document.content.isEmpty ? .insert : .normal
        self.snapshots = SnapshotScheduler(document: document)
    }

    var pendingOperator: Operator? {
        if case .op(let op) = pending { return op }
        return nil
    }

    // MARK: - Hooks from the view

    /// Called from `makeNSView`, i.e. while SwiftUI is updating views. Nothing @Published
    /// may change synchronously here, so the first stats count waits for the next turn.
    func attach(_ buffer: TextBuffer) {
        self.buffer = buffer
        DispatchQueue.main.async { [weak self] in self?.refreshStats() }
    }

    func textDidChange() {
        cachedUnits = nil
        snapshots.textDidChange()
        scheduleStats()
    }

    func selectionDidChange() {
        if mode == .visual { updateVisualHighlight() }
    }

    func flushSnapshots() {
        snapshots.flush()
    }

    // MARK: - Actions from the UI

    func openReview() { activeSheet = .review }

    /// Opens statistics with what they can be scoped to: the current paragraph, and the
    /// selection if in Visual mode.
    func openStatistics() {
        let selection = mode == .visual ? visualRange : nil
        let paragraph = units.unit(.paragraph, at: cursor)?.range
        activeSheet = .statistics(StatisticsContext(text: text, paragraph: paragraph, selection: selection))
    }

    /// Before the preview covers the editor: finish typing, drop selections and pending keys.
    func prepareForPreview() {
        leaveTransientModes()
        buffer?.setHighlight(nil)
    }

    /// After the preview closes: give the keyboard back to the text.
    func focusEditor() {
        buffer?.focus()
    }

    func jump(to range: NSRange) {
        leaveTransientModes()
        cursor = range.location
        buffer?.flash(range)
        buffer?.revealCursor()
    }

    /// Replaces the text with a snapshot as a single undoable edit, after capturing the
    /// current text as a safety snapshot (whatever the snapshot setting).
    func restore(_ snapshot: Snapshot) {
        leaveTransientModes()
        document.takeSnapshot()
        replace(NSRange(location: 0, length: text.utf16Length), with: snapshot.content, cursorAfter: 0)
        message = "Restored “\(snapshot.displayName)” — press u to undo"
    }

    func saveSnapshot(name: String, note: String) {
        if document.takeSnapshot(name: name, note: note) != nil {
            message = "Saved snapshot “\(name)”"
        }
    }

    func putInRegister(_ text: String) {
        register = Register(text: text, kind: .sentence)
        message = "In the register — press p to put it back"
    }

    // MARK: - Key dispatch

    func handle(_ key: KeyInput) {
        message = nil
        switch mode {
        case .insert:
            if key == .escape { exitInsert() }
        case .normal:
            handleNormal(key)
        case .visual:
            handleVisual(key)
        case .command(let current):
            handleCommandLine(key, current)
        case .search(let current):
            handleSearchLine(key, current)
        }
    }

    private func handleNormal(_ key: KeyInput) {
        switch pending {
        case .op(let op):
            pending = .none
            guard case .char(let c) = key, let kind = Self.object(for: c) else { return }
            operate(op, on: kind)
            return
        case .g:
            pending = .none
            if key == .char("g") { cursor = 0; afterMotion(kind: nil) }
            return
        case .none:
            break
        }

        switch key {
        case .escape:
            buffer?.setHighlight(nil)
        case .ctrl("r"):
            redo()
        case .char(let c):
            if performMotion(c) { return }
            normalCommand(c)
        default:
            break
        }
    }

    private func normalCommand(_ c: Character) {
        switch c {
        case "d", "c", "y", "m":
            if let op = Operator(rawValue: c) { pending = .op(op) }
        case "D": deleteToEndOfSentence(thenInsert: false)
        case "C": deleteToEndOfSentence(thenInsert: true)
        case "x": deleteCharacter()
        case "i": enterInsert(at: cursor)
        case "I": enterInsert(at: units.unit(.sentence, at: cursor)?.location ?? cursor)
        case "a": appendAfterSentence()
        case "A": enterInsert(at: units.unit(.paragraph, at: cursor)?.end ?? text.utf16Length)
        case "o": openParagraph(below: true)
        case "O": openParagraph(below: false)
        case "p": put(after: true)
        case "P": put(after: false)
        case "u": undo()
        case ".": repeatLast()
        case "v": enterVisual()
        case ":": mode = .command("")
        case "/": mode = .search("")
        default: break
        }
    }

    static func object(for c: Character) -> UnitKind? {
        switch c {
        case "w": return .word
        case "c": return .clause
        case "s": return .sentence
        case "p": return .paragraph
        default: return nil
        }
    }

    // MARK: - Motions

    /// Returns true if `c` is a motion key (whether or not there was anywhere to go).
    private func performMotion(_ c: Character) -> Bool {
        let u = units, position = cursor
        var target: Int?
        var kind: UnitKind?
        switch c {
        case "l": kind = .sentence; target = u.nextStart(.sentence, after: position)
        case "h": kind = .sentence; target = u.previousStart(.sentence, before: position)
        case "L": kind = .clause; target = u.nextStart(.clause, after: position)
        case "H": kind = .clause; target = u.previousStart(.clause, before: position)
        case "j": kind = .paragraph; target = u.nextStart(.paragraph, after: position)
        case "k": kind = .paragraph; target = u.previousStart(.paragraph, before: position)
        case "w": kind = .word; target = u.nextStart(.word, after: position)
        case "b": kind = .word; target = u.previousStart(.word, before: position)
        case "J", "K":
            buffer?.moveVisualLine(down: c == "J")
            afterMotion(kind: nil)
            return true
        case "G": target = text.utf16Length
        case "g": pending = .g; return true
        case "]": target = noteStart(forward: true)
        case "[": target = noteStart(forward: false)
        case "n": target = searchMatch(forward: true)
        case "N": target = searchMatch(forward: false)
        default: return false
        }
        if let target = target { cursor = target }
        afterMotion(kind: kind)
        return true
    }

    private func afterMotion(kind: UnitKind?) {
        if mode == .visual {
            if let kind = kind { visualKind = kind }
            updateVisualHighlight()
        }
        buffer?.revealCursor()
    }

    private func noteStart(forward: Bool) -> Int? {
        let starts = document.notes.filter { !$0.resolved && !$0.isDetached }.map(\.location).sorted()
        let position = cursor
        let target = forward ? starts.first(where: { $0 > position }) : starts.last(where: { $0 < position })
        if target == nil { message = forward ? "No more notes below" : "No more notes above" }
        return target
    }

    // MARK: - Operators

    private func operate(_ op: Operator, on kind: UnitKind, insertedText: String? = nil) {
        guard let unit = units.unit(kind, at: cursor) else { return }
        apply(op, to: unit.range, text: unit.text, kind: kind, insertedText: insertedText)
    }

    /// - Parameter exact: delete precisely `range` (a mouse selection that doesn't sit on
    ///   unit boundaries) instead of also tidying the spacing around a whole unit.
    private func apply(_ op: Operator, to range: NSRange, text unitText: String, kind: UnitKind,
                       insertedText: String? = nil, exact: Bool = false) {
        switch op {
        case .delete:
            register = Register(text: unitText, kind: kind)
            document.recordCut(unitText)
            let removal = exact ? range : units.deletionRange(for: range, kind: kind)
            replace(removal, with: "", cursorAfter: removal.location)
            lastRepeatable = .operate(.delete, kind, insertedText: nil)

        case .change:
            register = Register(text: unitText, kind: kind)
            document.recordCut(unitText)
            if let replacement = insertedText {
                replace(range, with: replacement, cursorAfter: range.location + replacement.utf16Length)
                lastRepeatable = .operate(.change, kind, insertedText: replacement)
            } else {
                replace(range, with: "", cursorAfter: range.location)
                lastRepeatable = .operate(.change, kind, insertedText: nil)
                enterInsert(at: range.location)
                changeStart = range.location
            }

        case .yank:
            register = Register(text: unitText, kind: kind)
            buffer?.flash(range)
            message = "Yanked \(kind.rawValue)"

        case .note:
            activeSheet = .note(range: range, anchor: unitText)
        }
    }

    private func deleteToEndOfSentence(thenInsert: Bool) {
        guard let rest = units.restOfSentence(from: cursor) else { return }
        register = Register(text: substring(rest), kind: .clause)
        document.recordCut(substring(rest))
        replace(rest, with: "", cursorAfter: rest.location)
        if thenInsert { enterInsert(at: rest.location) }
    }

    private func deleteCharacter() {
        let ns = text as NSString
        guard cursor < ns.length else { return }
        let range = ns.rangeOfComposedCharacterSequence(at: cursor)
        replace(range, with: "", cursorAfter: range.location)
        lastRepeatable = .deleteCharacter
    }

    /// Puts the register back as a whole unit: a sentence goes after (or before) the
    /// current sentence, a paragraph after the current paragraph, with spacing added.
    private func put(after: Bool) {
        guard let reg = register, !reg.text.isEmpty else { message = "Nothing yanked yet"; return }
        let u = units
        let location: Int, insertion: String, start: Int
        if let anchor = u.unit(reg.kind, at: cursor) {
            let separator = reg.kind == .paragraph ? u.paragraphSeparator : " "
            if after {
                location = anchor.end
                insertion = separator + reg.text
                start = location + separator.utf16Length
            } else {
                location = anchor.location
                insertion = reg.text + separator
                start = location
            }
        } else {
            location = cursor
            insertion = reg.text
            start = location
        }
        replace(NSRange(location: location, length: 0), with: insertion, cursorAfter: start)
        buffer?.flash(NSRange(location: start, length: reg.text.utf16Length))
    }

    private func repeatLast() {
        switch lastRepeatable {
        case .operate(let op, let kind, let inserted)?:
            operate(op, on: kind, insertedText: inserted)
        case .deleteCharacter?:
            deleteCharacter()
        case nil:
            break
        }
    }

    private func undo() {
        buffer?.undoEdit()
        cachedUnits = nil
    }

    private func redo() {
        buffer?.redoEdit()
        cachedUnits = nil
    }

    // MARK: - Insert

    private func enterInsert(at position: Int, helper: NSRange? = nil) {
        buffer?.setHighlight(nil)
        cursor = position
        helperInsertion = helper
        lengthAtInsertEntry = text.utf16Length
        mode = .insert
    }

    private func exitInsert() {
        buffer?.endTyping()
        if text.utf16Length == lengthAtInsertEntry, let helper = helperInsertion {
            replace(helper, with: "", cursorAfter: helper.location)
        }
        if let start = changeStart, case .operate(let op, let kind, _)? = lastRepeatable {
            let end = cursor
            let typed = end > start ? substring(NSRange(location: start, length: end - start)) : nil
            lastRepeatable = .operate(op, kind, insertedText: typed)
        }
        changeStart = nil
        helperInsertion = nil
        mode = .normal
    }

    /// `a`: start a new sentence after the current one.
    private func appendAfterSentence() {
        guard let sentence = units.unit(.sentence, at: cursor) else {
            enterInsert(at: text.utf16Length)
            return
        }
        let space = NSRange(location: sentence.end, length: 1)
        replace(NSRange(location: sentence.end, length: 0), with: " ", cursorAfter: sentence.end + 1)
        enterInsert(at: sentence.end + 1, helper: space)
    }

    /// `o` / `O`: start a new paragraph below or above the current one.
    private func openParagraph(below: Bool) {
        let u = units
        guard let paragraph = u.unit(.paragraph, at: cursor) else {
            enterInsert(at: text.utf16Length)
            return
        }
        let separator = u.paragraphSeparator
        let length = separator.utf16Length
        if below {
            replace(NSRange(location: paragraph.end, length: 0), with: separator)
            enterInsert(at: paragraph.end + length, helper: NSRange(location: paragraph.end, length: length))
        } else {
            replace(NSRange(location: paragraph.location, length: 0), with: separator)
            enterInsert(at: paragraph.location, helper: NSRange(location: paragraph.location, length: length))
        }
    }

    // MARK: - Visual

    private func enterVisual() {
        visualFreeRange = nil
        visualAnchor = cursor
        visualKind = .sentence
        mode = .visual
        updateVisualHighlight()
    }

    private func exitVisual() {
        visualFreeRange = nil
        mode = .normal
        buffer?.setHighlight(nil)
        // Drop any mouse selection, leaving the cursor at its start.
        if let selection = buffer?.cursorRange, selection.length > 0 { cursor = selection.location }
    }

    /// The user selected text with the mouse, shift-arrows or Select All outside Insert
    /// mode. A selection enters Visual mode holding exactly that text; a plain click
    /// (empty selection) while in Visual mode cancels it.
    func userSelected(_ range: NSRange) {
        guard mode == .normal || mode == .visual else { return }
        if range.length > 0 {
            pending = .none
            visualFreeRange = range
            visualAnchor = range.location
            visualKind = .sentence
            mode = .visual
            updateVisualHighlight()
        } else if mode == .visual {
            exitVisual()
        }
    }

    /// A motion key after a mouse selection: carry on from it, snapping to whole units.
    private func adoptFreeSelection() {
        guard let free = visualFreeRange else { return }
        visualFreeRange = nil
        visualAnchor = free.location
        cursor = max(free.location, NSMaxRange(free) - 1)
    }

    /// How a mouse selection is treated when acted on: as paragraphs if it holds a whole
    /// paragraph, as sentences if it holds a whole sentence, otherwise as words. `aligned`
    /// says it starts and ends exactly on units of that kind, so deleting it can tidy the
    /// spacing the way `ds` or `dw` would; anything else is deleted exactly as selected.
    private func describeFreeSelection(_ range: NSRange) -> (kind: UnitKind, aligned: Bool) {
        let u = units
        let start = range.location, end = NSMaxRange(range)
        func holdsWhole(_ kind: UnitKind) -> Bool {
            u.units(kind).contains { $0.location >= start && $0.end <= end }
        }
        let kind: UnitKind = holdsWhole(.paragraph) ? .paragraph : (holdsWhole(.sentence) ? .sentence : .word)
        let all = u.units(kind)
        let aligned = all.contains { $0.location == start } && all.contains { $0.end == end }
        return (kind, aligned)
    }

    private static let motionKeys: Set<Character> = ["h", "l", "H", "L", "j", "k", "w", "b", "J", "K", "G", "g", "[", "]", "n", "N"]

    /// The mouse selection if there is one; otherwise whole units of the most recent
    /// motion's kind, from the anchor to the cursor.
    private var visualRange: NSRange? {
        if let free = visualFreeRange {
            let length = text.utf16Length
            let location = min(free.location, length)
            return NSRange(location: location, length: min(free.length, length - location))
        }
        let u = units
        let low = min(visualAnchor, cursor), high = max(visualAnchor, cursor)
        guard let first = u.unit(visualKind, at: low), let last = u.unit(visualKind, at: high) else { return nil }
        let start = min(first.location, last.location)
        let end = max(first.end, last.end)
        return NSRange(location: start, length: end - start)
    }

    private func updateVisualHighlight() {
        buffer?.setHighlight(visualRange)
    }

    private func handleVisual(_ key: KeyInput) {
        if pending == .g {
            pending = .none
            if key == .char("g") { cursor = 0; afterMotion(kind: nil) }
            return
        }
        switch key {
        case .escape:
            exitVisual()
        case .char(let c):
            if c == "v" { exitVisual(); return }
            let op: Operator? = (c == "x") ? .delete : Operator(rawValue: c)
            if let op = op {
                guard let range = visualRange else { exitVisual(); return }
                var kind = visualKind
                var exact = false
                if visualFreeRange != nil {
                    let description = describeFreeSelection(range)
                    kind = description.kind
                    exact = !description.aligned
                }
                let selected = substring(range)
                exitVisual()
                cursor = range.location
                apply(op, to: range, text: selected, kind: kind, exact: exact)
                return
            }
            if visualFreeRange != nil, Self.motionKeys.contains(c) { adoptFreeSelection() }
            _ = performMotion(c)
        default:
            break
        }
    }

    // MARK: - Command line

    private func handleCommandLine(_ key: KeyInput, _ current: String) {
        switch key {
        case .escape: mode = .normal
        case .enter:
            mode = .normal
            run(command: current)
        case .backspace: mode = current.isEmpty ? .normal : .command(String(current.dropLast()))
        case .char(let c): mode = .command(current + String(c))
        case .ctrl: break
        }
    }

    func run(command raw: String) {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
        guard let name = parts.first?.lowercased() else { return }
        let argument = parts.count > 1 ? parts[1] : nil
        switch name {
        case "w", "save", "snap", "snapshot":
            if let snapshotName = argument {
                saveSnapshot(name: snapshotName, note: "")
            } else {
                activeSheet = .review
            }
        case "review", "changes", "diff": activeSheet = .review
        case "history", "log": panelRequest = .history
        case "darlings", "cuts": panelRequest = .darlings
        case "notes": panelRequest = .notes
        case "help", "h", "?": activeSheet = .help
        case "rename", "title":
            if let title = argument?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
                document.title = title
                message = "Renamed to “\(title)”"
            } else {
                renameRequested = true
            }
        case "preview", "p": previewRequested = true
        case "stats", "statistics": openStatistics()
        case "export":
            let words = (argument ?? "").split(separator: " ").map(String.init)
            if words.first?.lowercased() == "log" {
                if let format = EvolutionLogFormat(command: words.count > 1 ? words[1] : "") {
                    exportRequest = .log(format)
                } else {
                    message = "Usage: :export log [md | pdf | docx]"
                }
            } else if let format = words.first.flatMap(ExportFormat.init(command:)) {
                exportRequest = .document(format)
            } else {
                message = "Usage: :export txt | md | pdf | docx | archive, or :export log [md | pdf | docx]"
            }
        default: message = "Unknown command :\(name)"
        }
    }

    // MARK: - Search

    private func handleSearchLine(_ key: KeyInput, _ current: String) {
        switch key {
        case .escape:
            mode = .normal
            buffer?.setHighlight(nil)
        case .enter:
            mode = .normal
            buffer?.setHighlight(nil)
            guard !current.isEmpty else { return }
            lastSearch = current
            lastSearchWholeWord = false
            let matches = searchMatches(current)
            let position = cursor
            if let match = matches.first(where: { $0.location >= position }) ?? matches.first {
                cursor = match.location
                buffer?.flash(match)
                buffer?.revealCursor()
            } else {
                message = "Not found: \(current)"
            }
        case .backspace:
            if current.isEmpty {
                mode = .normal
                buffer?.setHighlight(nil)
            } else {
                let query = String(current.dropLast())
                mode = .search(query)
                previewSearch(query)
            }
        case .char(let c):
            let query = current + String(c)
            mode = .search(query)
            previewSearch(query)
        case .ctrl:
            break
        }
    }

    private func previewSearch(_ query: String) {
        let matches = searchMatches(query)
        searchMatchCount = matches.count
        let position = cursor
        buffer?.setHighlight(matches.first(where: { $0.location >= position }) ?? matches.first)
    }

    private func searchMatches(_ query: String, wholeWord: Bool = false) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let ns = text as NSString
        var matches: [NSRange] = []
        var start = 0
        func isWordCharacter(at index: Int) -> Bool {
            guard index >= 0, index < ns.length, let scalar = Unicode.Scalar(ns.character(at: index)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar)
        }
        while start < ns.length {
            let found = ns.range(of: query, options: .caseInsensitive,
                                 range: NSRange(location: start, length: ns.length - start))
            if found.location == NSNotFound { break }
            if !wholeWord || (!isWordCharacter(at: found.location - 1) && !isWordCharacter(at: NSMaxRange(found))) {
                matches.append(found)
            }
            start = found.location + max(found.length, 1)
        }
        return matches
    }

    /// Jumps to the next whole-word occurrence of `word`; n / N then step through the rest.
    func findWord(_ word: String) {
        leaveTransientModes()
        lastSearch = word
        lastSearchWholeWord = true
        let total = searchMatches(word, wholeWord: true).count
        if let target = searchMatch(forward: true) {
            cursor = target
            buffer?.revealCursor()
            message = "“\(word)”: \(total) \(total == 1 ? "match" : "matches") — n / N for next / previous"
        }
    }

    private func searchMatch(forward: Bool) -> Int? {
        let matches = searchMatches(lastSearch, wholeWord: lastSearchWholeWord)
        guard !matches.isEmpty else {
            message = lastSearch.isEmpty ? "No search yet — press / to search" : "Not found: \(lastSearch)"
            return nil
        }
        let position = cursor
        let match = forward
            ? (matches.first(where: { $0.location > position }) ?? matches[0])
            : (matches.last(where: { $0.location < position }) ?? matches[matches.count - 1])
        buffer?.flash(match)
        return match.location
    }

    // MARK: - Helpers

    private var text: String { buffer?.bufferText ?? "" }

    private var cursor: Int {
        get { buffer?.cursorRange.location ?? 0 }
        set { buffer?.cursorRange = NSRange(location: max(0, min(newValue, text.utf16Length)), length: 0) }
    }

    private var units: TextUnits {
        let current = text
        if let cached = cachedUnits, cached.text == current { return cached }
        let fresh = TextUnits(current)
        cachedUnits = fresh
        return fresh
    }

    private func substring(_ range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }

    private func replace(_ range: NSRange, with replacement: String, cursorAfter: Int? = nil) {
        guard let buffer = buffer else { return }
        buffer.replaceText(in: range, with: replacement)
        cachedUnits = nil
        if let position = cursorAfter { cursor = position }
    }

    private func leaveTransientModes() {
        switch mode {
        case .insert: exitInsert()
        case .visual: exitVisual()
        case .command, .search: mode = .normal
        case .normal: break
        }
        pending = .none
    }

    private func scheduleStats() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.refreshStats()
        }
    }

    private func refreshStats() {
        stats = units.stats
    }
}
