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

Run `bd list -s open`. For each open bead:
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

**Routing — `decisions/` vs Rules (READ FIRST):**

Every finding goes into exactly one bucket. Decide BEFORE writing the staging file.

- **`<project>/decisions/`** — IS-state facts, code-based decisions, empirical findings about THIS project. Examples: cache-rebuild case families, pipeline data model, hook byte limits, "proxy strips X at step Y". Relevant only when working in that specific functional area. Read on demand, NOT always-on.
- **Rules / rule proposals** (`~/.claude/shared-rules/`) — things that must be at hand EVERY session. Always-loaded into system prompt. Split by scope:
  - `global/` — universal behavior that applies regardless of project (communication, scoping, verification, tool usage)
  - `opus/` — Opus-only concerns (orchestration, beads, workers)
  - `worker/` — Worker-only concerns (code standards, dev conventions)
  - `proj_<name>/` — **project-specific rules**. If a failure would have been prevented by knowing something structural about THIS project (its architecture, its conventions, its peculiar setup, the "if you touch X here, always Y" kind of invariant) → this is a project rule, NOT a global one. Project-specific is the right answer whenever the lesson does not generalize to other projects.

Test for each finding:
- "Do I need this in EVERY new session of this project?" → rule (project-specific `proj_<name>/` by default, global only if it truly applies across ALL projects)
- "Only when I work on feature X or debug issue Y?" → `decisions/`

**RULE IMPROVEMENT STAGING (MANDATORY — read before editing any rule file):**

Editing a file under `~/.claude/shared-rules/` or `~/.claude/rules/` during an active
session triggers a proxy-side cache rebuild in the NEXT request. The proxy's rule loader
watches file mtime; any mtime change invalidates the cached `sys[2]` rules block, which
shifts the prefix by thousands of bytes and forces a full CC write. Cost per edit:
roughly the entire current context size as `cache_creation_input_tokens`.

**Workflow:**
1. During RECAP Section 3: do NOT edit rule files directly. Instead, CREATE one
   per-session file under `~/.claude/shared-rules/_staging/`. Filename pattern:
   ```
   <YYYY-MM-DD_HHMMSS>_<project>_<topic-slug>.md
   ```
   Example: `2026-04-17_142305_searxng_tier-eval-blocked.md`
   Inside the file, use the format:
   ```
   # <YYYY-MM-DD> — <PROJECT_NAME>: <session topic in 5 words>

   ## <target rule file path> → <section>
   <proposed improvement text, ready to paste>

   ## <another target rule file path> → <another section>
   <another improvement>
   ```
   A single session can contain multiple improvements — all go into the one per-session file.

**One md per session. That's it.** The staging file accumulates — application is out of scope for this rule.

**Staging file is MANDATORY when the session produced findings worth carrying forward:**

- New empirical findings about system behavior (cache, proxy, tokenizer, etc.)
- Process errors that need rule changes
- Architecture decisions that affect future sessions
- Workflow improvements discovered during execution

The file goes to `~/.claude/shared-rules/_staging/<YYYY-MM-DD_HHMMSS>_<project>_<topic>.md`
with the format shown above.

**Project name is MANDATORY in the filename AND the in-file header.** Without it,
proposals are unattributable across projects.

**No staging file needed when:**
- Nothing to improve (session ran cleanly, no findings)
- All identified improvements were applied LIVE during the session (backlog empty at RECAP)

In those cases the RECAP plan file itself is the record — no empty marker file.

Concrete failure (2026-04-16): Full Monitor_CC session with TTL verification, cross-session
cache proof, sys[2]-marker validation, proxy architecture findings. Zero entries in staging
file. All findings only in chat context — lost for future sessions until manually recovered
from bead comments.

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

**Scope Check (MANDATORY before writing):**
Before routing a process improvement to a global rule file (`~/.claude/shared-rules/global/`), verify: is this lesson PROJECT-SPECIFIC or truly global?
- Tool/technology-specific lessons (tmux, specific API, project-specific patterns) → project rule (`~/.claude/shared-rules/proj_<name>/`)
- Universal behavior lessons (communication, scoping, verification methodology) → global rule (`~/.claude/shared-rules/global/`)
- `~/.claude/shared-rules/global/verify-before-execution.md` is NOT a dump for all lessons. Only route there if the verification pattern applies across ALL projects.
- Concrete failure (2026-03-27): tmux format variable lesson routed to global `verify-before-execution.md`. Only relevant to Monitor_CC — belongs in `~/.claude/shared-rules/proj_monitor/monitor-standards.md`.

##### 3.3 Documentation Check (MANDATORY)

**ALWAYS actively verify — not from memory. DOCS drift compounds — every skipped check makes the next exploration worse.**

DOCS format reference: `~/.claude/shared-rules/global/documentation.md`. Required fields per module: LOC, Purpose, Reads, Writes, Called-by, Calls-out. Per package: Role, Public Interface, Flow (where relevant), Modules, State (where applicable), Gotchas (where applicable).

**Step 1 — Enumerate touched files.**

Run `git diff main..dev --name-only` (or against the branch point) to get the full list of files modified this cycle. Every `.py`/`.sh` under `src/` hits the docs pipeline.

**Step 2 — Per-module drift checks (concrete, scriptable).**

For each modified module:

| Check | Command | What counts as DRIFT |
|-------|---------|----------------------|
| LOC | `wc -l <file>` vs `### <module> (<LOC> LOC)` header in DOCS | Actual LOC differs by ≥5 from doc value |
| Called-by | `grep -rn "from \\.\\.<package>\\.<module>\\|from src\\.<package>\\.<module>" src/ workflow.py dev/` | Caller list in DOCS missing a caller or lists a removed one |
| Calls-out | Read the module's import block | External packages in imports not mentioned in Calls-out line |
| Public Interface | Read `<package>/__init__.py` | Re-exports changed but DOCS "Public Interface" not updated |
| State | Grep module-level mutable vars | New state surface added but not in State section |
| Gotchas | Same-session discovery of landmines | New gotcha found this session and not added |

**Step 3 — Per-package drift checks.**

| Check | How | Drift |
|-------|-----|-------|
| Directory Map (`src/DOCS.md`) | `ls src/<subdir>/*.py` count vs "Modules" column; `wc -l src/<subdir>/*.py` sum vs "LOC" column | Any delta |
| Root-Level Files table (`src/DOCS.md`) | `ls src/*.py` | New/removed root file not reflected |
| Subdir DOCS links (`src/DOCS.md`) | One link per subdir with DOCS.md | Missing link or stale link |

**Step 4 — decisions/ and CLAUDE.md drift.**

- For each file changed in `src/`: is a `decisions/` file covering that component? Does IST still match the code?
- `CLAUDE.md` (root): still short + link-based, no stale file-list?

**Step 5 — Report per file in RECAP report:**

```
DOCS DRIFT CHECK:

Per-module:
- src/<package>/<module>.py: LOC OK / DRIFT (DOCS says N, actual M)
- src/<package>/<module>.py: Called-by OK / DRIFT (<details>)

Per-package:
- src/<package>/DOCS.md: OK / DRIFT (<details>)
- src/DOCS.md Directory Map: OK / DRIFT (<subdir> count N → M)
- CLAUDE.md: OK / DRIFT (<details>)
- decisions/: OK / DRIFT (<details>)
```

**Step 6 — Every DRIFT item → Content Improvement (3.1).**

DOCS drift is never deferred to the next session. If the DOCS went stale THIS cycle, the fix belongs in the SAME cycle's IMPROVE phase. A worker can batch-update DOCS if the drift is broad (multi-file LOC/caller shifts).

**Anti-pattern — prescriptive "if LOC grows, extract …" comments.**

Gotchas document landmines that exist NOW. They are NOT the place for future-refactor suggestions. If a module is already over the refactor threshold, that's a Bead, not a Gotcha. Gotchas that prescribe a future action based on a threshold the module has already crossed get DELETED on sight — they are noise.

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
3. Automation File improvements → staging file under `~/.claude/shared-rules/_staging/` per the workflow in Section 3. Plugin files: edit in SOURCE REPO (plugin-sync details in `~/.claude/shared-rules/situational/plugins.md` — not auto-loaded, read on demand).
4. Handle Beads (from RECAP Section 2) — all via `bd` CLI:
   - Create: `bd --repo <project_path> create --title "<title>" --type task --description "<desc>"`
   - Comment (STAND block): `bd comments add <id> "<text>"`
   - Close: `bd close <id> --reason="<reason>"`
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

1. **Bead STAND Block (MANDATORY):** For each Bead created or commented this session: write ONE `bd comments add <id> "<STAND text>"` with STAND block (DONE/OPEN/NEW/DROPPED/APPROACH). This is the single session-end update — no mid-session commenting. The STAND block must enable a fresh Claude to continue without any prior context.
2. **Dev → Main Sync:** Use `dev_sync()` MCP tool to sync dev→main. Then optionally `git branch -d dev` to clean up. All subsequent commits happen on `main`.
3. Commit ALL repos: pre-commit staging via `git_check(repo_path)` MCP, then CLI `git -C <repo> commit -m "<msg>"` (HEREDOC for multi-line) and `git -C <repo> push` per repo. Full flow in `~/.claude/shared-rules/global/git-commit-workflow.md`.
4. **NO post-commit verification by Opus.** The commit command returns the hash. Do NOT run additional git commands to "verify" — it always shows clean state and wastes tokens.
