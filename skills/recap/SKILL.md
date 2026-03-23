---
name: recap
description: Cycle review — RECAP, IMPROVE, CLOSING phases. Activate after IMPLEMENT is complete.
---

# Cycle Review

EVERY RESPONSE STARTS WITH A PHASE INDICATOR:
- `🔍 RECAP` - Report phase (Plan Mode active - read-only enforced)
- `🛠️ IMPROVE` - Improvements phase
- `✅ CLOSING` - Cycle completion

**Phase Detection:** System message contains "Plan mode is active" → you are in RECAP.

---

## Recap Phase (RECAP)

### Phase Entry

1. Ask user: "Activate Plan Mode for RECAP (`/plan`)"
2. Wait for Plan Mode system message
3. Proceed with evaluation report (read-only enforced by Plan Mode)

### Plan File Handling

**CRITICAL:** Report OVERWRITES plan file completely.

- **Open items:** Listed in "## Open Items" section → handled in CLOSING phase (Bead or discard)
- **No "ORIGINAL PLAN" section** - plan is consumed by execution

### Report

Claude writes a report that OVERWRITES the plan file:

#### 1. Session Reflection

Analyze the session across two dimensions:

##### 1.1 Efficiency

**Questions:**
- Were my questions focused or scattered?
- Did we iterate too much? Could we have reached the finished plan faster?
- Did I correctly understand the user's answers?
- Did the user give insightful answers?

**Red Flags:**
- More than 3 back-and-forth exchanges before stable plan
- User had to correct my assumptions multiple times
- I proposed solutions before understanding the problem
- Execution Path Errors (Most IMPLEMENT failures trace back to skipped verification in PLAN)
- User did not explicitly state what he wants, gave bad directions

**References:**
- Did I explicitly ask for references early enough?
- Were the references helpful or did they lead me astray?

##### 1.2 Assumptions/Hallucinations

**Questions:**
- Did I make assumptions that needed correction?
- Was the user's intent clear from the start?
- Did I verify assumptions or just proceed?

**Categories:**
- **Structural:** Directory layout, file locations, naming conventions
- **Semantic:** What columns mean, what functions do, data flow
- **Behavioral:** Expected output format, error handling, edge cases

#### 2. Hooks Evaluation

**Questions:**
- Did a hook block something it shouldn't have?
- Did a hook allow something it should have blocked?
- Is output silencing helping or hiding problems?
- Should a recurring command pattern become a hook rule?

**Token Efficiency Analysis:**
Review Bash tool calls from this session and identify where hooks could have saved tokens:
- Commands with large outputs that could be piped through `head -N` or `tail -N`
- Repeated commands whose output could be cached or silenced after first run
- Commands where only a subset of output was needed

For each finding: estimate token waste (small/medium/large) and propose a hook rule or pattern.

#### 3. Beads Evaluation

Run `bead_list(status="open")` to check open beads, then evaluate:

##### 3.1 Active Beads

For each open bead touched this cycle:
- Was a session-end comment written with STAND block? If not → add in IMPROVE
- Is the latest comment sufficient for a fresh session to continue? If not → improve in IMPROVE

##### 3.2 New Beads

Discovered work that needs cross-session tracking?
- List candidates with proposed title and description
- Title = topic, not date (e.g., "LSP Integration" not "Session 02.03")

##### 3.3 Close Completed Beads

For each bead where the topic is fully resolved:
- Mark for closing with reason
- **Format:** `<id>: <reason>`

##### 3.4 Continuation Check (MANDATORY)

After listing all beads to close: **Would closing them leave ZERO open beads?**

If yes → a Continuation-Bead MUST be created in IMPROVE phase:
- Title: Next work topic (NOT "Session YYYY-MM-DD")
- Description: What was done (context), what's next (scope), key files/repos

##### 3.5 IMPROVE Action List (MANDATORY)

```
BEADS ACTIONS:
- CLOSE: <id> — <reason>
- COMMENT: <id> — <what to write>
- CREATE: "<title>" — <description summary>
```

#### 4. Improvements

Every Process Improvement MUST reference an exact Automation File path + section.
Format: `[Description] → [Automation File path] → [Section to add/extend]`
Automation File locations: see `~/.claude/rules/automation-framework.md`

**READ BEFORE WRITE (MANDATORY):**
Before proposing ANY process improvement: READ the target Automation File. You need to know:
1. What sections already exist (avoid duplicating existing rules)
2. Exact line numbers for insertion points
3. Whether the improvement overlaps with or contradicts existing content

Concrete failure (2026-03-23): Proposed workers.md improvements without reading the file. Would have referenced wrong section names and missed existing "Reusing Workers" content. User had to ask "hast du die automation files gelesen?"

##### 4.1 Content Improvements (Code/Docs)

Prioritization:
- **Critical:** Must fix (breaks functionality, wrong behavior)
- **Important:** Should fix (code quality, maintainability)
- **Optional:** Nice to have

**Handling:** Code → **Bead** (needs own cycle). Docs/README/Automation Files → **Direct Edit** in IMPROVE.

##### 4.2 Process Improvements

Prioritization (by OUTCOME):
- **Critical:** Process errors that WOULD HAVE caused critical code issues
- **Important:** Process errors that caused detours but correct outcome
- **Optional:** Minor process inefficiencies

**Handling:** Same as 4.1 — Code → Bead, Automation Files → Direct Edit.

**Key rules:**
- Process Improvements = Automation Files ONLY. Docs/README = Content Improvements (4.1).
- OUTCOME determines severity. Wrong process + correct result = Important (not Critical).
- Every process error MUST produce a config change. "Lesson Learned" without config change = FAILURE.

**Rule Layers — where to route each improvement:**

| Layer | Path | Scope | When to use |
|-------|------|-------|-------------|
| Global rules | `~/.claude/rules/*.md` | All projects, always loaded | General behavior (communication, verification, scoping) |
| Shared rules | `~/.claude/shared-rules/global/*.md` | Symlinked into projects | Code conventions, project standards |
| Project rules | `<project>/.claude/rules/*.md` | One project only | Project-specific constraints, TUI standards, dev workflows |
| Plugin skills | Plugin source repo `skills/*/SKILL.md` | Activated per-skill | Workflow phases, domain tools |

**Path-scoped project rules (BIGGEST LEVER):**
Project rules in `<project>/.claude/rules/` can use `paths:` frontmatter to activate ONLY when specific files are read. This is the most powerful mechanism for context-specific behavior — a rule that fires when touching `src/formatter.py` can enforce TUI color standards, a rule scoped to `decisions/` can enforce decision file structure.

For each process error: identify which rule layer would have prevented it. If a path-scoped project rule would be most effective (error only happens in specific file context), create one. This is higher leverage than global rules because it targets the exact context where the error occurs.

##### 4.3 Documentation Check (MANDATORY)

**ALWAYS actively verify — not from memory:**

1. Read ALL DOCS.md, README.md, and decisions/ files in directories touched this cycle
2. Compare directory trees in docs vs actual files on disk (`ls`)
3. Check for drift:

| Check | How |
|-------|-----|
| Files listed in tree | `ls` actual dir, compare to doc tree |
| Function tables | Read source, compare to doc tables |
| Variables/constants | Read source, compare to doc tables |
| Architecture decisions | Compare doc claims to actual code |
| Entry points / CLI args | Read argparse, compare |
| decisions/ files | Do they reflect current implementation? |

4. Report per file in RECAP plan file:
```
DOCS DRIFT CHECK:
- src/features/DOCS.md: OK / DRIFT (details)
- decisions/: OK / DRIFT (details)
- DOCS.md (root): OK / DRIFT (details)
```

5. Every DRIFT item → Content Improvement (4.1)

**DOCS/README updates are NEVER optional, NEVER skippable.**

For full structural reviews, use `/iterative-dev:doc-review`.

##### 4.4 Decisions & Sources Check (MANDATORY)

**ALWAYS actively verify — not from memory:**

1. **Decisions drift:** For each file changed this cycle in `src/`, check if a `decisions/` file covers that component. If yes: does the IST section still match the code? If implementation changed → flag as DRIFT.

2. **New sources:** Were external sources consulted this cycle (papers, docs, APIs, GitHub repos, Reddit threads)? If yes: is each source listed in `sources/sources.md`? If not → flag as MISSING SOURCE.

3. **Pipeline Steps update:** For sources already in `sources/sources.md`: does the Pipeline Steps column reference the correct decision files? If a source informed a decision that isn't listed → flag as STALE REFERENCE.

4. Report:
```
DECISIONS & SOURCES CHECK:
- decisions/index02_dense_embedding.md: OK / DRIFT (IST says X, code now Y)
- sources/sources.md: OK / MISSING SOURCE (<name> — consulted but not listed)
- sources/sources.md: OK / STALE REFERENCE (<source> missing step <decision>)
```

5. Every finding → Content Improvement (4.1)

#### 5. Open Items

List any tasks from the original plan that were NOT executed.

**EMPTY PLATE RULE:** Every Open Item MUST become a Bead before CLOSING.

**NO COMMIT/PUSH BEADS:** Beads NEVER contain "commit and push" as the remaining task. Git operations are CLOSING-phase work (git-committer agent). If all code changes are done and only commit/push remains — that's not a Bead, that's CLOSING. Creating a Bead for "push this repo" means CLOSING was incomplete.

Concrete failure (2026-03-23): Created Bead "blank: worker_send Fix + Ghostty-Kill Push" for 3 changes that only needed pushing. Git-committer had already pushed in CLOSING. Bead was obsolete at creation time.

### Presenting Beads Hygiene

**Beads status MUST appear in BOTH the plan file AND in chat text.**

Format in chat (BEFORE Process Improvements):
```
**<id>** (<title>) — <ACTIVE or CLOSE vorgeschlagen>
- Stand: <last comment summary>
- Kommentiert diese Session: JA/NEIN
- Reason (if close): <why>
```

### Presenting Process Improvements

**Process Improvements MUST appear in BOTH the plan file AND in chat text.**

### Collecting Improvements

After presenting improvements:
1. Ask: "Any remarks?"
2. User gives remark → Analyze for system improvement → Propose concrete change + exact file location
3. Repeat until user says "done" or "improve"

### Phase Exit

1. Ensure all improvements are written to plan file
2. Call ExitPlanMode
3. Next response starts with 🛠️ IMPROVE

---

## Improve Phase (IMPROVE)

**Purpose:** Execute improvements from plan file.

### Workflow

1. Read plan file "## Improvements" and "## Open Items" sections
2. **DOCS/README/decisions/ updates FIRST** — NEVER skippable
3. For each other improvement:
   - **Code?** → `bead_create(title, description)`
   - **Automation Files?** → Follow edit workflow in `~/.claude/rules/automation-framework.md`. Plugin files: edit in SOURCE REPO (see `~/.claude/rules/plugins.md`).
4. Handle Beads (from RECAP Section 3):
   - Create: `bead_create(title, description)`
   - Update: `bead_comment(id, text)`
   - Close: `bead_close(id, reason)`
5. **Handle Open Items** (EMPTY PLATE RULE — see Section 5):
   - For EACH Open Item: `bead_create(title, description)`
6. Ask: "Proceed to CLOSING?"

User confirms → next response starts with ✅ CLOSING

---

## Closing Phase (CLOSING)

Only enter when user confirms (e.g., "proceed", "close", "done").

**PRE-CLOSE CHECK:** EMPTY PLATE RULE enforced — all Open Items must have Beads. Delete `recap_notes.md` (process artifact).

1. **Bead STAND Block (MANDATORY):** For each Bead created or commented this session: write ONE `bead_comment` with STAND block (DONE/OPEN/NEW/DROPPED/APPROACH). This is the single session-end update — no mid-session commenting. The STAND block must enable a fresh Claude to continue without any prior context.
2. Commit ALL repos via git-committer agent (see `~/.claude/rules/subagents.md`)
3. **NO post-commit verification by Opus.** The git-committer agent runs `git status` after commit. Do NOT run additional git commands to "verify" — it always shows clean state and wastes tokens.
4. Ask: "New cycle or done for now?"
