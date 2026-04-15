---
name: recap
description: See ~/.claude/shared-rules/global/cli-skills.md
---

# Cycle Review

**EVERY RESPONSE STARTS WITH A POSITION INDICATOR** — phase + current section:
- `🔍 RECAP — Section 1: Session Reflection`
- `🔍 RECAP — Section 2: Beads Evaluation`
- `🔍 RECAP — Section 3: Improvements`
- `🔍 RECAP — Section 4: Open Items`
- `🛠️ IMPROVE`
- `✅ CLOSING`

---

## Recap Phase (RECAP)

### Phase Entry

1. Create or overwrite plan file at `~/.claude/plans/` with the evaluation report
2. Proceed with evaluation — no edits to source code during RECAP, only the plan file

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
- Were reference files identified early enough (Phase 1 Code Check)?
- References can come from the user OR from code investigation — did subagents flag relevant existing code as reference patterns?
- Were the references helpful or did they lead astray?

##### 1.2 Assumptions/Hallucinations

**Questions:**
- Did I make assumptions that needed correction?
- Was the user's intent clear from the start?
- Did I verify assumptions or just proceed?

**Categories:**
- **Structural:** Directory layout, file locations, naming conventions
- **Semantic:** What columns mean, what functions do, data flow
- **Behavioral:** Expected output format, error handling, edge cases

#### 2. Beads Evaluation

Run `bead_list(status="open")`. For each open bead:
- What was done this session relevant to this bead?
- Can this bead be closed? → mark for close with reason
- What's still to do next session?
- What must a fresh Opus with zero context know to continue seamlessly?

Output:
```
BEADS ACTIONS:
- CLOSE: <id> — <reason>
- COMMENT: <id> — <what to write>
- CREATE: "<title>" — <what was done + what's still to do>
```

##### 2.1 Bead Comment Compression (MANDATORY)

Long-running beads accumulate comment history across many sessions. At a certain point the comment chain becomes the bead's dominant content and makes it unreadable for a fresh Opus. RECAP is the clean-up point.

**Rule — asymmetric detail:**

- **DONE = short form.** One line per delivered item. No narrative, no rationale replay, no "we tried X then Y then Z". Just: _what exists now_. The reader does not need the journey, only the result.
- **OPEN = long form.** Each open item gets full Sachverhalt / context so a fresh Opus can act without re-reading old comments. Include: which files, which function, which invariant, what has been ruled out, what the concrete next step is.
- **Explanations only attach to OPEN items.** Background / "why this matters" prose belongs with the open work it explains, NEVER with done work.

**When to compress an existing comment chain:**

During RECAP Section 2, for every bead with ≥3 historical STAND comments:
1. Read all prior STAND comments
2. Collapse the historical DONE lines into a single short "Done so far:" bullet list in the new comment
3. Write the NEW comment in the asymmetric format above — short DONE, long OPEN
4. Do NOT re-state prior DONE items that are still valid. Done is done.

The new comment supersedes the old narrative for the purpose of "what must a fresh Opus know". Old comments stay in the history for audit — they are not deleted — but the latest comment is authoritative.

**Template:**

```
STAND <date>:

DONE (short):
- <delivered item 1>
- <delivered item 2>
- <delivered item 3>

OPEN (detailed):

### <open item 1 — one-line title>
Sachverhalt: <what the problem is, where it lives in code, what's been ruled out>
Next step: <concrete action a fresh Opus can execute>

### <open item 2 — one-line title>
Sachverhalt: ...
Next step: ...

APPROACH: <how the work was done this session — only if needed for OPEN continuation>
```

**Anti-pattern:** Replaying the full session story in DONE because "the context is interesting". It is not interesting to the next session. Compress mercilessly.

#### 3. Improvements

Every Process Improvement MUST reference an exact Automation File path + section.
Format: `[Description] → [Automation File path] → [Section to add/extend]`
Automation File locations: see `~/.claude/rules/automation-framework.md`

**READ BEFORE WRITE (MANDATORY):**
Before proposing ANY process improvement: READ the target Automation File. You need to know:
1. What sections already exist (avoid duplicating existing rules)
2. Exact line numbers for insertion points
3. Whether the improvement overlaps with or contradicts existing content

Concrete failure (2026-03-23): Proposed workers.md improvements without reading the file. Would have referenced wrong section names and missed existing "Reusing Workers" content. User had to ask "hast du die automation files gelesen?"

**RULE IMPROVEMENT STAGING (MANDATORY — read before editing any rule file):**

Editing a file under `~/.claude/shared-rules/` or `~/.claude/rules/` during an active
session triggers a proxy-side cache rebuild in the NEXT request. The proxy's rule loader
watches file mtime; any mtime change invalidates the cached `sys[2]` rules block, which
shifts the prefix by thousands of bytes and forces a full CC write. Cost per edit:
roughly the entire current context size as `cache_creation_input_tokens`.

**Workflow:**
1. During RECAP Section 3: do NOT edit rule files directly. Instead, append the proposed
   improvement to `~/.claude/shared-rules/_staging/rule_improvements.md`. Use the format:
   ```
   ## <date> — <session topic>
   ### <target rule file path> → <section>
   <proposed improvement text, ready to paste>
   ```
2. At the END of the last daily session: review the staging file, decide which
   improvements to apply, and execute all edits in one batch. The batch edit still causes
   ONE rebuild — but only one, and only at end-of-day when further requests are cheap
   (next-session fresh cache anyway).
3. If the staging file does not exist yet, create it.

**Exception:** The LAST session of the day may edit rule files directly if the user
explicitly confirms it is the last session. In that case, the next-request rebuild is
acceptable because the session ends shortly after.

**Why staging is not a detour:** The staging file IS the improvement queue. RECAP Section
3 output must still be listed in the plan file AND in chat. The staging file is a
separate artifact that accumulates proposals across sessions until the batch is applied.

##### 3.1 Content Improvements (Code/Docs)

Prioritization:
- **Critical:** Must fix (breaks functionality, wrong behavior)
- **Important:** Should fix (code quality, maintainability)
- **Optional:** Nice to have

**Handling:** Code → **Bead** (needs own cycle). Docs/README/Automation Files → **Direct Edit** in IMPROVE.

##### 3.2 Process Improvements

Prioritization (by OUTCOME):
- **Critical:** Process errors that WOULD HAVE caused critical code issues
- **Important:** Process errors that caused detours but correct outcome
- **Optional:** Minor process inefficiencies

**Handling:** Same as 3.1 — Code → Bead, Automation Files → Direct Edit.

**Key rules:**
- Process Improvements = Automation Files ONLY. Docs/README = Content Improvements (3.1).
- OUTCOME determines severity. Wrong process + correct result = Important (not Critical).
- Every process error MUST produce a config change. "Lesson Learned" without config change = FAILURE.

Routing table and rule layers: see `~/.claude/rules/automation-framework.md`.

**Scope Check (MANDATORY before writing):**
Before routing a process improvement to a global rule file (`~/.claude/rules/`), verify: is this lesson PROJECT-SPECIFIC or truly global?
- Tool/technology-specific lessons (tmux, specific API, project-specific patterns) → project rule (`<project>/.claude/rules/`)
- Universal behavior lessons (communication, scoping, verification methodology) → global rule (`~/.claude/rules/`)
- `~/.claude/rules/verify-before-execution.md` is NOT a dump for all lessons. Only route there if the verification pattern applies across ALL projects.
- Concrete failure (2026-03-27): tmux format variable lesson routed to global `verify-before-execution.md`. Only relevant to Monitor_CC — belongs in `Monitor_CC/.claude/rules/monitor-standards.md`.

##### 3.3 Documentation Check (MANDATORY)

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

4. Report per file in RECAP report:
```
DOCS DRIFT CHECK:
- src/features/DOCS.md: OK / DRIFT (details)
- decisions/: OK / DRIFT (details)
- DOCS.md (root): OK / DRIFT (details)
```

5. Every DRIFT item → Content Improvement (3.1)

**DOCS/README updates are NEVER optional, NEVER skippable.**

For full structural reviews, use `/iterative-dev:doc-review`.

##### 3.4 Decisions & Sources Check (MANDATORY)

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

5. Every finding → Content Improvement (3.1)

#### 4. Open Items

List any tasks from the original plan that were NOT executed.

**EMPTY PLATE RULE:** Every Open Item MUST become a Bead before CLOSING.

**NO COMMIT/PUSH BEADS:** Beads NEVER contain "commit and push" as the remaining task. Git operations are CLOSING-phase work (git-committer agent). If all code changes are done and only commit/push remains — that's not a Bead, that's CLOSING. Creating a Bead for "push this repo" means CLOSING was incomplete.

Concrete failure (2026-03-23): Created Bead "blank: worker_send Fix + Ghostty-Kill Push" for 3 changes that only needed pushing. Git-committer had already pushed in CLOSING. Bead was obsolete at creation time.

### Presenting Beads Hygiene

Before writing any bead comments, present in chat:
- What was done this session (brief summary)
- What Opus intends to write as OPEN in the bead

User can correct before the bead comment is set. The actual bead content will be more detailed.

### Presenting Process Improvements

**Process Improvements MUST appear in BOTH the report file AND in chat text.**

### Collecting Improvements

After presenting improvements:
1. Ask: "Any remarks?"
2. User gives remark → Analyze for system improvement → Propose concrete change + exact file location
3. Repeat until user says "done" or "improve"

### Phase Exit

1. Ensure all improvements are written to report file
2. Ask: "Bemerkungen bevor ich zur IMPROVE-Phase übergehe?"
3. Next response starts with 🛠️ IMPROVE

---

## Improve Phase (IMPROVE)

**Purpose:** Execute improvements from report file.

### Workflow

1. Read report file "## Improvements" and "## Open Items" sections
2. **DOCS/README/decisions/ updates FIRST** — NEVER skippable
3. Automation File improvements → Follow edit workflow in `~/.claude/rules/automation-framework.md`. Plugin files: edit in SOURCE REPO (see `~/.claude/rules/plugins.md`).
4. Handle Beads (from RECAP Section 2):
   - Create: `bead_create(title, description)` — content = what was done + what's still to do
   - Comment: `bead_comment(id, text)` — STAND block
   - Close: `bead_close(id, reason)`
   - Open Items without a bead → create bead here (EMPTY PLATE RULE)
5. Ask: "Proceed to CLOSING?"

User confirms → next response starts with ✅ CLOSING

---

## Closing Phase (CLOSING)

Only enter when user confirms (e.g., "proceed", "close", "done").

**PRE-CLOSE CHECK:** EMPTY PLATE RULE enforced — all Open Items must have Beads. Delete `recap_notes.md` (process artifact).

### Cross-Session Verification

When a change cannot be tested in the current session (e.g., plugin changes that need CC restart):
1. **Worker stays alive** — tmux session open, do NOT kill. Worker kill only after verification passes + user approval.
2. **Bead tracks** what's DONE and what's OPEN (verification pending). Document alive workers in Bead STAND block: worker name, what it did, what to verify.
3. **Next session:** test the change. If it fails → re-send the worker via `worker_send` with fix instructions. The worker has full context from implementation — no re-exploration needed.

### Workflow

1. **Bead STAND Block (MANDATORY):** For each Bead created or commented this session: write ONE `bead_comment` with STAND block (DONE/OPEN/NEW/DROPPED/APPROACH). This is the single session-end update — no mid-session commenting. The STAND block must enable a fresh Claude to continue without any prior context.
2. **Dev → Main Sync:** Use `dev_sync()` MCP tool to sync dev→main. Then optionally `git branch -d dev` to clean up. All subsequent commits happen on `main`.
3. Commit ALL repos via MCP tools: `git_commit(repo_path, message)` per repo, then `git_push(repo_path)` per repo. Stage files with Bash `git add` before committing.
4. **NO post-commit verification by Opus.** `git_commit` returns the commit hash. Do NOT run additional git commands to "verify" — it always shows clean state and wastes tokens.
