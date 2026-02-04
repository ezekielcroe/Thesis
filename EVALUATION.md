# Thesis MVP Evaluation Framework

## Purpose

This MVP validates **3 critical hypotheses** before full production:

1. **Modal editing is superior for prose** (not just code)
2. **Version control provides value for thoughts** (not just files)  
3. **Sentence-level granularity matches cognition** (not words/paragraphs)

## Evaluation Structure

### Week 1: Solo Testing (You)
### Week 2-3: User Testing (10 people)
### Week 4: Decision Point

---

## Week 1: Solo Testing Protocol

### Day 1: Learning Curve
**Goal:** Assess time-to-proficiency

**Tasks:**
1. Complete welcome document tutorial (time it)
2. Create test document with provided template
3. Practice each command 5x
4. Write 500-word document about any topic

**Metrics:**
- Time to memorize hjklwb: ___ minutes
- Time to feel comfortable with d commands: ___ minutes
- Time to understand :comp: ___ minutes
- Mouse clicks during writing: ___ (goal: <10)

**Questions:**
- Which commands felt natural immediately?
- Which commands felt awkward?
- Did you forget which mode you were in?
- How many times did you reach for mouse?

### Day 2: Real Work
**Goal:** Test utility for actual tasks

**Tasks:**
1. Use Thesis for ALL note-taking today
2. Create 3+ documents (meeting notes, todo, ideas)
3. Save at least 2 drafts per document

**Metrics:**
- Documents created: ___
- Drafts saved: ___
- Times you opened :comp: ___
- Times you restored old draft: ___

**Questions:**
- Did modal editing slow you down or speed you up?
- Did you look at draft history? Why/why not?
- What features did you miss from other tools?
- Would you use this tomorrow?

### Day 3: Complex Editing
**Goal:** Stress-test command repertoire

**Tasks:**
1. Write 1000+ word essay
2. Heavy editing session (50+ commands)
3. Intentionally create 5 drafts
4. Use :comp after each draft

**Metrics:**
- Total words written: ___
- Commands used (from most to least frequent):
- Undo commands used: ___
- Drafts that provided insight: ___

**Questions:**
- Which commands did you use most?
- Which commands did you avoid? Why?
- Did constrained insert (i/a) feel helpful or restrictive?
- Did seeing diffs change your editing behavior?

### Day 4: Edge Cases
**Goal:** Find breaking points

**Tasks:**
1. Test abbreviations (Dr., U.S.A., etc.)
2. Test very long sentences (100+ words)
3. Test rapid command sequences
4. Test 10+ undo chain

**Metrics:**
- Sentence detection errors found: ___
- Times undo didn't work as expected: ___
- Performance issues (lag >1s): ___
- Crashes or data loss: ___

**Questions:**
- What edge cases did you find?
- How accurate was sentence detection?
- Did undo always work correctly?
- Any data loss or corruption?

### Day 5: Comparison
**Goal:** Benchmark against existing tools

**Tasks:**
1. Morning: Use Thesis for work
2. Afternoon: Use your usual tool (Notion/Obsidian/etc.)
3. Evening: Direct comparison

**Metrics:**
- Thesis words per hour: ___
- Usual tool words per hour: ___
- Thesis edits per hour: ___
- Usual tool edits per hour: ___

**Questions:**
- Which felt faster for writing?
- Which felt faster for editing?
- Which would you choose for which tasks?
- What's Thesis's killer feature?

### Week 1 Summary

**Hypothesis 1: Modal editing for prose**
- [ ] Modal editing felt natural after Day 1
- [ ] Navigated faster than with mouse
- [ ] Editing felt more intentional
- [ ] Would use for serious writing

Score: ___/4 (need 3/4 to validate)

**Hypothesis 2: Version control value**
- [ ] Looked at draft history multiple times
- [ ] Restored old version at least once
- [ ] :comp diff influenced editing decisions
- [ ] Gained insight from seeing evolution

Score: ___/4 (need 3/4 to validate)

**Hypothesis 3: Sentence granularity**
- [ ] h/l felt more natural than arrow keys
- [ ] Sentence = right unit for navigation
- [ ] das/cas commands felt powerful
- [ ] Would want character-level less than 20% of time

Score: ___/4 (need 3/4 to validate)

---

## Week 2-3: User Testing Protocol

### Recruitment (10 Users)

**Group A: Power Users (3 people)**
- Comfortable with Vim/command-line
- Developers or technical writers
- Existing modal editing experience

**Group B: Knowledge Workers (4 people)**
- Writers, researchers, analysts
- Use tools like Notion/Obsidian
- No Vim experience

**Group C: Casual Users (3 people)**
- Students or light note-takers
- Basic tool users (Apple Notes, Word)
- Minimal keyboard shortcuts

### Testing Session (60 minutes per user)

#### Part 1: Tutorial (10 min)
1. Show welcome document
2. Demonstrate mode switching
3. Show 5 core commands: h, l, dw, cw, :comp
4. Let them try each command once

#### Part 2: Guided Task (20 min)
**Task:** Write an argument with thesis statement

1. "Write 2-3 paragraphs arguing for or against remote work"
2. After writing, press ESC to save First Draft
3. Make 3 edits using d/c commands
4. Use :comp to review changes
5. Save as Draft 2 with comment

**Observe:**
- Mode confusion
- Command recall
- Frustration points
- Aha moments

#### Part 3: Free Exploration (20 min)
"Now write about anything you want. Try different commands."

**Observe:**
- Which commands they gravitate to
- Mouse usage
- Mode switching frequency
- Draft creation behavior

#### Part 4: Interview (10 min)

**Usability Questions:**
1. On a scale of 1-10, how intuitive was modal editing?
2. Which commands felt natural? Which felt forced?
3. How long would it take to become proficient?
4. What was most confusing?

**Value Questions:**
1. Would you use draft history if this were your tool?
2. Did :comp provide value?
3. Would you switch from your current tool?
4. What's missing that would make you switch?

**Comparison Questions:**
1. How does this compare to [their tool]?
2. What would you use Thesis for?
3. Would you pay for this? How much?
4. Would you recommend it?

### User Testing Metrics

**Quantitative:**

| Metric | Group A | Group B | Group C | Goal |
|--------|---------|---------|---------|------|
| Time to complete tutorial | ___ min | ___ min | ___ min | <5 min |
| Commands memorized after 20 min | ___ / 10 | ___ / 10 | ___ / 10 | >6 |
| Mode confusion incidents | ___ | ___ | ___ | <3 |
| Mouse clicks during task | ___ | ___ | ___ | <20 |
| Completed draft cycle | ___% | ___% | ___% | >70% |
| Would use again | ___% | ___% | ___% | >50% |

**Qualitative:**

Common positive feedback:
1. ___
2. ___
3. ___

Common negative feedback:
1. ___
2. ___
3. ___

Surprising insights:
1. ___
2. ___
3. ___

---

## Week 4: Decision Point

### Data Analysis

**Hypothesis 1: Modal editing for prose**

Evidence FOR:
- Users who said modal felt natural: ___/10
- Users who navigated faster than mouse: ___/10
- Users who would use for writing: ___/10

Evidence AGAINST:
- Users who found it too complex: ___/10
- Users who preferred traditional editing: ___/10
- Mode confusion incidents: ___ (>30 = problem)

**Verdict:** Pass / Fail / Needs Iteration
**Reasoning:** ___

**Hypothesis 2: Version control value**

Evidence FOR:
- Users who used draft history: ___/10
- Users who restored old version: ___/10
- Users who said :comp was valuable: ___/10

Evidence AGAINST:
- Users who never looked at history: ___/10
- Users who saw no value in drafts: ___/10
- "Why not just use Undo?" responses: ___/10

**Verdict:** Pass / Fail / Needs Iteration
**Reasoning:** ___

**Hypothesis 3: Sentence granularity**

Evidence FOR:
- Users who preferred h/l over arrows: ___/10
- Users who said sentences = right unit: ___/10
- Users who used das/cas effectively: ___/10

Evidence AGAINST:
- Users who wanted character-level: ___/10
- Sentence detection errors reported: ___
- Users who preferred paragraph-level: ___/10

**Verdict:** Pass / Fail / Needs Iteration
**Reasoning:** ___

### Decision Matrix

| Hypotheses Validated | Decision | Next Steps | Timeline |
|---------------------|----------|------------|----------|
| 3/3 Pass | **BUILD IT** | Full production development | 3-4 months |
| 2/3 Pass | **ITERATE** | Fix failing hypothesis, re-test | 1 month |
| 1/3 Pass | **PIVOT** | Keep what works, rebuild rest | 2 months |
| 0/3 Pass | **STOP** | Concept not viable | - |

### Build Decision (3/3 Pass)

**Investment Required:**
- Time: 400-500 hours (3-4 months full-time)
- Money: $0 (self-development) or $30-50k (contractor)
- Risk: Medium (validated concept, execution risk remains)

**Success Criteria:**
- 100+ beta users
- 4.0+ star rating
- 30%+ retention after 1 month
- $20-30 price point validated

**Go/No-Go Decision:**
- [ ] I can commit 3-4 months
- [ ] I have 10+ committed beta testers
- [ ] I'm excited to build this
- [ ] Market research shows gap exists

If all checked → **BUILD**

### Iterate Decision (2/3 Pass)

**Which hypothesis failed?** ___

**Why did it fail?**
- User feedback: ___
- Observation: ___
- Metrics: ___

**Proposed changes:**
1. ___
2. ___
3. ___

**Re-test plan:**
- Fix in: ___ weeks
- Test with: ___ users
- Target metrics: ___

**Go/No-Go Decision:**
- [ ] Changes are feasible
- [ ] Core concept still valid
- [ ] Users want to re-test
- [ ] I believe in fixes

If all checked → **ITERATE**

### Pivot Decision (1/3 Pass)

**What worked?** ___
**What didn't?** ___

**Pivot options:**
1. Keep version control, drop modal editing
2. Keep modal editing, simplify version control
3. Reframe as plugin for existing tool
4. Target different user segment

**Chosen pivot:** ___

**Rationale:** ___

### Stop Decision (0/3 Pass)

**Why did it fail?**
- User feedback: ___
- Fundamental flaw: ___
- Better alternatives exist: ___

**Lessons learned:**
1. ___
2. ___
3. ___

**Alternative paths:**
1. ___
2. ___

---

## Success Indicators Summary

### Must Have (Non-negotiable)
- [ ] Zero data loss across all testing
- [ ] <3 crashes per user session
- [ ] Commands work as documented
- [ ] Modal switching reliable

### Should Have (Important)
- [ ] 70%+ complete draft cycle in testing
- [ ] 50%+ say they would use again
- [ ] 60%+ prefer to mouse for navigation
- [ ] Average 7+/10 on intuitiveness

### Nice to Have (Bonus)
- [ ] Users discover commands without docs
- [ ] Organic "aha moments" reported
- [ ] Users describe it positively to others
- [ ] Requests for iOS version

### Red Flags (Stop Signals)
- [ ] >50% say "too complex"
- [ ] >50% prefer traditional editing
- [ ] Nobody uses draft history
- [ ] "Why not just use X?" with no answer

---

## Final Question

After 4 weeks of testing:

> "If I could only use Thesis (no other note apps) for the next 3 months, would I feel empowered or constrained?"

**Empowered → BUILD**
**Neutral → ITERATE**
**Constrained → PIVOT or STOP**

---

## Documentation

Keep detailed notes:
- User session recordings (with permission)
- Command frequency logs
- Mode transition graphs
- Draft creation patterns
- Qualitative feedback themes

Store in:
- `/testing-data/week-1/`
- `/testing-data/week-2/`
- `/testing-data/analysis/`

This data informs:
- Feature prioritization
- UI improvements
- Tutorial design
- Marketing positioning
