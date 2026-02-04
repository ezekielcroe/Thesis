# Thesis MVP - Modal Editor for Version-Controlled Writing

## What This Is

A complete specification and implementation roadmap for building a production-quality modal text editor with version control for prose writing.

**Status:** Ready to build (Specification complete, ~2-3 weeks development time)

## Quick Links

- **[MVP_SPECIFICATION.md](./MVP_SPECIFICATION.md)** - Complete feature specification
- **[IMPLEMENTATION_ROADMAP.md](./IMPLEMENTATION_ROADMAP.md)** - 14-day development plan

## Core Concept

### The Problem
Writers need version control like developers have Git, but current tools either:
- Don't track evolution of thinking (Notion, Google Docs)
- Require technical knowledge (Git + Markdown)
- Focus on code, not prose (every IDE)

### The Solution
**Thesis** - A modal editor with three modes:

```
INSERT (Green)  → Write freely
   ↓ ESC
EDIT (Blue)     → Navigate and refine with Vim-like commands
   ↓ :comp
COMPARE (Orange) → Review changes with git-style diffs
   ↓ :print
SAVE DRAFT      → Commit with meaningful comment
```

## Key Features

### 1. Modal Editing Optimized for Prose

**Not just Vim for writing** - Commands are prose-aware:

| Command | Action | Why It's Different |
|---------|--------|-------------------|
| `h` / `l` | Previous/Next **Sentence** | Not character |
| `j` / `k` | Previous/Next **Paragraph** | Not line |
| `das` | Delete Around **Sentence** | Atomic thought unit |
| `cw` | Change **Word** (exits on space) | Constrained |
| `cas` | Change Around **Sentence** (exits on punctuation) | Constrained |

**Constrained Insert Modes** prevent mindless typing:
- `i` - insert one word (exits on space)
- `a` - append sentence (exits on punctuation)
- `cw` - change word (exits on space)

### 2. Version Control That Makes Sense

**Drafts, not Commits:**
- "First Draft" - Your initial thoughts
- "Draft 2: Added Evidence" - Refined with sources
- "Draft 3: Counterarguments" - Explored alternatives

**Compare View:**
- See exactly what changed
- Red strikethrough for deletions
- Green highlight for additions
- Navigate changes with `n`/`p`

### 3. Sentence-Level Thinking

**Why sentences?**
- Words are too granular
- Paragraphs are too coarse
- Sentences = atomic units of thought

**Benefits:**
- Navigate by idea, not by line
- Delete/change meaningful chunks
- Diffs show semantic changes

## Technical Approach

### Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Text View | NSTextView | Only option for cursor control + keyboard events |
| Command Parsing | Simple buffer | Commands are short, no nesting needed |
| Diff Algorithm | Swift Difference API | Good enough for MVP, can upgrade later |
| State Management | Single AppState | Centralized, easy to debug |
| Persistence | UserDefaults | Zero setup, works immediately |
| Sentence Detection | NLTagger | Native, ~95% accurate, handles edge cases |

### Why NSTextView?

SwiftUI's `TextEditor` doesn't expose:
- Cursor position (can't implement navigation)
- Keyboard events (can't intercept commands)
- Text attributes (can't render diffs)

NSTextView via NSViewRepresentable provides:
- `selectedRange` property for cursor
- `keyDown` override for commands
- `NSAttributedString` for diff highlighting

### Project Structure

```
Models/           # Document, Draft, EditCommand
State/            # AppState (central state management)
Views/            # ContentView, EditorView (NSTextView wrapper), Dialogs
Utilities/        # TextAnalyzer (NLTagger), DiffEngine, CommandParser
```

**~15 Swift files total**

## Implementation Timeline

### Week 1: Core Functionality
- **Days 1-3:** Models, state, basic UI, mode switching
- **Days 4-5:** Navigation commands (hjklwb)
- **Days 6-7:** Delete operations (dw, db, D, das, dap)

### Week 2: Advanced Features
- **Days 8-9:** Change/insert commands, undo stack
- **Days 10-12:** Compare mode with diff rendering
- **Days 13-14:** Polish, dialogs, testing

**Deliverable:** Working MVP, ready for user testing

## User Workflow Example

```
1. Open Thesis → New Document
2. [INSERT MODE] - Type: "Distributed systems are more resilient than centralized ones."
3. Press ESC → Prompt: "Save as First Draft?" → Name: "Initial Argument" → Save
4. [EDIT MODE] - Navigate with l (next sentence)
5. Type cas → [CONSTRAINED INSERT] - Change sentence: "Distributed systems provide better fault tolerance."
6. Press . to end sentence → Back to [EDIT MODE]
7. Type :comp → [COMPARE MODE] - See diff with red/green highlighting
8. Press n to jump to changed sentence
9. Type :print → Prompt: "Draft name? Comment?" → Save as "Draft 2: Refined claim"
10. Back to [EDIT MODE] - Continue refining
```

## What Makes This Different

### vs. Notion/Roam
- ✅ Local-first (your data stays yours)
- ✅ Version history is first-class (not buried in menu)
- ✅ Keyboard-driven (no mouse required)

### vs. Obsidian + Git Plugin
- ✅ Sentence-aware commands (not just file-level commits)
- ✅ Integrated diff view (no separate Git client)
- ✅ Prose-optimized (not Markdown-centric)

### vs. Vim/Neovim
- ✅ Built for writing, not coding
- ✅ Constrained insert modes (prevents overwriting)
- ✅ Native macOS app (not terminal)

### vs. Scrivener
- ✅ Modal editing (faster for power users)
- ✅ True version control (not just snapshots)
- ✅ Diff view (see what changed)

## Success Criteria

After 2 weeks of user testing, this MVP succeeds if:

**Usability**
- [ ] Users can navigate 500-word doc faster with keyboard than mouse
- [ ] Modal switching becomes muscle memory within 30 minutes
- [ ] 60%+ of testers prefer it to their current tool

**Value**
- [ ] Users actually review their draft history
- [ ] Compare view provides "aha!" moments
- [ ] Constrained insert modes feel purposeful, not limiting

**Adoption**
- [ ] 40%+ would pay $20 for this
- [ ] Generates word-of-mouth interest
- [ ] Feature requests are enhancements, not basics

## Target Users

### Primary
- **Academic Researchers** - writing papers with evolving arguments
- **Technical Writers** - documenting complex systems
- **Essayists/Bloggers** - refining arguments over time

### Secondary
- **Vim Users** - who write prose, not just code
- **Knowledge Workers** - who think by writing
- **Students** - writing thesis or dissertations

### Not For
- Quick note-takers (too much ceremony)
- Casual users (learning curve too steep)
- Collaborative writers (single-user focused)

## Risks & Mitigations

### High Risk: NSTextView Keyboard Handling
**Risk:** Can't reliably intercept all keys in EDIT mode  
**Mitigation:** Prototype this on Day 1-2; if fails, reconsider architecture

### Medium Risk: Constrained Insert Complexity
**Risk:** Hard to implement "insert one word" reliably  
**Mitigation:** Simplify to just blocking navigation, allow longer input

### Medium Risk: Diff Performance
**Risk:** Attributed string generation lags on large documents  
**Mitigation:** Profile early, simplify to line-level diffs if needed

### Low Risk: Everything Else
- Model/state management: Standard patterns
- Persistence: UserDefaults is reliable
- UI layout: SwiftUI is mature

## What's in This Package

### Specification Documents
1. **MVP_SPECIFICATION.md** (9,000 words)
   - Complete feature breakdown
   - Mode specifications
   - Command reference
   - Data models
   - UI mockups
   - Testing checklist

2. **IMPLEMENTATION_ROADMAP.md** (6,000 words)
   - Architecture decisions
   - 14-day development plan
   - Technical challenges
   - Risk assessment
   - File structure
   - Decision points

3. **README.md** (This file)
   - High-level overview
   - Comparative analysis
   - Success criteria

### Total: ~18,000 words of documentation

## Next Steps

### If You're Ready to Build

1. **Day 1:** Read both spec docs completely
2. **Day 2:** Set up Xcode project, create basic models
3. **Day 3:** Prototype NSTextView keyboard handling (CRITICAL)
4. **Day 4+:** Follow the 14-day roadmap

### If You Want to Validate First

1. **Mock it up:** Create non-functional prototype with fake commands
2. **Test with 5 users:** Does the concept resonate?
3. **Iterate:** Refine based on feedback
4. **Then build:** Full implementation with confidence

### If You're Unsure

**Questions to ask yourself:**
1. Would I use this daily for my own writing?
2. Can I commit 2-3 weeks of focused development?
3. Am I comfortable with a niche/power-user product?
4. Do I have 5-10 people who'd beta test?

If 3+ are "yes" → Build it  
If 1-2 are "yes" → Iterate the concept first  
If 0 are "yes" → Reconsider

## Cost-Benefit Analysis

### Investment
- **Development:** 2-3 weeks (80-120 hours)
- **Testing:** 1 week with 5-10 users
- **Total:** ~1 month, $0 cost (your time only)

### Potential Return
- **Learn:** Deep experience with NSTextView, NLTagger, diff algorithms
- **Validate:** Proof that modal editing works for prose (or doesn't)
- **Product:** If successful, could be commercial app ($20-50 price point)
- **Portfolio:** Unique project that demonstrates vision + execution

### Alternative (Not Building)
- Cost: 0 hours
- Learn: Nothing
- Validate: Never know if it would work
- Product: Idea stays idea

**Analysis:** If you're seriously considering this, the upside far outweighs the 1-month investment.

## Frequently Asked Questions

**Q: Why not just use Git + Markdown?**  
A: Thesis integrates version control at the sentence level with prose-aware commands. Git is file-level and requires command-line knowledge.

**Q: Why modal editing? Isn't that just harder?**  
A: For power users, modal editing is faster once learned. Constrained modes also create intentional "speed bumps" that improve thoughtfulness.

**Q: Will anyone actually use this?**  
A: That's what the MVP validates. If 5 users love it, build more. If 0 do, pivot.

**Q: Can't I just add Vim keybindings to VS Code?**  
A: VS Code is optimized for code. Thesis is prose-aware (sentence/paragraph navigation, diff rendering, draft management).

**Q: What about mobile?**  
A: macOS first. iOS port in Phase 5 (weeks 10-12) if desktop succeeds.

**Q: How do you handle merge conflicts in prose?**  
A: MVP doesn't support branching/merging. That's Phase 2. For now, drafts are linear.

**Q: What if NLTagger doesn't detect sentences well?**  
A: It's ~95% accurate. For edge cases (e.g., "Dr. Smith"), users can work around. Perfect detection isn't required for MVP.

## Conclusion

You've taken an ambitious idea and refined it into a **buildable MVP**.

**The good:**
- Concept is novel and defensible
- Technical approach is sound
- Scope is focused (no feature creep)
- Timeline is realistic
- Documentation is thorough

**The challenge:**
- Modal editing is niche
- Learning curve is steep
- Requires focus and commitment

**The verdict:**
If you're passionate about this, **build it**. The worst outcome is you learn a ton. The best outcome is you create something genuinely useful that doesn't exist yet.

---

## Contact & Feedback

This specification was created to help you make an informed decision about building Thesis.

**If you build this:**
- I'd love to see it! Share progress if you're comfortable
- Consider making it open source (great for community)
- Beta test with diverse users (not just Vim users)

**If you don't build this:**
- The specs might be useful for other projects
- The architectural decisions apply broadly
- Modal editing principles transfer to other domains

Good luck! 🚀
