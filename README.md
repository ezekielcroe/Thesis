# Thesis — Modal Editor for Thought Evolution

A native macOS writing app with modal editing and semantic version control.

## Architecture (3,585 lines across 16 files)

```
┌─────────────────────────────────────────────────┐
│  ThesisApp.swift          App entry point        │
│  ContentView.swift        Layout: sidebar/editor │
├─────────────────────────────────────────────────┤
│  ModalEditor.swift        Core editor (947 LOC)  │
│    Key routing, navigation, verb-object system,  │
│    visual mode, comp mode, command mode           │
├─────────────────────────────────────────────────┤
│  EditorTextView.swift     NSViewRepresentable    │
│    ModalNSTextView        Key event interception │
├─────────────────────────────────────────────────┤
│  StatusBar.swift          Mode + stats display   │
│  DraftHistoryView.swift   History/Darlings/Notes │
│  Sheets.swift             Save/Annotate dialogs  │
├─────────────────────────────────────────────────┤
│  EditorMode.swift         Modes + verb/object    │
│  SemanticChange.swift     Change type system     │
│  TextAnalyzer.swift       NLP text parsing       │
│  UndoSystem.swift         Operation-based undo   │
│  DiffGenerator.swift      Sentence-level diff    │
├─────────────────────────────────────────────────┤
│  Document.swift           Core data model        │
│  Draft.swift              Version snapshots      │
│  Annotation.swift         Positional notes       │
│  DocumentManager.swift    Persistence            │
└─────────────────────────────────────────────────┘
```

## Mode Flow

```
FREE TEXT  ──ESC──▶  NORMAL  ──v──▶  VISUAL
                      │  ▲            │
                  i/a/o/c  ESC    d/c/r/y/m
                      ▼  │            │
                    INSERT         (executes, back to NORMAL)
                      │
                  NORMAL  ──:──▶  COMMAND  ──⏎──▶  NORMAL
                      │
                  Cmd+D──▶  COMPARE  ──ESC──▶  NORMAL
```

## Command Reference

### Navigation (Normal + Visual modes)
| Key | Action |
|-----|--------|
| w / b | Next / previous word |
| h / l | Next / previous clause |
| H / L | Next / previous sentence (Shift) |
| j / k | Next / previous paragraph |
| J / K | Next / previous line (Shift) |

### Verb-Object Commands (Normal mode)
Press verb, see live highlight + help overlay, then press object:

| Verb | Object keys | Result |
|------|-------------|--------|
| d | w/b/c/s/p | Delete word/word-back/clause/sentence/paragraph |
| c | w/c/s/p | Change (replace) — enters Insert mode |
| r | w/c/s/p | Refine (improve wording) — enters Insert mode |
| y | w/c/s/p | Yank (copy to register) |
| m | w/c/s/p | Markup (add annotation) |

Shift+D / Shift+C / Shift+R = operate to end of sentence.

### Direct Actions (Normal mode)
| Key | Action |
|-----|--------|
| i | Insert at cursor (word context) |
| a | Append after current sentence |
| o | Open new line below, enter Insert |
| p | Paste from yank register |
| u | Undo (operation-based, syncs with semantic changes) |
| v | Enter Visual mode |
| : | Enter Command mode |

### Visual Mode
Navigate with same keys to extend selection, then press action:
d = delete, c = change, r = refine, y = yank, m = markup

### Command Mode
| Command | Action |
|---------|--------|
| :comp / :diff | Enter Compare mode |
| :save / :commit | Save draft (commit) |
| :hist / :log | (toggle history panel) |
| :notes / :anno | (toggle notes panel) |

### Compare Mode
| Key | Action |
|-----|--------|
| n | Next change |
| p | Previous change |
| ESC | Exit compare |

## Key Design Decisions

1. **Select-then-act via Visual mode (v)** — Safer path for new users. Navigate to select, see highlight, then choose action.

2. **Live highlight on verb press** — When you press `d`, the target unit highlights immediately. Object key confirms.

3. **Semantic change tracking** — Every edit records WHY (added/deleted/replaced/refined), not just what. Version history reads as intellectual narrative.

4. **Context-aware Insert exit** — Typing `.` in sentence-insert mode auto-escapes. ESC always works.

5. **Darlings panel** — All deleted/replaced text is recoverable. "Never lose a word you've written."

6. **Operation-based undo** — Undo syncs with semantic change history. Undoing a delete also removes it from the change log.

7. **Annotations via `m` (markup)** — Positional notes attached to text ranges, shown in sidebar panel.

## Setup

1. Open Xcode → File → New → Project → macOS App (SwiftUI)
2. Replace generated files with these source files
3. Set deployment target: macOS 14.0+
4. Build and run (⌘R)

No external dependencies — uses only Apple frameworks (SwiftUI, AppKit, NaturalLanguage, Foundation).
