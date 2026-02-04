# Thesis MVP - Implementation Roadmap

## Executive Summary

**Scope:** 2-3 week full-time development for working MVP  
**Complexity:** High (modal editing + version control + diff rendering)  
**Key Risk:** NSTextView keyboard event handling complexity  
**Mitigation:** Build incrementally, test each mode independently

---

## Architecture Decisions

### 1. Text View: NSTextView vs SwiftUI TextEditor

**Decision: Use NSTextView via NSViewRepresentable**

**Rationale:**
- ✅ Full cursor control (selectedRange property)
- ✅ Keyboard event interception (keyDown override)
- ✅ Text delegate for constrained input
- ✅ Attributed string support for diff rendering
- ❌ More complex than TextEditor
- ❌ Requires AppKit knowledge

**Alternative Considered:** SwiftUI TextEditor
- ❌ No cursor position access
- ❌ No keyboard event handling
- ❌ Would need workarounds that add more complexity

**Verdict:** NSTextView is the only viable option for this use case.

### 2. Command Parsing: Buffer vs State Machine

**Decision: Simple command buffer with pattern matching**

**Rationale:**
- Commands are short (1-4 chars max)
- Limited command set (~20 commands)
- No nested commands
- Easy to debug

**Implementation:**
```swift
var commandBuffer = ""

func handleKey(_ key: String) {
    commandBuffer += key
    
    if commandBuffer == "dw" { executeDW(); commandBuffer = "" }
    else if commandBuffer == "das" { executeDAS(); commandBuffer = "" }
    // ... etc
    
    // Clear if too long or invalid
    if commandBuffer.count > 10 { commandBuffer = "" }
}
```

**Alternative Considered:** Full state machine
- Would be over-engineering for this limited command set
- Adds complexity without benefits

### 3. Diff Algorithm: Myers vs Simple Line-by-Line

**Decision: Start with simple word-level diff, upgrade if needed**

**Rationale:**
- MVP focus is on *showing* diffs, not perfect algorithms
- Swift has Difference API for collections
- Can upgrade to Myers algorithm post-MVP if needed

**Implementation:**
```swift
let oldWords = oldText.components(separatedBy: .whitespaces)
let newWords = newText.components(separatedBy: .whitespaces)
let diff = newWords.difference(from: oldWords)

// Apply red/green highlighting based on diff
```

**Alternative Considered:** Myers diff algorithm
- More accurate but complex
- Not needed for MVP validation

### 4. State Management: AppState vs DocumentViewModel

**Decision: Single AppState class with @Published properties**

**Rationale:**
- All state in one place (easier to debug)
- Clear data flow: View → AppState → Document
- Works well with SwiftUI @EnvironmentObject

**Structure:**
```swift
class AppState: ObservableObject {
    @Published var documents: [Document]
    @Published var selectedDocument: Document?
    @Published var editorMode: EditorMode
    @Published var cursorPosition: Int
    @Published var commandBuffer: String
    @Published var undoStack: UndoStack
    
    func handleCommand(_ command: EditorCommand) { ... }
}
```

### 5. Persistence: UserDefaults vs Core Data vs SQLite

**Decision: UserDefaults for MVP**

**Rationale:**
- Zero setup, works immediately
- JSON encoding is straightforward
- Good enough for <100 documents, <10MB data
- Easy migration path to Core Data later

**Limitations Accepted:**
- Not suitable for hundreds of documents
- No incremental loading
- No relationships/queries

**Migration Path:**
- Phase 2: Move to Core Data
- Phase 3: Add SQLite for full-text search

---

## Development Phases

### Phase 1: Foundation (Days 1-3)

**Goal:** Basic structure with mode switching

#### Day 1: Models & State
- [ ] Create Document, Draft, TextStatistics models
- [ ] Create EditCommand and UndoStack
- [ ] Create AppState with mode management
- [ ] Implement UserDefaults persistence

**Files to create:**
- `Models/Document.swift`
- `Models/Draft.swift`
- `Models/EditCommand.swift`
- `State/AppState.swift`

#### Day 2: Basic UI
- [ ] Create main window layout
- [ ] Create sidebar with document list
- [ ] Integrate NSTextView via NSViewRepresentable
- [ ] Mode indicators (colored borders)

**Files to create:**
- `Views/ContentView.swift`
- `Views/Sidebar.swift`
- `Views/EditorView.swift` (NSViewRepresentable wrapper)
- `Views/StatusBar.swift`

#### Day 3: Mode Switching
- [ ] INSERT mode: free typing, ESC to exit
- [ ] First Draft prompt dialog
- [ ] EDIT mode: read-only cursor display
- [ ] Visual mode transitions working

**Test:**
- Can type in INSERT
- ESC shows First Draft prompt
- Saving draft enters EDIT mode
- Mode border changes color

---

### Phase 2: Navigation (Days 4-5)

**Goal:** All navigation commands working in EDIT mode

#### Day 4: TextAnalyzer
- [ ] Create TextAnalyzer with NLTagger
- [ ] getSentences() method
- [ ] getParagraphs() method
- [ ] getWords() method
- [ ] getNext/PreviousSentence/Paragraph/Word() methods

**Files to create:**
- `Utilities/TextAnalyzer.swift`

#### Day 5: Navigation Commands
- [ ] Implement h/l (sentence navigation)
- [ ] Implement j/k (paragraph navigation)
- [ ] Implement w/b (word navigation)
- [ ] Update cursor position in text view

**Integration:**
- AppState receives EditorCommand from EditorView
- AppState calls TextAnalyzer to find target
- AppState updates cursorPosition
- EditorView updates NSTextView.selectedRange

**Test:**
- h/l jumps between sentences
- j/k jumps between paragraphs
- w/b jumps between words
- Cursor moves visually

---

### Phase 3: Delete Operations (Days 6-7)

**Goal:** All delete commands with highlighting

#### Day 6: Basic Deletes
- [ ] Implement dw (delete forward word)
- [ ] Implement db (delete backward word)
- [ ] Add highlight animation (200ms yellow)
- [ ] Push to undo stack

#### Day 7: Advanced Deletes
- [ ] Implement D (delete to end of sentence)
- [ ] Implement das (delete around sentence)
- [ ] Implement dap (delete around paragraph)

**Test:**
- Each delete command works correctly
- Highlight appears before deletion
- Undo restores text and cursor
- Document marked as modified

---

### Phase 4: Change & Insert (Days 8-9)

**Goal:** Constrained insert modes working

#### Day 8: Change Commands
- [ ] Implement cw (change word)
- [ ] Implement C (change to end of sentence)
- [ ] Implement cas (change around sentence)
- [ ] Implement cap (change around paragraph)
- [ ] Constrained input: block navigation, allow chars
- [ ] Auto-exit on conditions (space, punctuation, etc.)

#### Day 9: Insert Commands & Undo
- [ ] Implement i (insert word)
- [ ] Implement a (append sentence)
- [ ] Implement u (undo)
- [ ] Test undo stack (10 levels)

**Test:**
- cw changes single word, exits on space
- C changes to end, exits on punctuation
- i inserts word, a appends sentence
- u undos last 10 operations

---

### Phase 5: Compare Mode (Days 10-12)

**Goal:** Diff view with navigation

#### Day 10: Diff Algorithm
- [ ] Create DiffEngine using Swift's Difference API
- [ ] Generate word-level or sentence-level diffs
- [ ] Return array of changes (additions, deletions)

**Files to create:**
- `Utilities/DiffEngine.swift`

#### Day 11: Diff Rendering
- [ ] Create NSAttributedString with diff highlights
- [ ] Red strikethrough for deletions
- [ ] Green background for additions
- [ ] Display in read-only NSTextView

#### Day 12: Diff Navigation
- [ ] Implement n (next difference)
- [ ] Implement p (previous difference)
- [ ] Jump cursor to next/prev change
- [ ] ESC exits to EDIT mode

**Test:**
- Diff shows changes accurately
- Red/green highlighting is clear
- n/p jumps between changes
- Can exit back to EDIT

---

### Phase 6: Polish & Testing (Days 13-14)

**Goal:** Production-ready MVP

#### Day 13: Status Bar & Dialogs
- [ ] Status bar shows mode, draft name, statistics
- [ ] First Draft dialog with name input
- [ ] Save Draft dialog with name and comment
- [ ] Statistics update live

#### Day 14: Final Polish
- [ ] Visual refinements (spacing, colors)
- [ ] Error handling (edge cases)
- [ ] Performance testing (500-word documents)
- [ ] User testing with 3-5 people

**Test Everything:**
- Full workflow: INSERT → First Draft → EDIT → Changes → COMPARE → Save Draft
- All 20+ commands work correctly
- No crashes on edge cases
- Performance is smooth

---

## Critical Path Items

These are blockers - if these fail, MVP fails:

1. **NSTextView keyboard event handling**
   - Must intercept all keys in EDIT mode
   - Must allow constrained input in change/insert modes
   - Fallback: Use NSResponder subclass if delegate fails

2. **NLTagger sentence detection**
   - Must be ~95% accurate for common text
   - Test with: abbreviations, quotes, decimals
   - Fallback: Custom regex if NLTagger too buggy

3. **Diff rendering performance**
   - Must handle 1000-word documents smoothly
   - Attributed string generation can't lag
   - Fallback: Simplify to line-level diffs if too slow

4. **Undo stack correctness**
   - Must restore exact state (content + cursor)
   - Can't lose data or corrupt document
   - Fallback: Reduce to 5 levels if memory issues

---

## File Structure

```
ThesisAppMVP/
├── App/
│   └── ThesisApp.swift                 # App entry point
│
├── Models/
│   ├── Document.swift                  # Document with drafts
│   ├── Draft.swift                     # Single draft snapshot
│   ├── EditCommand.swift               # Undo/redo command
│   └── EditorMode.swift                # Mode enum
│
├── State/
│   └── AppState.swift                  # Central state management
│
├── Views/
│   ├── ContentView.swift               # Main layout
│   ├── Sidebar.swift                   # Document list
│   ├── EditorView.swift                # NSTextView wrapper
│   ├── StatusBar.swift                 # Mode + statistics
│   ├── FirstDraftDialog.swift          # First draft prompt
│   └── SaveDraftDialog.swift           # Save draft prompt
│
├── Utilities/
│   ├── TextAnalyzer.swift              # NLTagger wrapper
│   ├── DiffEngine.swift                # Diff algorithm
│   └── CommandParser.swift             # Parse edit commands
│
├── Resources/
│   ├── Info.plist
│   └── Assets.xcassets
│
└── Documentation/
    ├── MVP_SPECIFICATION.md
    ├── IMPLEMENTATION_ROADMAP.md
    └── README.md
```

**Total files:** ~15 Swift files + docs

---

## Risk Assessment

### High Risk
🔴 **NSTextView keyboard handling**
- Mitigation: Prototype this first (Day 1-2)
- If fails: Consider Electron or web-based alternative

🔴 **Constrained insert modes**
- Mitigation: Test delegate methods early
- If fails: Simplify to just `i` entering full INSERT mode

### Medium Risk
⚠️ **Diff rendering performance**
- Mitigation: Profile with Instruments
- If slow: Batch attribute updates, simplify diff

⚠️ **Command parsing edge cases**
- Mitigation: Comprehensive unit tests
- If buggy: Add timeout to clear buffer faster

### Low Risk
✅ **Model/state management** - Standard Swift patterns
✅ **Persistence** - UserDefaults is reliable
✅ **UI layout** - SwiftUI is mature

---

## Success Metrics

### Technical
- [ ] All 20+ commands implemented
- [ ] Zero crashes in 1-hour stress test
- [ ] Undo works for all operations
- [ ] Performance: <100ms for any command
- [ ] Data persistence: 100% reliable

### User Experience
- [ ] Mode transitions feel immediate
- [ ] Highlights are visible but not annoying
- [ ] Diff view is readable
- [ ] Status bar is informative
- [ ] Keyboard-only workflow is fluid

### Validation
- [ ] 5 beta testers complete full workflow
- [ ] 3+ say it's better than their current tool
- [ ] 0 reports of data loss
- [ ] Feature requests focused on enhancements, not basics

---

## Post-MVP Roadmap

If MVP succeeds, prioritize these:

**Week 4-5: Core Improvements**
- Redo support (Ctrl+R)
- Repeat last command (.)
- Visual selection mode (v)
- More delete/change variants

**Week 6-7: Version Control Enhancements**
- Branch support
- Merge/combine drafts
- Restore any draft (not just last)
- Diff between any two drafts

**Week 8-9: Professional Features**
- Markdown rendering
- Export to PDF/DOCX
- Full-text search
- Tags and metadata

**Week 10-12: iOS Port**
- Touch gesture navigation
- On-screen command palette
- iCloud sync
- Universal clipboard

---

## Decision Points

### After Phase 1 (Day 3)
**Question:** Does mode switching feel natural?
- If yes: Continue to Phase 2
- If no: Simplify modes or reconsider approach

### After Phase 3 (Day 7)
**Question:** Do delete operations feel precise?
- If yes: Continue to Phase 4
- If no: Add visual selection mode first

### After Phase 5 (Day 12)
**Question:** Does COMPARE mode provide clear value?
- If yes: Polish and ship
- If no: Simplify to just "show last draft" side-by-side

### After Phase 6 (Day 14)
**Question:** Would I use this for real work?
- If yes: Recruit beta testers, iterate to 1.0
- If maybe: Get more user feedback, improve pain points
- If no: Re-evaluate core concept

---

## Conclusion

This MVP is **ambitious but achievable** in 2-3 weeks with focused development.

**Keys to success:**
1. Build NSTextView integration first (de-risk early)
2. Test each mode independently before integrating
3. Use NLTagger as-is (don't over-engineer sentence detection)
4. Keep diff simple (word-level is fine for MVP)
5. Get user feedback after each phase

**If you're ready to build:** Start with Phase 1, Day 1.
