# Thesis MVP - Complete Specification

## Overview

A modal text editor for version-controlled writing with three distinct modes: INSERT, EDIT, and COMPARE.

## Core Workflow

```
[INSERT Mode] → Write content
      ↓
   Press ESC
      ↓
   Name First Draft (y) → [EDIT Mode]
      ↓                       ↓
   Cancel (n)           Navigate & Refine
      ↓                       ↓
   Back to INSERT        :comp or Cmd+D
                              ↓
                         [COMPARE Mode]
                              ↓
                         :print or Cmd+S
                              ↓
                         Save Draft with Comment
                              ↓
                         Back to EDIT Mode
```

## Mode Specifications

### 1. INSERT Mode (Green Border)

**Purpose:** Free-form writing and composing

**Behavior:**
- Standard text editor - all keys insert characters
- No navigation commands active
- Unrestricted typing
- Auto-saves as "Working Draft"

**Exit:**
- Press ESC → Triggers First Draft prompt (if no drafts exist)
- Press ESC → Enters EDIT mode (if drafts exist)

**First Draft Prompt:**
```
┌─────────────────────────────────────┐
│  Save as First Draft                │
│                                     │
│  Draft Name: [First Draft_____]    │
│                                     │
│  This will be your baseline for    │
│  tracking all future changes.      │
│                                     │
│     [Save (y)]    [Cancel (n)]     │
└─────────────────────────────────────┘
```

- Press 'y' or click Save: Save draft, enter EDIT mode
- Press 'n' or click Cancel: Return to INSERT mode

### 2. EDIT Mode (Blue Border)

**Purpose:** Navigation and precise editing

**Behavior:**
- Read cursor position from text view
- Execute atomic commands
- Brief highlight before destructive operations (200ms)
- All edits tracked for undo (up to 10 levels)

#### Navigation Commands

| Key | Command | Action |
|-----|---------|--------|
| `h` | Previous Sentence | Move cursor to start of previous sentence |
| `l` | Next Sentence | Move cursor to start of next sentence |
| `j` | Next Paragraph | Move cursor to start of next paragraph |
| `k` | Previous Paragraph | Move cursor to start of previous paragraph |
| `w` | Next Word | Move cursor to start of next word |
| `b` | Previous Word | Move cursor to start of previous word |

**Implementation:** Use NLTagger with `.sentence`, `.paragraph`, `.word` units

#### Delete Commands

| Command | Action | Range |
|---------|--------|-------|
| `dw` | Delete Forward Word | From cursor to end of current word + space |
| `db` | Delete Backward Word | From start of current word to cursor |
| `D` (Shift+d) | Delete to End of Sentence | From cursor to end of sentence (include period + whitespace) |
| `das` | Delete Around Sentence | Entire current sentence (include period + whitespace) |
| `dap` | Delete Around Paragraph | Entire current paragraph (include trailing newlines) |

**Behavior:**
1. Highlight range for 200ms
2. Execute delete
3. Push to undo stack
4. Mark document as modified

#### Change Commands

| Command | Action | Constrained Input Mode | Exit Condition |
|---------|--------|------------------------|----------------|
| `cw` | Change Word | Single word | Space or ESC |
| `C` (Shift+c) | Change to End | Multi-word | Punctuation (. ! ?) or ESC |
| `cas` | Change Around Sentence | Multi-word | Punctuation (. ! ?) or ESC |
| `cap` | Change Around Paragraph | Multi-paragraph | Double newline or ESC |

**Behavior:**
1. Highlight range for 200ms
2. Delete range
3. Enter constrained INSERT mode
4. Accept only characters and backspace
5. Block navigation commands
6. Exit on condition met, return to EDIT mode

#### Insert Commands

| Command | Action | Constrained Input Mode | Exit Condition |
|---------|--------|------------------------|----------------|
| `i` | Insert Word | Single word | Space or ESC |
| `a` | Append Sentence | Multi-word | Punctuation (. ! ?) or ESC |

**Behavior:**
- Insert at current cursor position
- Enter constrained INSERT mode
- Exit on condition, return to EDIT mode

#### Undo Command

| Command | Action |
|---------|--------|
| `u` | Undo | Restore previous state (up to 10 levels) |

**Implementation:**
- Undo stack stores: (beforeContent, afterContent, cursorBefore, cursorAfter)
- Pop from stack
- Restore content and cursor
- Stay in EDIT mode

#### Mode Transition Commands

| Command | Action |
|---------|--------|
| `:comp` + Return | Enter COMPARE mode |
| Cmd+D | Enter COMPARE mode (shortcut) |
| `:print` + Return | Show Save Draft dialog |
| Cmd+S | Show Save Draft dialog (shortcut) |

### 3. COMPARE Mode (Orange Border)

**Purpose:** Read-only diff view between Working Draft and Last Saved Draft

**Display:**
- Inline git-style diff
- Red strikethrough for deletions
- Green highlight for additions
- Unchanged text in normal color

**Navigation:**

| Key | Action |
|-----|--------|
| `h`, `j`, `k`, `l`, `w`, `b` | Normal navigation (read-only) |
| `n` | Jump to next difference |
| `p` | Jump to previous difference |

**Exit:**
- Press ESC: Return to EDIT mode
- Type `:print` + Return: Show Save Draft dialog
- Press Cmd+S: Show Save Draft dialog

**Save Draft Dialog:**
```
┌─────────────────────────────────────┐
│  Save Draft                         │
│                                     │
│  Draft Name: [Draft 2_________]    │
│                                     │
│  Comment (describe changes):       │
│  [Refined argument structure___]   │
│  [Added counterpoint examples__]   │
│                                     │
│     [Save]    [Cancel]             │
└─────────────────────────────────────┘
```

- Save: Create new draft, clear undo stack, return to EDIT mode
- Cancel: Return to COMPARE mode

## Status Bar

Display at bottom of editor:

```
[MODE]  Draft: [Name]  |  Para: N  Sent: N  Words: N  |  *Unsaved
```

**Examples:**
```
[INSERT]  Working Draft  |  Para: 3  Sent: 12  Words: 247

[EDIT]  Draft 2: First Revision  |  Para: 5  Sent: 18  Words: 342  |  *Unsaved

[COMPARE]  Comparing: Working Draft ↔ Draft 2  |  Changes: 4
```

## Sidebar

**Purpose:** Document library

**Display:**
- List of all documents
- Each shows: Title, Last Modified, Draft Count
- Selected document highlighted

**Actions:**
- Click to switch documents
- Cmd+N to create new document
- Right-click to delete document

## Visual Indicators

### Mode Borders
- **INSERT:** 3px green border around editor
- **EDIT:** 3px blue border around editor
- **COMPARE:** 3px orange border around editor

### Highlights
- **Before Delete:** Yellow background, 200ms
- **Before Change:** Yellow background, 200ms
- **Diff Deletions:** Red strikethrough
- **Diff Additions:** Green background

## Text Analysis (NLTagger)

### Sentence Detection
```swift
let tagger = NLTagger(tagSchemes: [.lexicalClass])
tagger.string = text
tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                    unit: .sentence,
                    scheme: .lexicalClass) { ... }
```

**Edge Cases:**
- "Dr. Smith arrived." → 1 sentence
- "She said, 'Hello.'" → 1 sentence
- "Cost is $3.50." → 1 sentence

NLTagger handles these ~95% accurately.

### Paragraph Detection
```swift
tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                    unit: .paragraph,
                    scheme: .lexicalClass) { ... }
```

**Definition:** Text separated by `\n\n` or single `\n` with distinct blocks

### Word Detection
```swift
tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                    unit: .word,
                    scheme: .lexicalClass) { ... }
```

## Data Model

### Document
```swift
class Document {
    let id: UUID
    var title: String
    var workingContent: String
    var drafts: [Draft]
    var hasUnsavedChanges: Bool
    var lastModified: Date
}
```

### Draft
```swift
struct Draft {
    let id: UUID
    let timestamp: Date
    let name: String
    let content: String
    let comment: String
    let statistics: TextStatistics
}
```

### TextStatistics
```swift
struct TextStatistics {
    let paragraphCount: Int
    let sentenceCount: Int
    let wordCount: Int
}
```

### EditCommand
```swift
struct EditCommand {
    let beforeContent: String
    let afterContent: String
    let cursorBefore: Int
    let cursorAfter: Int
    let timestamp: Date
}
```

### UndoStack
```swift
class UndoStack {
    private var commands: [EditCommand] = []
    let maxSize = 10
    
    func push(_ command: EditCommand)
    func pop() -> EditCommand?
    func clear()
}
```

## Storage

**UserDefaults** for MVP:
- Key: "ThesisDocuments"
- Format: JSON encoded array of Documents
- Auto-save every 2 seconds
- Manual save on draft creation

## Implementation Complexity

### Phase 1: Core Structure (2-3 days)
- ✅ Document/Draft models
- ✅ AppState management
- ✅ TextAnalyzer with NLTagger
- ✅ Basic UI layout
- ✅ Mode switching

### Phase 2: Edit Commands (3-4 days)
- ⚠️ Navigation (hjklwb)
- ⚠️ Delete operations (dw, db, D, das, dap)
- ⚠️ Change operations (cw, C, cas, cap)
- ⚠️ Insert operations (i, a)
- ⚠️ Command parser
- ⚠️ Undo stack

### Phase 3: Compare Mode (2-3 days)
- 🔴 Diff algorithm
- 🔴 Inline diff rendering
- 🔴 Diff navigation (n, p)
- 🔴 Visual highlighting

### Phase 4: Polish (2-3 days)
- 🔴 Status bar with statistics
- 🔴 Visual mode indicators
- 🔴 Highlight animations
- 🔴 Draft management UI
- 🔴 Save/load dialogs

**Total: 10-14 days full-time development**

## Technical Challenges

### 1. Cursor Management
**Problem:** SwiftUI TextEditor doesn't expose cursor position

**Solution:** Use NSTextView via NSViewRepresentable
- Direct access to selectedRange
- Can set cursor programmatically
- Full keyboard event handling

### 2. Constrained Insert Modes
**Problem:** Need to intercept specific keys in INSERT mode

**Solution:** NSTextView delegate
- Implement `textView(_:shouldChangeTextIn:replacementString:)`
- Check for exit conditions
- Block/allow changes accordingly

### 3. Command Parsing
**Problem:** Multi-character commands (das, cap, :comp)

**Solution:** Command buffer
- Accumulate characters
- Match against command patterns
- Execute on complete match
- Clear on timeout or invalid sequence

### 4. Diff Rendering
**Problem:** Show inline git-style diff

**Solution:** NSAttributedString
- Run diff algorithm on strings
- Apply attributes (color, strikethrough)
- Display in read-only NSTextView

### 5. Highlight Animations
**Problem:** Brief highlight before delete

**Solution:** Temporary attributes
- Apply yellow background to range
- Use DispatchQueue.main.asyncAfter
- Remove after 200ms, then execute

## Testing Checklist

### INSERT Mode
- [ ] Can type freely
- [ ] ESC triggers First Draft prompt (first time)
- [ ] ESC enters EDIT mode (subsequent times)
- [ ] Auto-saves as Working Draft

### EDIT Mode - Navigation
- [ ] h/l moves between sentences correctly
- [ ] j/k moves between paragraphs correctly
- [ ] w/b moves between words correctly
- [ ] Cursor position updates visually

### EDIT Mode - Delete
- [ ] dw deletes forward word
- [ ] db deletes backward word
- [ ] D deletes to end of sentence
- [ ] das deletes whole sentence
- [ ] dap deletes whole paragraph
- [ ] 200ms highlight appears before delete

### EDIT Mode - Change
- [ ] cw changes single word (exits on space)
- [ ] C changes to end of sentence (exits on punctuation)
- [ ] cas changes whole sentence (exits on punctuation)
- [ ] cap changes whole paragraph (exits on double newline)

### EDIT Mode - Insert
- [ ] i inserts single word (exits on space)
- [ ] a appends sentence (exits on punctuation)

### EDIT Mode - Undo
- [ ] u undoes last command
- [ ] Works up to 10 levels
- [ ] Restores cursor position

### COMPARE Mode
- [ ] Shows diff between Working and Last Draft
- [ ] Red strikethrough for deletions
- [ ] Green highlight for additions
- [ ] n/p navigates between differences
- [ ] ESC returns to EDIT mode
- [ ] :print or Cmd+S shows Save Draft dialog

### Drafts
- [ ] First Draft prompt on first ESC from INSERT
- [ ] Save creates new draft with name and comment
- [ ] Draft list shows all drafts with timestamps
- [ ] Can restore old draft (future feature)

### Visual
- [ ] Mode border changes color (green/blue/orange)
- [ ] Status bar shows correct mode and statistics
- [ ] Highlights appear briefly before operations

### Persistence
- [ ] Documents auto-save to UserDefaults
- [ ] Relaunch restores all documents
- [ ] No data loss on quit

## Future Enhancements (Post-MVP)

- Branch/merge support
- Side-by-side diff view
- Restore any draft (not just last)
- Full-text search
- Export to Markdown/PDF
- Themes and customization
- iOS version with gestures
- iCloud sync
- Collaborative editing

## Success Criteria

After 2 weeks of testing:

**Usability:**
- [ ] Can navigate 500-word document faster than with mouse
- [ ] Modal switching becomes automatic
- [ ] Diff view provides clear value

**Value:**
- [ ] Users reference draft history weekly
- [ ] Constrained insert modes feel purposeful
- [ ] Sentence-level navigation matches thought process

**Adoption:**
- [ ] 60%+ of testers prefer it for serious writing
- [ ] 40%+ would pay $20 for this
- [ ] Generates word-of-mouth interest

---

## Getting Started

1. **Build the core structure** (models, AppState)
2. **Implement mode switching** (INSERT ↔ EDIT)
3. **Add navigation** (hjklwb)
4. **Add delete** (dw, db, D, das, dap)
5. **Add change/insert** (cw, C, cas, cap, i, a)
6. **Implement undo**
7. **Build COMPARE mode**
8. **Polish UI/UX**

This is now ready to be built. Estimated 2-3 weeks for working MVP.
