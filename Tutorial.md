# Thesis: a tutorial

Thesis is a writing app for the Mac that treats prose as **ideas, not characters**. You move by
sentence and paragraph, act on whole clauses and sentences, and the app keeps a record of how
your text changed and why, without getting in the way while you write.

This tutorial goes from your first document to revising, reviewing history, formatting with
Markdown, analysing your prose and exporting it. Each part builds on the last, but you can
jump to any section. A full key reference is at the end.

**Contents**

1. [The idea in one minute](#1-the-idea-in-one-minute)
2. [Your first document](#2-your-first-document)
3. [Writing: Insert mode](#3-writing-insert-mode)
4. [Moving around: Normal mode](#4-moving-around-normal-mode)
5. [Editing whole units](#5-editing-whole-units)
6. [Selecting passages: Visual mode](#6-selecting-passages-visual-mode)
7. [Search and the command line](#7-search-and-the-command-line)
8. [Snapshots: keeping track of what changed](#8-snapshots-keeping-track-of-what-changed)
9. [Reviewing your changes and saying why](#9-reviewing-your-changes-and-saying-why)
10. [The Evolution panel: history, darlings and notes](#10-the-evolution-panel-history-darlings-and-notes)
11. [Formatting with Markdown](#11-formatting-with-markdown)
12. [Statistics: analysing your prose](#12-statistics-analysing-your-prose)
13. [Exporting and backing up](#13-exporting-and-backing-up)
14. [A revision session, start to finish](#14-a-revision-session-start-to-finish)
15. [Settings](#15-settings)
16. [Troubleshooting and questions](#16-troubleshooting-and-questions)
17. [Key reference](#17-key-reference)

---

## 1. The idea in one minute

Most editors make you think in characters: click here, drag to there, press delete. Thesis lets
you think in the units you actually write in: **words, clauses, sentences and paragraphs**.

Thesis has three modes:

| Mode       | What it's for                                                                             | Border colour |
| ---------- | ----------------------------------------------------------------------------------------- | ------------- |
| **Insert** | Writing. Ordinary typing, exactly like any Mac text editor.                               | green         |
| **Normal** | Moving and editing by unit: "next sentence", "delete this clause", "move this paragraph". | blue          |
| **Visual** | Selecting whole sentences or paragraphs to act on together.                               | orange        |

You switch between them on purpose. Writing, navigating and revising then feel distinct, and a
single keystroke in Normal mode can do what would take a careful mouse drag elsewhere.

Under the hood, Thesis keeps **snapshots** of your text and works out what changed between
them (sentences added, cut, reworded, rewritten or moved). You can attach a reason to any change
whenever you like. Over time, that builds a record of how your thinking developed.

If you've used Vim, much of this will feel familiar, but you don't need to know Vim at all.

---

## 2. Your first document

Press **⌘N** (or the **+** at the top of the sidebar). Thesis asks for a name; type one and press
Return. You can rename it at any time by clicking the title above the editor, pressing **⇧⌘R**,
or right-clicking it in the sidebar and choosing **Rename…**.

The window has four parts:

- **Sidebar (left).** Your documents. An **orange dot** means the document has changes since its
  last snapshot. Under each title is the name of its latest named snapshot.
- **Header (top).** The title, plus buttons for **Statistics**, **Preview**, **Export** and the
  **Evolution** panel.
- **Editor (middle).** Your text. The coloured border shows the mode.
- **Status bar (bottom).** The mode on the left (`NORMAL`, `INSERT`, `VISUAL`, or what you're
  typing on the command line), then messages or when the last snapshot was taken, and on the right
  the paragraph (¶), sentence (S) and word (W) counts. Click the counts to open Statistics.

A new, empty document opens in **Insert** mode, so you can start typing straight away. A
document that already has text opens in **Normal** mode.

**Saving is automatic.** Every change is saved a second after you stop typing, and again when
you switch documents or quit. There is no "Save" to remember. (⌘S does something else, covered in
[section 9](#9-reviewing-your-changes-and-saying-why).)

---

## 3. Writing: Insert mode

In Insert mode Thesis is an ordinary text editor. Type, use the arrow keys, click with the mouse,
select and delete. Undo is **⌘Z**. Smart quotes, dashes and spell-check work as usual.

When you've finished a stretch of writing, press **ESC**. The border turns blue and you're in
Normal mode.

> **One line is one paragraph.** Press Return once to start a new paragraph. Long lines wrap
> on screen, so there's no need to break them yourself. Blank lines between paragraphs are
> optional. Everything in Thesis (moving by paragraph, statistics, exports) follows this rule.

### Ways into Insert mode

From Normal mode, each of these keys puts you into Insert mode at a useful place:

| Key | Starts typing…                                                           |
| --- | ------------------------------------------------------------------------ |
| `i` | at the cursor                                                            |
| `I` | at the start of the current sentence                                     |
| `a` | in a **new sentence after** the current one (the space is added for you) |
| `A` | at the end of the current paragraph                                      |
| `o` | in a **new paragraph below**                                             |
| `O` | in a new paragraph above                                                 |

If you press `a`, `o` or `O` and then ESC without typing anything, the space or line break that
was added is taken away again.

**Try it.** Type a few sentences, press ESC, then press `a` and type another sentence. It lands
after the sentence the cursor was in, correctly spaced.

---

## 4. Moving around: Normal mode

In Normal mode, letter keys move and act instead of typing. The movement keys come in pairs:
one goes back, the other goes forward.

| Keys       | Move to the previous / next…                                         |
| ---------- | -------------------------------------------------------------------- |
| `h` / `l`  | **sentence**                                                         |
| `H` / `L`  | **clause** (the parts between commas, semicolons, colons and dashes) |
| `k` / `j`  | **paragraph**                                                        |
| `b` / `w`  | **word**                                                             |
| `K` / `J`  | displayed line (follows wrapped lines, like the arrow keys)          |
| `gg` / `G` | top / bottom of the document                                         |
| `[` / `]`  | note (see [section 10](#notes))                                      |

The arrow keys, Home/End and Page Up/Down still work, and so does clicking.

Sentences are the main unit, so they get the easiest keys: `h` and `l`, under your right
hand. `h` goes to the start of the sentence you're in; press it again for the previous one.

**Try it.** In a paragraph of a few sentences, press `l` repeatedly and watch the cursor hop from
sentence to sentence. Press `j` to jump to the next paragraph, and `gg` to return to the top.

---

## 5. Editing whole units

Editing in Normal mode works like a short sentence: a **verb** followed by an **object**.

| Verb | Means                                                          |
| ---- | -------------------------------------------------------------- |
| `d`  | **delete** it (it's kept in the *register*, ready to put back) |
| `c`  | **change** it: delete it and start typing in its place         |
| `y`  | **yank** (copy) it into the register                           |
| `m`  | **mark** it with a note                                        |

| Object | Unit      |
| ------ | --------- |
| `w`    | word      |
| `c`    | clause    |
| `s`    | sentence  |
| `p`    | paragraph |

So `ds` deletes the sentence the cursor is in, `cc` changes the clause, `yp` copies the
paragraph, and `ms` adds a note to the sentence. After you press a verb, a small panel in the
corner lists the objects; press ESC to cancel.

Deleting tidies the spacing for you. Deleting a sentence takes the space after it (or before it,
at the end of a paragraph). Deleting the only sentence in a paragraph removes the paragraph.

### Putting text back: moving sentences and paragraphs

`p` **puts** the register back as a whole unit, **after** the current one; `P` puts it
**before**. A sentence goes after the current sentence; a paragraph goes after the current
paragraph. The spacing is added for you.

That's how you **move** text: cut it, go somewhere else, put it.

- `ds` → move with `l`/`h` → `p`: move a sentence.
- `dp` → move with `j`/`k` → `p`: move a paragraph.

### More editing keys

| Key      | Does                                                                                               |
| -------- | -------------------------------------------------------------------------------------------------- |
| `D`      | delete from the cursor to the end of the sentence                                                  |
| `C`      | change from the cursor to the end of the sentence                                                  |
| `x`      | delete one character (for typos)                                                                   |
| `.`      | **repeat** the last change. After `cs` + typing, `.` replaces another sentence with the same text. |
| `u`      | undo                                                                                               |
| `Ctrl-r` | redo                                                                                               |

> Undoing a `c` change takes two presses of `u`: one undoes what you typed, the next restores the
> text you replaced.

**Try it.** Put the cursor in a sentence you don't like and press `cs`. The sentence disappears
and you're typing in its place. Write the new version and press ESC.

---

## 6. Selecting passages: Visual mode

Press `v` in Normal mode. The current **sentence** is highlighted. Now move:

- `l` / `h` extends the selection sentence by sentence;
- `j` / `k` switches to whole **paragraphs**;
- `w` / `b` switches to **words**.

The selection always covers whole units of whatever you last moved by. When it covers what you
want, press a verb: `d` (or `x`) to delete, `c` to change, `y` to yank, `m` to note it. Press `v`
or ESC to cancel.

Visual mode is also how you **analyse just one passage**. Select it, then press **⇧⌘I** for
statistics on the selection alone (see [section 12](#12-statistics-analysing-your-prose)).

---

## 7. Search and the command line

### Search

Press `/`, type what you're looking for, and press Return. The search ignores capitals. As you
type, the nearest match is highlighted and the status bar shows how many there are. Then:

- `n` jumps to the next match, and `N` to the previous one. Both wrap around the document.
- ESC cancels the search.

### The command line

Press `:` to type a command, then Return. ESC cancels and Backspace edits.

| Command                                                       | Does                                                     |
| ------------------------------------------------------------- | -------------------------------------------------------- |
| `:w`                                                          | review changes and save a named snapshot (same as ⌘S)    |
| `:w First draft`                                              | save a named snapshot called "First draft" straight away |
| `:review`                                                     | review changes since the last named snapshot             |
| `:history`, `:darlings`, `:notes`                             | open the Evolution panel on that tab                     |
| `:rename New title`                                           | rename the document (`:rename` alone asks for a name)    |
| `:preview`                                                    | show the formatted preview                               |
| `:stats`                                                      | open Statistics                                          |
| `:export txt`, `:export md`, `:export pdf`, `:export archive` | export (see [section 13](#13-exporting-and-backing-up))  |
| `:help`                                                       | the quick reference sheet                                |

---

## 8. Snapshots: keeping track of what changed

A **snapshot** is a saved copy of your text at a moment in time. Thesis never records your
individual keystrokes. Instead, it compares snapshots to work out what changed between them.

There are two kinds:

- **Automatic snapshots** are taken quietly while you work. When they're taken is your choice, in
  **Settings** (⌘,):
  - *When I pause writing*: after a set number of seconds without typing (30 by default).
  - *At regular intervals while I write*: every few minutes (10 by default), but only if
    something has changed.
  - *Only when I save one*: no automatic snapshots at all.

  With the first two options, a snapshot is also taken when you switch documents or quit.
- **Named snapshots** are your own checkpoints: "First draft", "After supervisor's comments",
  "Tightened the argument". You make one with **⌘S** or `:w`. Named snapshots are kept forever.

Automatic snapshots are thinned out over time, so they don't pile up. The latest 50 are kept, and
older ones are reduced to one per day. Nothing you've written is lost in the process; see
[Darlings](#darlings).

### How changes are described

Between two snapshots, Thesis matches up sentences and describes each difference in one of five
ways:

| Change        | Meaning                                                                        |
| ------------- | ------------------------------------------------------------------------------ |
| **Added**     | new sentences with no counterpart before                                       |
| **Cut**       | sentences that are gone, with nothing replacing them                           |
| **Reworded**  | the same sentence with its wording adjusted (most words shared)                |
| **Rewritten** | the same spot, but a substantially different sentence (few or no words shared) |
| **Moved**     | the same sentence, now somewhere else                                          |

Thesis works these out by itself; you never have to declare your intent while editing. Several
sentences added or moved together count as one change, so "added a paragraph" appears once,
not five times. Changes in spacing alone are ignored.

---

## 9. Reviewing your changes and saying why

Press **⌘S** (or `:w`, or `:review`). The **Review** sheet lists every change since your last
named snapshot (or since you started, if there isn't one):

- **added** text is shown plainly,
- **cut** text is struck through,
- **reworded** sentences show the words that changed inline (removed in red, added in green),
- **rewritten** sentences show the old version struck through above the new one.

Each change has a **"Why?"** field. Fill in as many or as few as you like: "cut the anecdote, it
buried the point", "reviewer asked for a definition". Reasons are saved as you type, even if
you close the sheet without saving a snapshot.

At the bottom, give the snapshot a **name** (today's date is filled in for you), optionally a
note on what changed in your thinking, and press **Save Snapshot** (⌘Return).

This is the heart of Thesis. You write freely, and when you're ready, you look back at what you
did and record why. The reasons stay attached to their changes in the history and next to
anything you cut.

---

## 10. The Evolution panel: history, darlings and notes

Press **⌘E** (or click **Evolution** in the header) to open the panel on the right. It has three
tabs.

### History

- **Now** at the top summarises your changes since the last named snapshot, with a **Review…**
  button.
- Each **named snapshot** shows its name, date and note, and a summary like "3 added, 2 reworded,
  1 cut". Expand **the summary** to see each change and its reason.
- Runs of **automatic snapshots** are folded into one row; expand it to see them.
- **Restore** puts a snapshot's text back in the editor. Before restoring, Thesis takes a safety
  snapshot of your current text, and the restore itself can be undone with `u`, so restoring is
  never a risk.

<a id="darlings"></a>

### Darlings

"Kill your darlings" is old writing advice: cut the lines you love if they don't serve the work.
Thesis makes that easier, because nothing you cut is ever thrown away.

Whenever a snapshot is taken, every sentence that was **cut** or **rewritten** since the previous
snapshot is kept here, along with the date and, for rewrites, what replaced it. If you gave the
change a reason, that's shown too.

- **Put in register** loads it into the register, so press `p` in the editor to put it back where
  you want it.
- **Copy** puts it on the clipboard.

> Darlings are collected when snapshots are taken. With the *Only when I save one* setting, text
> you add and then cut between two named snapshots never reaches Darlings.

<a id="notes"></a>

### Notes

Notes are comments attached to your text, like margin notes.

- In Normal mode, press `m` followed by an object: `mw`, `mc`, `ms` or `mp` notes a word, clause,
  sentence or paragraph. In Visual mode, `m` notes the selection.
- Choose a kind (**Note**, **Question** or **To do**), write the note, and press ⌘Return.
- Text with an open note gets a dotted purple underline.
- `]` and `[` jump to the next and previous note in the text.

In the Notes tab you can jump to a note's text (the location icon), **Resolve** or **Reopen** it,
or delete it. Notes stay attached to their words as you edit around them. If you delete the
annotated text entirely, the note is kept and marked **"text removed"**. If the text comes back
(through undo or `p`), the note reattaches.

---

## 11. Formatting with Markdown

Thesis uses **Markdown** for formatting: plain-text marks that indicate structure and emphasis.

| You type                           | You get                                                 |
| ---------------------------------- | ------------------------------------------------------- |
| `# Heading`                        | a heading (`##` and `###` for smaller levels)           |
| `**bold**`                         | **bold**                                                |
| `*italic*` or `_italic_`           | *italic*                                                |
| `~~struck~~`                       | ~~struck through~~                                      |
| `` `code` ``                       | `code`                                                  |
| `- item` or `1. item`              | bulleted or numbered lists (indent with spaces to nest) |
| `> quoted`                         | a block quote                                           |
| `[text](https://example.com)`      | a link                                                  |
| a line of ` ``` ` before and after | a code block                                            |
| `---` on its own line              | a horizontal rule                                       |

**While you write**, Thesis formats the text in place: headings are larger, bold is bold, and so
on. The Markdown characters stay visible but faint, so what you see is exactly what's in your
text. To turn this off, go to **Settings ▸ Format Markdown while writing**.

**To see the finished result**, press **⇧⌘P** (or click **Preview**, or type `:preview`). The
editor is replaced by the formatted document with its title. In the preview:

- `j`/`k` or the arrow keys scroll, space pages down (shift-space pages up), and `gg`/`G` go to
  the top and bottom.
- Links can be clicked.
- **ESC** (or ⇧⌘P) takes you back to your text, with the cursor and undo history just as you left
  them.

> In standard Markdown, consecutive lines join into one paragraph. Thesis keeps its own rule (one
> line, one paragraph), and the preview, PDFs and `.md` exports follow it. List items, table rows
> and code blocks stay together as you'd expect.

---

## 12. Statistics: analysing your prose

Press **⇧⌘I**, click the chart button in the header, type `:stats`, or click the counts in the
status bar.

### Choosing what to analyse

The picker at the top sets the **scope**:

- **Document**: everything.
- **This paragraph**: the paragraph the cursor is in.
- **Selection**: a passage you selected in Visual mode. Select it with `v`, then press ⇧⌘I, and
  the sheet opens on Selection automatically. If a selection starts or ends mid-sentence, it's
  widened to whole sentences.

Counts include everything in scope. All other figures cover **prose only**: headings, code
blocks, tables and horizontal rules are left out, so a `## Method` heading doesn't count as a
two-word sentence.

### What you'll see

**Totals.** Words, sentences, paragraphs, characters (with and without spaces), and reading time
(at 238 words a minute).

**Lengths.** For words per sentence, words per paragraph and sentences per paragraph:

| Figure                      | Tells you                                                                                   |
| --------------------------- | ------------------------------------------------------------------------------------------- |
| **Mean**                    | the average                                                                                 |
| **Min**, **Max**, **Range** | the shortest, the longest, and the gap between them                                         |
| **Q1**, **Median**, **Q3**  | a quarter are shorter than Q1, half shorter than the median, three-quarters shorter than Q3 |
| **IQR**                     | Q3 − Q1: how spread out the typical half of your sentences is                               |
| **SD**                      | standard deviation: overall variety in length                                               |

The small **box plot** draws the same figures. The line spans min to max, the box spans Q1 to Q3,
the stroke is the median, and the dot is the mean. A narrow box means very uniform sentences. A
mean well above the median means a few very long sentences are pulling the average up.

Quartiles are interpolated (the same method as Excel's QUARTILE.INC), so they can fall between
whole numbers, e.g. 12.5.

**Sentence lengths (histogram).** How many sentences fall into each band: 1–5 words, 6–10, and
so on up to 41+. Good prose usually has a spread. A single tall bar suggests a monotonous rhythm.

**Runs of similar-length sentences.** Three or more sentences in a row whose lengths are all
within 2 words of each other, such as `14 · 15 · 13 · 14 words`. These are the passages that
sound flat when read aloud. Click one to select it in the editor.

**Most-used words.** Your most frequent words, with common words like "the", "and" and "was" left
out. Words writers often overuse ("just", "really", "very", "actually") are kept on purpose.
Click a word to find it in the text, then press `n`/`N` to step through every place you used it.

**Sentence openers.** How often each first word starts a sentence, e.g. "The · 12 · 34%". Below
that, **In a row** flags streaks like "4 in a row start with I", which you can click to jump to.

**Longest sentences.** The five longest, with their lengths. Click one to go straight to it,
usually to split it.

### Copying the numbers out

**Copy as Table** (bottom left) copies the statistics in the current scope:

- **All Statistics**: every section above.
- **Summary**: the totals and the lengths table, the usual choice for a report.
- **Sentence Lengths**: one row per sentence (number, paragraph, words, text), as raw data for your
  own charts.
- **Save All as CSV…**: everything as a file.

Paste into **Word** or **Pages** to get real tables. Paste into **Excel** or **Numbers** to get
one value per cell, ready for formulas and charts. Numbers follow your Mac's regional format.

> The common-word list is English. Words aren't reduced to their root, so "write", "writes" and
> "writing" are counted separately.

---

## 13. Exporting and backing up

### Exporting your current text

Choose **File ▸ Export**, the **Export** button in the header, **Export** in the sidebar's
right-click menu, or a `:export` command:

| Format                | Contains                                                                                            |
| --------------------- | --------------------------------------------------------------------------------------------------- |
| **Plain text (.txt)** | your text exactly as written, including any Markdown marks                                          |
| **Markdown (.md)**    | the title as a heading, then your text, set up so other Markdown apps show the same paragraphs      |
| **PDF**               | the formatted document (as in the preview), on pages with margins, black on white even in dark mode |

### Archives: backups with full history

A **Thesis Archive (.thesis)** contains *everything* about a document: the text, every snapshot,
your reasons, darlings and notes.

- **Export ▸ Thesis Archive** (or `:export archive`) saves one document.
- **File ▸ Back Up All Documents…** saves all of them in one dated file. It's worth doing now and
  then and keeping the file somewhere safe.
- **To restore**, double-click a `.thesis` file in Finder, drag it onto Thesis in the Dock, or use
  **File ▸ Import Archive…**.

If an imported document is already in your library, you can choose:

- **Keep Both**: the imported copy is added with "(archived)" after its title.
- **Replace**: your current copy is replaced by the archived one.
- **Skip**: nothing changes.

**Import Archive…** also accepts Thesis's own `documents.json` file (see
[section 16](#16-troubleshooting-and-questions)), so any copy of your data can be brought back.

---

## 14. A revision session, start to finish

Here's how the pieces fit together on a real revision. Say you have a draft essay and a
named snapshot from yesterday called "First draft".

1. **Read through in Normal mode.** Use `j` to go paragraph by paragraph and `l` to go sentence by
   sentence. Press `ms` on anything to come back to, and choose *To do*.
2. **Check the mechanics.** Press ⇧⌘I. The longest sentence is 52 words; click it to jump there.
3. **Split it.** Press `cs`, type it again as two sentences, and press ESC.
4. **Fix the rhythm.** Back in Statistics, a run of four 14-word sentences is flagged. Click it,
   then shorten one sentence with `C` and combine two others.
5. **Cut what isn't working.** An anecdote in paragraph three doesn't earn its place, so put the
   cursor in it and press `dp`. It's safe: it will be in Darlings.
6. **Reorder.** The conclusion's second paragraph belongs earlier. Use `dp`, go there with `k`,
   then press `P` to put it before that paragraph.
7. **Work through your notes.** Press `]` to visit each to-do, then resolve it in the Notes tab
   (⌘E).
8. **Review and record.** Press ⌘S. The Review sheet shows a rewritten sentence, a moved paragraph
   and a cut paragraph. Next to the cut, write "anecdote was charming but off-topic". Name the
   snapshot "Second draft" and save.
9. **Check the result.** Press ⇧⌘P to read the formatted version, then ESC to return.
10. **Share or back up.** Export a PDF for a reader, and back up all documents as an archive.

A month later, the History tab shows the essay's evolution draft by draft, and the anecdote is
still waiting in Darlings, with your reason for cutting it.

---

## 15. Settings

Open **Thesis ▸ Settings…** (⌘,).

- **Take snapshots**: *When I pause writing* (with how many seconds), *At regular intervals while
  I write* (with how many minutes), or *Only when I save one*. See
  [section 8](#8-snapshots-keeping-track-of-what-changed).
- **Format Markdown while writing**: on or off. The preview and PDFs are always formatted.

The Evolution panel's open/closed state is remembered between sessions.

---

## 16. Troubleshooting and questions

**Where are my documents stored?**
All documents are stored together in one file, `documents.json`, which is saved automatically.
In a sandboxed build (the default) it's in
`~/Library/Containers/<the app's bundle identifier>/Data/Library/Application Support/Thesis/`,
and otherwise in `~/Library/Application Support/Thesis/`. You don't need to touch it; use
**Back Up All Documents…** for backups.

**Thesis said it couldn't open my documents.**
If the file can't be read, Thesis doesn't overwrite it. It saves a copy called
`documents-unreadable-<date>.json` next to the original and tells you where it is. You can bring
that copy back in with **File ▸ Import Archive…**.

**Export says it can't show a save panel.**
The app needs permission to write the files you choose. In Xcode, go to **Signing & Capabilities ▸
App Sandbox ▸ File Access ▸ User Selected File** and set it to **Read/Write**.

**Double-clicking a .thesis file doesn't open Thesis.**
Run Thesis once so macOS registers it. If Finder still offers another app, right-click the file
and choose **Open With ▸ Thesis**.

**A key does nothing.**
Check the mode in the status bar. Letter keys type in Insert mode and act in Normal mode. After
a verb (`d`, `c`, `y`, `m`), Thesis waits for an object (`w`, `c`, `s`, `p`); press ESC to cancel.

**Why is undo two steps after `c`?**
The change is recorded as two edits: removing the old text, then your typing. Press `u` twice.

**Does it work in languages other than English?**
Sentence and word detection use Apple's language tools and work for many languages. The
common-word filter in Statistics is English only.

---

## 17. Key reference

### Modes

| Key                     | From                                 | Does                                                                                                 |
| ----------------------- | ------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| ESC                     | Insert, Visual, command line, search | back to Normal                                                                                       |
| `i` `I` `a` `A` `o` `O` | Normal                               | Insert at cursor / sentence start / new sentence after / paragraph end / new paragraph below / above |
| `v`                     | Normal                               | Visual (selects the current sentence)                                                                |
| `:`                     | Normal                               | command line                                                                                         |
| `/`                     | Normal                               | search                                                                                               |

### Moving (Normal and Visual)

| Keys     | Previous / next |
| -------- | --------------- |
| `h` `l`  | sentence        |
| `H` `L`  | clause          |
| `k` `j`  | paragraph       |
| `b` `w`  | word            |
| `K` `J`  | displayed line  |
| `gg` `G` | top / bottom    |
| `[` `]`  | note            |
| `N` `n`  | search match    |

### Editing (Normal)

| Keys                              | Does                                                              |
| --------------------------------- | ----------------------------------------------------------------- |
| `d` `c` `y` `m` + `w` `c` `s` `p` | delete / change / yank / note a word, clause, sentence, paragraph |
| `p` `P`                           | put the register after / before the current unit                  |
| `D` `C`                           | delete / change to end of sentence                                |
| `x`                               | delete a character                                                |
| `.`                               | repeat the last change                                            |
| `u`, `Ctrl-r`                     | undo, redo                                                        |

### In Visual mode

| Keys                      | Does                                     |
| ------------------------- | ---------------------------------------- |
| motions                   | extend the selection by whole units      |
| `d` or `x`, `c`, `y`, `m` | delete, change, yank, note the selection |
| `v`, ESC                  | leave Visual mode                        |

### Shortcuts

| Shortcut | Does                                     |
| -------- | ---------------------------------------- |
| ⌘N       | new document                             |
| ⇧⌘R      | rename document                          |
| ⌘S       | review changes and save a named snapshot |
| ⌘E       | show / hide the Evolution panel          |
| ⇧⌘P      | preview                                  |
| ⇧⌘I      | statistics                               |
| ⌘Z, ⇧⌘Z  | undo, redo (in any mode)                 |
| ⌘,       | settings                                 |

### Commands

`:w` · `:w name` · `:review` · `:history` · `:darlings` · `:notes` · `:rename [title]` ·
`:preview` · `:stats` · `:export txt|md|pdf|archive` · `:help`

---

*For how Thesis is built (its data model, the change classifier, and the design decisions
behind them), see [DESIGN.md](DESIGN.md).*
