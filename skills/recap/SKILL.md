---
name: recap
description: See ~/.claude/shared-rules/global/cli-skills.md
---

# Cycle Review

Two phases. ONE stop between them.

- `🔍 RECAP` — mental reflection, then short chat output (Beads hygiene + Process Improvements), then STOP for remarks
- `🛠️ IMPROVE+CLOSE` — execute everything in one go, no further stops

No plan file. No `recap_notes.md`. The reflection is in your head; the deliverables are bead actions, staging file, direct edits, and commits.

---

## 🔍 RECAP

### Step 1 — Mental Reflection (no chat output, no file)

Think deeply across all dimensions below. Do NOT write any of this to chat or file. The output of this step is your own mental model that drives Step 2.

#### 1.1 Session Reflection

**Efficiency:**
- Focused questions or scattered?
- Iteration count — could the stable plan have come faster?
- User answers correctly understood?
- More than 3 back-and-forth before stable plan?
- Assumptions corrected multiple times?
- Solutions proposed before understanding the problem?
- Execution Path Errors — most IMPLEMENT failures trace back to skipped verification in PLAN
- References: identified early enough (Phase 1 Code Check)? helpful or misleading?

**Assumptions / Hallucinations** — categories:
- **Structural** — directory layout, file locations, naming
- **Semantic** — column meanings, function purpose, data flow
- **Behavioral** — output format, error handling, edge cases

#### 1.2 Beads Evaluation

Run `bd list -s open`. For each open bead decide: CLOSE / COMMENT / CREATE.

**Bead Comment Compression — asymmetric detail (MANDATORY):**

- DONE = **short**. One line per delivered item. No narrative, no rationale replay.
- OPEN = **long**. Full Sachverhalt per open item: which files, which function, which invariant, what's been ruled out, concrete next step.
- Explanations attach ONLY to OPEN items, never to DONE.

For beads with ≥3 historical STAND comments: collapse historical DONE into a single "Done so far:" bullet list in the new comment. New comment supersedes the old narrative for fresh-Opus reading. Old comments stay in history.

Template:
```
STAND <date>:

DONE (short):
- <delivered item 1>
- <delivered item 2>

OPEN (detailed):

### <open item 1 — one-line title>
Sachverhalt: <problem, location in code, what's ruled out>
Next step: <concrete action>

APPROACH: <how the work was done — only if needed for OPEN continuation>
```

#### 1.3 Improvements

**Routing — `decisions/` vs Rules:**

- `<project>/decisions/` — IS-state facts, code-based decisions, empirical findings about THIS project. Read on demand, not always-on.
- `~/.claude/shared-rules/` — needed every session, always-loaded:
  - `global/` — universal behavior (communication, scoping, verification, tool usage)
  - `opus/` — Opus-only (orchestration, beads, workers)
  - `worker/` — worker-only (code standards, dev conventions)
  - `proj_<name>/` — project-specific architectural rules

Test: "needed in EVERY session of this project?" → rule (project-specific by default, global only if truly cross-project). "Only when working on feature X?" → `decisions/`.

##### 1.3.1 Content Improvements (Code/Docs)

Severity: Critical / Important / Optional.

Routing: Code → **Bead** (needs own cycle). Docs/README/Automation Files → **Direct Edit** in IMPROVE+CLOSE.

##### 1.3.2 Process Improvements

Severity by OUTCOME:
- **Critical** — would have caused critical code issue
- **Important** — caused detour but correct outcome
- **Optional** — minor inefficiency

Rules:
- Process Improvements = Automation Files ONLY. Docs/README = 1.3.1.
- Every process error MUST produce a config change. "Lesson Learned" without config change = FAILURE.

**Scope Check:** Tool/tech-specific lesson → project rule (`proj_<name>/`). Universal behavior → `global/`. `verify-before-execution.md` is NOT a dump for all lessons.

##### 1.3.3 DOCS Drift Check (MANDATORY)

Format reference: `~/.claude/shared-rules/global/documentation.md`. Required per module: LOC, Purpose, Reads, Writes, Called-by, Calls-out. Per package: Role, Public Interface, Flow, Modules, State, Gotchas.

Run `git diff main..dev --name-only --` for the touched-file list.

Per-module checks:
| Check | Command | Drift |
|-------|---------|-------|
| LOC | `wc -l <file>` vs `### <module> (<LOC> LOC)` | actual differs by ≥5 |
| Called-by | `grep -rn "from \\.\\.<package>\\.<module>\\|from src\\.<package>\\.<module>" src/ workflow.py dev/` | DOCS missing/listing wrong caller |
| Calls-out | module's import block | external pkg not in Calls-out |
| Public Interface | `<package>/__init__.py` | re-exports changed, DOCS not |
| State | grep module-level mutable vars | new state not in State section |
| Gotchas | same-session landmines | new gotcha not added |

Per-package checks:
| Check | How |
|-------|-----|
| Directory Map (`src/DOCS.md`) | `ls src/<subdir>/*.py` count + `wc -l` sum vs table |
| Root-Level Files | `ls src/*.py` |
| Subdir DOCS links | one link per subdir with DOCS.md |

Plus: `decisions/` IST still matches code for touched components? `CLAUDE.md` still short + link-based?

Every DRIFT → 1.3.1 (Content Improvement). DOCS drift is NEVER deferred — fix in same cycle.

**Anti-pattern:** prescriptive "if LOC grows, extract …" comments in Gotchas. Gotchas document landmines that exist NOW, not future-refactor suggestions. If a module already crossed the refactor threshold → that's a Bead, not a Gotcha. Delete on sight.

For full structural reviews: `/iterative-dev:doc-review`.

##### 1.3.4 Decisions & Sources Check (MANDATORY)

- For each touched `src/` file: does a `decisions/` file cover it? IST still matches code? → DRIFT.
- External sources consulted this cycle (papers, docs, GitHub, Reddit) listed in `sources/sources.md`? → MISSING SOURCE.
- Pipeline Steps column references correct decision files? → STALE REFERENCE.

Every finding → 1.3.1.

##### 1.3.5 Rule Improvement Staging (MANDATORY for rule changes)

**NEVER edit `~/.claude/shared-rules/` or `~/.claude/rules/` directly during a session.** Proxy rule loader watches mtime; any edit invalidates `sys[2]` cache → full CC write next request, costs roughly the entire current context as `cache_creation_input_tokens`.

**Workflow:** ONE per-session staging file under `~/.claude/shared-rules/_staging/`:
```
<YYYY-MM-DD_HHMMSS>_<project>_<topic-slug>.md
```
Inside:
```
# <YYYY-MM-DD> — <PROJECT_NAME>: <session topic in 5 words>

## <target rule file path> → <section>
<proposed improvement text, ready to paste>

## <another target rule file path> → <another section>
<another improvement>
```

One md per session. Multiple improvements = multiple sections in the same file. Project name MANDATORY in filename and header — without it proposals are unattributable.

**Mandatory when:** new empirical findings, process errors needing rule changes, architecture decisions, workflow improvements.

**Not needed when:** session ran cleanly, OR all improvements applied LIVE during the session.

#### 1.4 Open Items

Tasks from the original plan NOT executed.

**EMPTY PLATE RULE:** every Open Item → Bead before CLOSING.

**NO COMMIT/PUSH BEADS:** Beads NEVER contain "commit and push" as the remaining task. Git operations are CLOSING work. If only commit/push remains → that's CLOSING, not a Bead.

---

### Step 2 — Chat Output (short form)

After mental reflection, post ONE chat message in short form. Two sections only:

```
BEADS:
- CLOSE <id>: <reason in one line>
- COMMENT <id>: <one-line OPEN summary>
- CREATE: "<title>" — <one-line scope>

PROCESS IMPROVEMENTS:
- <one-line finding> → <target rule file>
- <one-line finding> → <target rule file>

DRIFT (if any):
- <file/component>: <one-line drift>
```

No section headers beyond these. No prose. No "section X.Y completed". The user reads, gives remarks, then we proceed.

🛑 STOP — ask "Bemerkungen?"

User remark → analyze → propose concrete change + target file. Repeat until "improve" or "done".

---

## 🛠️ IMPROVE+CLOSE

One run through, no stops.

### 1. Apply Improvements

- **DOCS / README / decisions/** updates — direct edits in target files.
- **Rule improvements** — write ONE staging file at `~/.claude/shared-rules/_staging/<YYYY-MM-DD_HHMMSS>_<project>_<topic>.md` per the format above. Never edit rule files directly during the session.
- **Plugin file edits** — in SOURCE REPO (see `~/.claude/shared-rules/situational/plugins.md`, read on demand).
- **Code issues** → `bd create` (no direct edits to source code in this phase).

### 2. Sync Docs to RAG (when applicable)

Pattern is project-aware via `.rag-docs.json` at the project root. Projects with a manifest get a hash-based delta sync into their `<Project>-meta` collection; projects without are skipped silently.

```bash
[ -f .rag-docs.json ] && rag-cli update_docs .
```

Output reports added / updated / removed / unchanged counts.

### 3. Beads

All via `bd` CLI:
- `bd --repo <project_path> create --title "..." --type task --description "..."`
- `bd comments add <id> "<STAND text>"` — full STAND block (DONE/OPEN/NEW/DROPPED/APPROACH), asymmetric format from 1.2
- `bd close <id> --reason="..."`

ONE STAND comment per touched bead. The STAND must enable a fresh Claude with zero context to continue.

### 4. Cross-Session Verification

When a change can't be tested in the current session (e.g., plugin needing CC restart):
- Worker stays alive — do NOT kill until verification passes + user approval
- Bead STAND documents: worker name, what it did, what to verify
- Next session: test → if fail, `worker_send` with fix instructions (worker has full context)

### 5. Git (CLOSING)

1. **Dev → Main sync:** `dev_sync` MCP tool. Optional `git branch -d dev` after.
2. **Per repo:** `git_check` (pre-commit staging) → `git -C <repo> commit -m "<msg>"` (HEREDOC for multi-line per `git-commit-workflow.md`) → `git -C <repo> push`.
3. **NO post-commit verification.** The commit returns the hash; further git commands are token waste.

Done when commits are pushed.
