## Quick Start - Thesis MVP

### 5-Minute Setup

1. **Create Xcode Project**
   ```
   Open Xcode → File → New → Project
   Choose: macOS → App
   Product Name: Thesis
   Interface: SwiftUI
   Language: Swift
   ```

2. **Add Source Files**
   - Delete default `ThesisApp.swift` and `ContentView.swift`
   - Drag all 12 `.swift` files into project
   - Check "Copy items if needed"
   - Add to target: Thesis

3. **Update Info.plist**
   - Replace with provided `Info.plist`

4. **Build Settings**
   - Minimum macOS: 13.0
   - Bundle ID: com.thesis.app.mvp

5. **Run**
   - Press Cmd+R
   - App launches with welcome document

### First Test (3 Minutes)

**Goal:** Complete one full workflow cycle

1. **Read Welcome** (in INSERT mode - green border)
2. **Press ESC** → Save First Draft as "Test 1"
3. **Navigate:** Press `l` three times (next sentence)
4. **Delete:** Type `das` (delete sentence - watch highlight!)
5. **Change:** Navigate to a word, type `cw`, type new word + space
6. **Review:** Press Cmd+D → See diff in yellow
7. **Navigate diff:** Press `n` and `p`
8. **Save:** Press Cmd+S → Name "Test 2", comment "Deleted and changed"
9. **History:** Click clock icon → See both drafts

**Success:** You just evolved a thought with version control! ✅

### Test Document Template

Create a new document and paste this:

```
Distributed systems are inherently more resilient than centralized architectures. They eliminate single points of failure. However, they introduce complexity.

The CAP theorem states you cannot have all three properties simultaneously. Consistency and availability must be balanced. Partition tolerance is non-negotiable in distributed systems.

Modern applications favor eventual consistency. This trade-off enables massive scale. Users accept slight delays for better uptime.
```

Now practice:
- **Navigation:** `h/l` between sentences, `j/k` between paragraphs
- **Delete:** `dw` on "inherently", `das` on second sentence
- **Change:** `cas` on CAP theorem sentence
- **Undo:** `u` after each operation
- **Comp:** Cmd+D after multiple changes

### Command Cheat Sheet

Print this and keep visible:

```
┌─────────────────────────────────────┐
│         THESIS COMMANDS             │
├─────────────────────────────────────┤
│ NAVIGATION                          │
│  h  ← sentence    l  → sentence     │
│  k  ↑ paragraph   j  ↓ paragraph    │
│  b  ← word        w  → word         │
├─────────────────────────────────────┤
│ DELETE (stay in EDIT)               │
│  dw   word →      db   word ←       │
│  das  sentence    dap  paragraph    │
│  D    to end of sentence            │
├─────────────────────────────────────┤
│ CHANGE (enter INSERT)               │
│  cw   word        cas  sentence     │
│  cap  paragraph   C    to end       │
│  Exit: space/punctuation/ESC        │
├─────────────────────────────────────┤
│ INSERT (enter INSERT)               │
│  i    word        a    sentence     │
│  Exit: space/punctuation/ESC        │
├─────────────────────────────────────┤
│ OTHER                               │
│  u       undo (10 levels)           │
│  :comp   diff view (or Cmd+D)       │
│  :print  save draft (or Cmd+S)      │
│  ESC     → EDIT / save first draft  │
└─────────────────────────────────────┘
```

### Common First-Time Issues

**"I'm stuck in a mode!"**
→ Press ESC to return to EDIT mode

**"Commands don't work"**
→ Check border color - must be blue (EDIT mode)

**"Can't type freely"**
→ You're in EDIT mode - press `i` or `a` for constrained insert, or edit with `c` commands

**"Sentence navigation is weird"**
→ NLTagger splits on periods - "Dr. Smith" may cause split

**"Where's my text?"**
→ Press `u` to undo - or check Draft History

**"How do I save?"**
→ Working draft auto-saves. For commits: Cmd+S or :print

### What to Test First

#### Day 1: Basic Commands
- All navigation (hjklwb)
- All delete commands
- Undo
- First draft save

#### Day 2: Change Commands
- cw with different words
- cas with different sentences
- Exit conditions (space, punctuation, ESC)
- Undo after changes

#### Day 3: Workflow
- Write 500-word essay
- Save First Draft
- Make 10 edits
- Review with :comp
- Save as Draft 2
- Repeat 3x

#### Day 4: Edge Cases
- Very long sentences
- Abbreviations (test sentence detection)
- 10+ undos (test stack limit)
- Multiple documents

#### Day 5: Real Work
- Use for actual work
- Note friction points
- Test if you reach for mouse
- Measure time saved

### File Checklist

Verify all files are in project:

- [ ] ThesisApp.swift
- [ ] ContentView.swift
- [ ] EditorMode.swift
- [ ] Document.swift
- [ ] Draft.swift
- [ ] DocumentManager.swift
- [ ] ModalEditor.swift
- [ ] EditorTextView.swift
- [ ] TextAnalyzer.swift
- [ ] EditCommand.swift
- [ ] DiffGenerator.swift
- [ ] DraftHistoryView.swift
- [ ] Info.plist

**Total: 13 files**

### Data Location

If you need to reset everything:

```bash
# Delete all saved documents
defaults delete com.thesis.app.mvp
```

### Getting Help

1. Check README.md for detailed explanations
2. Check status bar - shows current mode and command
3. Verify border color matches expected mode
4. Try ESC to reset to EDIT mode
5. Clean build if strange behavior (Cmd+Shift+K)

### Success Indicators

After 30 minutes you should be able to:
- [ ] Switch modes without thinking
- [ ] Navigate faster than with mouse
- [ ] Delete/change without fear (undo works)
- [ ] Understand what :comp shows
- [ ] Complete a full draft cycle

If yes to all 5 → concept is viable! 🎉

### Next Steps

Once comfortable:
1. Write a real document (500+ words)
2. Save 3+ drafts over multiple sessions
3. Review your evolution in history
4. Ask: "Would I use this daily?"

See EVALUATION.md for structured testing protocol.
