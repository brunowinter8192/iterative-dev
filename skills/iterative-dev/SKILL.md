---
name: iterative-dev
description: (project)
---

# Iterative Development Skill

## Task Management Hierarchy

- **Beads** (`.beads/`) - Cross-session (days/weeks/months). Rules and formats in `~/.claude/rules/beads.md`
- **Plan-File** (`.claude/plans/`) - Within a session (hours)
- **TodoWrite** - Within an iteration (minutes)

### Beads (MANDATORY)

Rules, types, and content requirements: `~/.claude/rules/beads.md`

Beads are **always active** — not tied to specific phases. After every significant action (file changed, decision made, bug found, scope change), comment the relevant bead immediately. Don't batch comments for phase transitions.

**MANDATORY: After every `git commit`, immediately `bd comments add <bead-id>` with what was changed and why.** A commit without a bead comment = lost context. This is the minimum granularity — no exceptions.

**Session start:** `bd list -s open` → read relevant work beads. No bead for current work → create one before starting.

## CRITICAL CYCLE

```
PLAN (Plan Mode) -> IMPLEMENT -> RECAP -> IMPROVE -> CLOSING -> PLAN (new cycle)
```

EVERY RESPONSE STARTS WITH A PHASE INDICATOR:
- `📋 PLAN` - Planning phase (Plan Mode active)
- `🔨 IMPLEMENT` - Implementation phase
- `🔍 RECAP` - Report phase (Plan Mode active - read-only enforced)
- `🛠️ IMPROVE` - Improvements phase
- `✅ CLOSING` - Cycle completion

**Plan Mode Usage:**
- PLAN: Native Plan Mode for implementation planning
- RECAP: Plan Mode for read-only protection (prevents accidental edits)

**Phase Detection:** System message contains "Plan mode is active" → Check context to determine if PLAN or RECAP.

---

## Planning Phase (PLAN)

### Beads Check (BEFORE Exploration)

**MANDATORY:** Run `bd list -s open` BEFORE launching any exploration agents.

Beads provide cross-session context. Agent exploration without bead context = wasted effort.

**Note:** Always use `-s open` by default. Show closed beads only when user explicitly asks.

**Priority:** Read the most recently updated bead FIRST (`bd show` shows Created/Updated dates). The newest bead has the freshest context and is most likely the current session target.

**After reading bead comments, VERIFY:** Does the bead already answer the scope question you're about to ask? If the bead comments contain explicit next steps, decisions, or approaches — state them as fact ("Laut Bead: FFS mit Korrelations-Ranking"), don't re-ask as an open question. Re-asking what's already documented = not reading carefully enough.

### Scoping (BEFORE Exploration)

**Code-First Rule:** When user provides a codebase task (modify, convert, create based on existing code): READ the relevant source code BEFORE asking scope questions. Most questions answer themselves from code. Only ask what the code cannot tell you (intent, preferences, target audience).

BEFORE you explore, clarify with the user:

**1. SCOPE - What is the end goal?**
→ "What should the output be?"
→ File? Script? Documentation? Analysis?
→ **If Documentation:** "Who is the target reader?"
  - **Default assumption:** AI (you) is the primary reader
  - Docs should be perfect for AI consumption, but human-readable when needed
  - Optimize for: clarity, structure, completeness (AI needs full context)

**2. SOURCES - Which files/folders are relevant?**
→ "Which folders should I look at?"
→ "Is there a reference script?"
→ User knows the structure better than you

**3. CONNECTIONS - How do the sources relate?**
→ "How does X use data from Y?"
→ Only when connections are clear: read DOCS.md

**4. REFERENCES - Is there an existing pattern to follow?**
→ "Is there an existing pattern in your other projects we should follow?"
→ Especially for testing, debug, infrastructure tasks
→ User's existing patterns beat generic best practices (e.g., scraping suite > unit tests for web scrapers)

**Question Pacing:**
- Structure questions by topic steps, not as a single dump
- 5 questions in one round is fine IF they are thematically coherent
- Consider whether an answer to question N makes question N+1 obsolete — if so, ask sequentially
- Do NOT ask one question per round when they are independent — that wastes exchanges
- Do NOT overload the user with unrelated questions in a single block

**Session-Scope First (CRITICAL):**
- BEFORE asking about features, architecture, or sources: ask "What is the scope of THIS SESSION?"
- User often has a bigger vision but wants to tackle one piece now
- Don't brainstorm the full feature — ask what's actionable TODAY
- If user describes a multi-step vision: "Which part do we do now?"

**Scope-Pivot Rule:**
- When user corrects your scope understanding 2+ times → STOP
- Summarize: "So: [X] and only [X], correct?" — then wait for confirmation
- Do NOT continue asking questions after 2 corrections — you're clearly misreading the intent
- Each correction is a signal that you're thinking too broadly

**EXCEPTION — Concrete Usecase First:**
When user describes a concrete usecase ("verify these numbers", "run this workflow"), execute the usecase FIRST before asking scope questions. The concrete experience reveals the actual scope better than abstract discussion. AskUserQuestion only AFTER the usecase exposed gaps or decision points.

**Targeted vs Exploratory:**
- When user provides specific claims/data to verify → **targeted search**
  - Ask user for concrete path/directory BEFORE exploring
  - User has the mapping context (section name → directory)
  - Check bead descriptions for path hints
- When user asks to explore/discover → **exploratory search**
  - Navigate freely, no need to ask for paths upfront

**THEN:** Explore with direction (DOCS.md → relevant scripts → structures)

### Implementation Flow (Bugs AND Features)

When the scope is clear and the task involves implementing or fixing something in the repo, follow this sequence:

**1. Status Quo**
- Read relevant `decisions/` files if the project has them
- Map divergences between bead context and current decisions (things may have changed since the bead was written)

**2. Dev Check**
- Does `dev/` already have modules/scripts that address this problem area?
- Read DOCS.md of the relevant `dev/` subdirectory FIRST, then only read module code if needed
- Existing dev scripts > building new ad-hoc test scripts

**3. Source Check**
- Read the project's CLAUDE.md Sources table — what knowledge is already indexed?
- Identify gaps: do we need additional sources (web search, GitHub, papers)?
- If sources are missing → plan research BEFORE planning implementation
- Do NOT dispatch research agents before having reproduced/understood the problem in dev

**4. Reproduce / Verify in Dev (BEFORE Research)**
- For bugs: reproduce in dev/ with test DB first, THEN research causes
- For features: build a minimal prototype/test in dev/ first, THEN research best approaches
- Research agents dispatched before reproduction = wasted effort on assumptions
- Concrete failure (2026-03-17): 3 research agents dispatched for SPLADE nnz limits before reproduction. Reproduction revealed a completely different root cause (server state corruption). Research results were correct but irrelevant.

**5. Research (only when needed)**
- Wait for user input on whether research is needed
- Only AFTER reproduce/verify step reveals the actual problem or gap
- Use the right source: RAG collection first, then web/GH/papers

**6. Dev Script Decision**
- Are new dev scripts needed? If yes: which directory, what pattern to follow?
- Follow existing dev/ conventions (DOCS.md format, CLI flags, test DB usage)

**7. Plan**
- Map the complete plan: short form in chat, long form in plan file
- Include worker draft if workers are needed
- Ask for remarks

### Research Source Accounting (MANDATORY after web/academic research)

After ANY research phase (web search, paper lookup, API exploration), produce a **Source Table** before proceeding:

| Source | Status | Content Value | Plugin Needed | Index? |
|--------|--------|--------------|---------------|--------|
| Paper/URL title | Read ✅ / Failed ❌ / Paywall 🔒 | High/Medium/Low | ArXiv/GitHub/— | Yes/No |

**Categories:**
- **Read ✅**: Content successfully scraped/accessed, key findings extracted
- **Failed ❌**: Scrape returned empty, PDF conversion failed — note WHY (empty response, timeout, bot detection)
- **Paywall 🔒**: Content exists but requires subscription/login

**For each "Index? Yes" source:**
- If PDF available → download + pdf-convert pipeline
- If web page → crawl-site or scrape_url pipeline
- Spawn a worker to handle batch conversion/indexing

**For each "Plugin Needed" source:**
- ArXiv PDFs → ArXiv Plugin (download) + RAG Plugin (pdf-convert)
- GitHub repos/issues → GitHub Research Plugin
- Reddit threads → Reddit Plugin

**Why:** Research without source accounting = lost context. Next session won't know what was read, what was missed, and what's available for deeper analysis. The table is the bridge between "I searched" and "I can now plan based on evidence."

**Concrete failure (2026-03-17):** 5 papers identified during weight-calibration research. 2 readable, 3 failed (PDF scrape empty, Semantic Scholar abstract only). No systematic listing until user asked. Worker for PDF conversion spawned late instead of immediately after identifying sources.

### Exploration

**Documentation First (MANDATORY):**

BEFORE any action in a directory (running scripts, editing files, exploring code):
1. STOP
2. READ the DOCS.md in that directory
3. ONLY THEN proceed

This is NON-NEGOTIABLE. Skipping DOCS.md leads to: wrong paths, wrong arguments, wrong understanding.

**"Exploring code" includes:**
- Grep/Search in that directory
- Reading scripts
- Running scripts
- Editing files

**Bug Investigation Pattern:**
1. User reports bug (e.g., "threshold should be >150")
2. **WRONG:** Grep for "150" or "threshold" immediately
3. **RIGHT:** Read DOCS.md first → shows which script handles threshold → read THAT script

**Why DOCS first for bugs:**
- DOCS shows the workflow and which script does what
- DOCS shows the default values and parameters
- Grep without context = searching blind
- DOCS → targeted read = efficient investigation

**SOURCE CODE VERIFICATION (Bugs & Code Changes):**

When fixing bugs or making code changes involving system behavior (terminal escape codes, protocols, APIs):
1. **ASK:** "Is there a reference implementation I should check?"
2. **CHECK:** Look in local repos (e.g., `repo/` folder) for authoritative source code
3. **VERIFY:** Before implementing, confirm behavior against reference

**ASK THE FUCKING USER**
- the user knows best, ask him for reference scripts,
	- REFERENCE SCRIPTS OR SOURCE CODE IS A GAME CHANGER, MAKES LIFE MUCH EASIER
- ask him for things which are critical to understand in order to be able to make a Plan file
	- USER HAS A BROAD KNOWLEDGE, TAKE ADVANTAGE OF IT
- **External Dependencies/Versions:** ASK USER, don't self-verify
	- Docker images, tool versions, library versions
	- User knows what was ACTUALLY USED vs what's CURRENTLY AVAILABLE
	- Reproducibility > Recency

### Communication

| Channel | Purpose |
|---------|---------|
| Chat | Brainstorming, asking questions |
| Plan file | Key points and implementation steps |

**Proactivity (CRITICAL):**
- On skill start: Ask context questions IMMEDIATELY, don't wait
- Clarify SCOPE, SOURCES, CONNECTIONS first
- THEN explore with clear direction

**Questions:**
- One question at a time, based on previous answer, prefer multiple choice, 'askuserquestion' tool
- Questions building up on each other, one leads to another

**Plan-File:**
- Use system-provided plan file path from Plan Mode message
- ALWAYS use Write/Edit tool to update plan file
- NEVER write plan content directly in chat

### Plan File Management

**Core Principle:** Build the plan ITERATIVELY.

- **CRITICAL:**
- After each chat exchange: UPDATE the plan file
- Never write the complete plan at once
- Plan grows organically through conversation
- Only call ExitPlanMode when plan reflects current understanding

### Worker Scoping (in Plan)

**The plan must be structured for worker dispatch:**
- Each deliverable = potential worker task
- Identify which tasks are parallelizable (disjoint files) vs sequential (dependencies)
- For each worker task: specify input data, reference files, target files, constraints
- Glue work (server.py registration, config edits) stays with Opus — don't plan workers for trivial tasks

**Plan file MUST include a Workers section:**
```
## Workers
- Worker A: <name> — <deliverable> — <target files>
- Worker B: <name> — <deliverable> — <target files>
- Glue: <what Opus does after merge>
```

### Verification Planning (MANDATORY)

**BEFORE finalizing plan, ask yourself:**
- How will I verify that the implementation succeeded?
- What command/test/check proves correctness?

**Plan file MUST include a Verification section:**
- Concrete command to run
- Expected output/behavior
- What to check (file exists, content matches, test passes, etc.)

**Verification happens AFTER workers are merged, not during worker execution.**

### Verify Before Plan (MANDATORY)

**When a fix depends on external behavior (API responses, CLI output, file formats):**
1. FIRST: Inspect the actual response/output (curl, debug script, MCP tool call)
2. THEN: Write the plan based on verified data
3. NEVER plan a fix based on assumed external behavior

**Debug scripts** go in `debug/` folder when verification needs more than a one-liner.

**Testing/Debug Tasks (MANDATORY):**
Before proposing a test framework or debug approach, ask:
→ "What is the real risk we need to catch?"
→ Match the testing approach to the actual failure mode
→ Quantity (76 tests) != Quality (catches the right risk)
→ Example: Unit tests against static HTML fixtures don't catch the real risk for web scrapers (HTML structure changes). A scraping suite with live baselines + regression detection does.

**Red Flags:**
- "The API returns X" without having seen it
- Planning isinstance/type checks without knowing the actual type
- First verification attempt fails (e.g. auth error) and you proceed anyway
- Plan says "no code change needed" without thinking through edge cases
- Proposing a test pattern without asking "what failure mode does this actually catch?"

**"No Code Change" Plans (MANDATORY):**
When your plan concludes "existing code handles this, just run it":
1. Ask: What happens at the BOUNDARY between existing data and new data?
2. Ask: What failure modes exist? (overlaps, gaps, duplicates, ordering)
3. Ask: Has this exact scenario been tested before, or am I the first?
If ANY answer is uncertain → plan a verification step BEFORE declaring "no code change needed".

### Source Verification (BEFORE ExitPlanMode)

**MANDATORY:** Before calling ExitPlanMode, list all unverified external claims in the plan.

Format in chat:
```
Zur Verifizierung vor IMPLEMENT:
- [Claim 1] → Quelle: [URL/Doc/API] → VERIFIZIERT/ANNAHME
- [Claim 2] → Quelle: [URL/Doc/API] → VERIFIZIERT/ANNAHME
```

If any claim is ANNAHME: verify now (WebFetch, RAG search, GitHub) or flag explicitly in the plan file as `ASSUMPTION:`.

**Why:** Plans built on unverified external claims (API compatibility, library features, model capabilities, server parameters) fail during IMPLEMENT. 5 minutes of verification saves hours of rework. Concrete failure: `-ub 512` was assumed safe from docs but crashed llama-server on Metal — testing would have caught this in PLAN.

### Execution During Planning

If the planning session requires module execution to refine the plan:
1. Call ExitPlanMode
2. Execute only what is needed to refine the plan
3. Ask user to manually return to plan mode

### Before ExitPlanMode

- Plan file MUST reflect current implementation approach
- NEVER call ExitPlanMode with stale plan
- **ALWAYS ask "Any remarks?" and wait for user signal** ("done", "continue", "implement")
  - Saves tokens (no rejected ExitPlanMode calls)
  - User controls transition timing

---

## Implementation Phase (IMPLEMENT)

Implementation happens through **workers** — isolated Claude sessions in git worktrees via tmux.

### Opus Role

Opus orchestrates workers for substantial tasks and does small tasks directly:
- **Direct implementation** for trivial modules (< 150 lines, clear pattern to follow, reuses existing functions)
- **Spawn workers** for substantial tasks (200+ lines, unclear pattern, new infrastructure)
- **Glue work** after workers are merged (trivial wiring: imports, tool registration, small config edits)
- **Verification** after merge (run tests, MCP tool calls)

### Spawning Workers

For each worker task from the plan, follow this sequence:

#### 1. Scope the Task

Clarify with the user (2-3 exchanges max):
1. **What** should the worker do? (concrete deliverable)
2. **Where** in the codebase? (files, directories)
3. **Constraints?** (don't touch X, follow pattern Y, use library Z)
4. **Gitignored files needed?** (.env, .mcp.json, .venv, etc.)
   - If YES: skip worktree, use project directory directly
   - If NO: proceed with worktree isolation

#### 2. Pre-Flight Check (MANDATORY for worktree mode)

**BEFORE creating the worktree**, verify that ALL target files are tracked by git:

```bash
git check-ignore <file-or-dir-1> <file-or-dir-2> ...
```

- If ANY target file/directory is gitignored → **STOP and warn the user**
- Gitignored files do NOT exist in worktrees — the worker will find nothing and fall back to editing main
- Options: (a) un-ignore the files first, (b) skip worktree and work in project directory directly

#### 3. Build the Prompt

Write the prompt as a Markdown file at `/tmp/spawn-worker-<project>-<worker-name>.md`. This avoids shell escaping issues and makes the prompt reviewable.

Present it to the user:

"Prompt geschrieben nach `/tmp/spawn-worker-<project>-<worker-name>.md`:"

```
<the prompt content>
```

"Passt das, oder soll ich etwas aendern?"

The prompt MUST include:
- The specific task with concrete deliverables
- Which files/directories to work in
- Reference to plan file if one exists: "Read .claude/plans/*.md for full context"
- **Domain skill activation** (ALWAYS, when project has domain skills):

```
FIRST ACTION (before any file reads or edits):
1. Activate ALL project-relevant skills listed in the system prompt
   (e.g., /linkedin for LinkedIn MCP projects, /rag for RAG projects)
2. For worktree mode: Run /worker-rules

Skills provide critical tool references, parameter formats, and workflow rules.
Without them, the worker will guess parameters and produce wrong code.
Do NOT skip this step.
```

**Worktree environment hints** (include in prompt when applicable):
- `./venv/bin/python` does NOT exist in worktrees (gitignored). Use `python3` for syntax checks.
- `.env`, `.mcp.json` are not available in worktrees. For MCP-dependent tasks: skip worktree, work in project directory.
- `.claude/settings.local.json` is NOT copied to worktrees (gitignored). Without it, workers only see globally installed plugins — project-local plugins and skills are invisible. **Fix:** Copy settings before spawning workers (see Step 4).

**Shared-file conflict prevention (CRITICAL):**
- Worktrees branch from the last COMMIT, not from the working tree. Uncommitted local changes are NOT visible to the worker.
- BEFORE dispatching a worker that touches files you've modified locally: either (a) commit your changes first, or (b) tell the worker NOT to modify those files — "File X is locally modified, do NOT change it. Write recommendations to WORKER_REPORT.md instead."
- When both Opus and worker modify the same file: merge produces duplicates or conflicts. The worker has the old version.
- Concrete failure (2026-03-17): Worker added Mojeek config to old settings.yml while Opus had completely rewritten settings.yml locally. Merge produced duplicate Mojeek entry.

**Debug/Exploration workers (MCP projects):**
- Workers debugging MCP tool issues MUST write exploration scripts (using `src/` infrastructure directly), NOT call MCP tools
- MCP tools run through the MCP server process — workers can't reliably share the browser session
- Pattern: `from src.linkedin.client import get_authenticated_tab, voyager_get` → write script → `./venv/bin/python3 dev/exploration/...`
- Concrete failure (2026-03-16): Worker tried to debug get_company_posts via MCP tool calls. Browser race condition blocked all calls. Should have written an exploration script instead.

- **Skill discovery:** Check `.claude/skills/` in the project for available domain skills. Include activation commands for each relevant skill in the worker prompt.

**Domain Skill Activation Checklist (BEFORE writing prompt):**
1. Run: `ls .claude/skills/` in the project
2. For EACH skill found: add `/plugin:skill-name` activation to the prompt
3. Use FULLY QUALIFIED names: `/searxng:searxng` NOT `/searxng`
4. If unsure about the name: check the skill's SKILL.md frontmatter `name:` field
5. Concrete failure (2026-03-15): 3 decision workers dispatched with only /worker-rules, no /searxng:searxng.

**Plugin venv vs Project venv:**
- Plugin cache (`~/.claude/plugins/cache/...`) does NOT have a venv — it's a copy of source files only
- Plugin scripts that need Python: use the PROJECT venv (`./venv/bin/python`) not the plugin cache venv
- crawl_site.py, explore_site.py etc. live in plugin cache but must be run with project venv
- Concrete failure (2026-03-15): `$PLUGIN/venv/bin/python crawl_site.py` → exit 127 (file not found). Correct: `./venv/bin/python crawl_site.py`

Wait for user approval before proceeding.

#### 4. Create Worktree (if applicable)

```bash
git worktree add -b <worker-name> .claude/worktrees/<worker-name>
```

If the branch already exists, STOP and inform the user.

**Worktree Repo Verification (CRITICAL — MANDATORY):**
After creating the worktree, IMMEDIATELY verify it points to the correct project:
```bash
ls .claude/worktrees/<worker-name>/dev/  # or another known project directory
```
- The worktree MUST be inside the CURRENT project repo (`pwd`)
- NEVER spawn a worker in a worktree that belongs to a different repo
- If verification fails: `git worktree remove`, investigate, retry
- Concrete failure (2026-03-17): `git worktree add` created worktree in SearXNG repo instead of RAG repo. Worker found wrong dev/ structure, wasted a full spawn cycle.

**Copy project plugin settings to worktree** (required for project-local plugins/skills):
```bash
mkdir -p .claude/worktrees/<worker-name>/.claude
cp .claude/settings.local.json .claude/worktrees/<worker-name>/.claude/settings.local.json 2>/dev/null
```
Without this, workers only see globally installed plugins. Project-local skills (e.g., `/searxng:searxng`) will fail to activate.

**Symlink venv if worker needs Python tests** (venv is gitignored, does not exist in worktrees):
```bash
ln -sf "$(pwd)/venv" .claude/worktrees/<worker-name>/venv
```
Without this, `./venv/bin/python` fails in the worktree and workers cannot run tests, scripts, or dev suites. Check: does the worker prompt include any `./venv/bin/python` or `python dev/` commands? If yes, symlink is mandatory.

Concrete failure (2026-03-16): 3 bug-fix workers reported "verified" but had no venv — tests never actually ran. Discovered only when Opus tried to verify post-merge.

#### 5. Spawn

Resolve PLUGIN_DIR from the iterative-dev plugin path.

```bash
source $PLUGIN_DIR/src/spawn/tmux_spawn.sh
spawn_claude_worker_from_file "workers" "<worker-name>" "<project-or-worktree-path>" "sonnet" "/tmp/spawn-worker-<project>-<worker-name>.md"
```

#### 6. Confirm

Report to user:
- Worker name and branch
- Worktree path (if applicable)
- Prompt file: `/tmp/spawn-worker-<project>-<worker-name>.md`
- tmux attach command: `tmux attach -t worker-<project>-<worker-name>`
- List current project workers: `worker_list` (auto-filters by project)

### Worker-Done Notification (Automatic)

When a worker's Claude process exits (success or failure), a signal file `/tmp/worker-<name>.done` is created automatically. A PostToolUse hook (`worker-done-check.sh`) checks for these files on every tool call in the parent session.

**How it works:**
1. Worker exits → `touch /tmp/worker-<name>.done` fires (chained with `;`, runs even on crash)
2. Parent session makes any tool call → PostToolUse hook detects the `.done` file
3. Hook returns `systemMessage: "Worker <name> ist fertig."` → Claude sees it as a system hint
4. Hook deletes the `.done` file (one-time notification)
5. Claude decides when to read the worker's output (WORKER_REPORT.md or pane capture)

**Implications:**
- No manual "Worker fertig" needed — Claude gets a system hint at the next tool call
- No workflow interruption — Claude sees the hint and reads the report when it makes sense
- Works for both clean exits and crashes (`;` chaining)
- Multiple workers finishing simultaneously: all collected in one systemMessage
- Zero overhead when no workers are running (glob finds nothing → exit 0)
- Workers that hit STOP problems should write `STOP: <reason>` in WORKER_REPORT.md before exiting — the notification still fires, and Claude reads the report to see the STOP reason

### While Workers Run

**MANDATORY after dispatching workers:** Suggest productive parallel work to the user.

Options to propose (pick what's relevant):
- **Code Review:** Review related code that workers will integrate with
- **Docs Check:** Verify DOCS.md/README.md are current for touched directories
- **Eval Prep:** Prepare evaluation criteria for worker output
- **Independent Tasks:** Other open bead items that don't conflict with worker scope
- **Automation Improvements:** Draft SKILL/CLAUDE.md improvements noticed during planning

Format: "Workers dispatched. Waehrend die arbeiten, schlage ich vor: [1-3 concrete items]"

**Why:** Dead time between dispatch and merge wastes session capacity. Even 10 minutes of parallel work (docs, reviews) saves a full exchange later.

### Worker Orchestration (Monitor & Interact)

The main agent can monitor and interact with running workers via shell functions in `src/spawn/tmux_spawn.sh`. Source the file first, then use the functions.

```bash
source $PLUGIN_DIR/src/spawn/tmux_spawn.sh
```

#### List Active Workers

```bash
worker_list
```
Returns worker names (without `worker-` prefix), one per line. Empty output = no workers running.

#### Read Worker Output

```bash
worker_capture <name> [lines]
```
- Captures the worker's tmux pane content to `/tmp/worker-<name>-pane.txt`
- `lines` (optional): number of scrollback lines to capture (default: entire scrollback)
- Returns: path to the capture file

**CRITICAL — Use Read/Grep Tools, NEVER Bash sed/grep Chains:**

The pane file is a regular text file. Treat it EXACTLY like a source file — Read tool with offset/limit, Grep tool for pattern search. NEVER use `sed -n`, `bash grep`, `tail`, or `head` on it.

**Correct workflow:**
```
# Step 1: Capture (Bash — only this step uses Bash)
worker_capture feature-x

# Step 2: Find problems (Grep tool)
Grep(pattern="ERROR|STOP|FAILED", path="/tmp/worker-feature-x-pane.txt")

# Step 3: Read specific section (Read tool with offset/limit)
Read(file_path="/tmp/worker-feature-x-pane.txt", offset=150, limit=50)

# Step 4: Read full output if needed (Read tool)
Read(file_path="/tmp/worker-feature-x-pane.txt")
```

**WRONG — This wastes 10+ tool calls:**
```
Bash(sed -n '130,210p' /tmp/worker-feature-x-pane.txt)
Bash(sed -n '140,220p' /tmp/worker-feature-x-pane.txt)
Bash(sed -n '150,230p' /tmp/worker-feature-x-pane.txt)
... repeat 10 times with manually shifted offsets
```

**Use cases:**
- Check worker progress without switching windows
- Search for errors or specific output patterns
- Verify worker is on track before it finishes

#### Send Instructions to Worker

```bash
worker_send <name> "your message here"
```
- Sends text as user input to the worker's Claude Code session (followed by Enter)
- Same mechanism as the initial prompt delivery

**Use cases:**
- Course-correct a worker mid-task ("Focus on X, skip Y")
- Provide additional context the worker needs
- Tell worker to wrap up ("Commit your current state and write WORKER_REPORT.md")

**Caution:** Only send instructions when the worker's Claude session is waiting for user input. Use `worker_capture` first to check the worker's state.

### Scope Extension During IMPLEMENT

When the user introduces a new scope during IMPLEMENT (e.g., "let's also build X"):
1. **Do NOT expand the current cycle** — finish what's planned first
2. **Dispatch a worker** for the new scope (worktree if code-only, project-dir if MCP needed)
3. **User works directly with the worker** on the new scope
4. **Opus stays on the original scope** and closes the cycle cleanly (verify, glue, RECAP)
5. Worker results are merged in the NEXT cycle

**Why:** Scope creep within a cycle blurs RECAP boundaries. Workers isolate new scope without blocking the current cycle.

### Merging Worker Results

**CRITICAL: Always MERGE, never copy files from worktrees.**

When a worker is done (user confirms or you verify the worktree has commits):

```bash
# 1. Read worker report (handoff artifact)
cat .claude/worktrees/<worker-name>/WORKER_REPORT.md

# 2. Review commits
git log main..<worker-name> --oneline

# 3. Merge into current branch
git merge <worker-name>

# 4. Remove worker report (process artifact, not repo content)
git rm -f WORKER_REPORT.md && git commit -m "cleanup: remove worker report"

# 5. Cleanup worktree, branch, AND tmux session
tmux kill-session -t worker-<project>-<worker-name> 2>/dev/null
git worktree remove .claude/worktrees/<worker-name>
git branch -d <worker-name>
```

**Tmux Session Cleanup (MANDATORY — after merge OR abort):**
- ALWAYS kill the tmux session after merge, abort, or worker failure
- Use `tmux kill-session -t worker-<name>` (NOT `kill-window` — sessions are 1:1 per worker)
- NEVER leave orphaned tmux sessions running — they consume resources and confuse future spawns
- When killing sessions, only kill sessions belonging to the CURRENT project:
  - Check `worker_capture <name>` output for project path before killing unknown sessions
  - Do NOT blanket-kill all `worker-*` sessions — other projects may have active workers
- Concrete failure (2026-03-17): `tmux kill-session` on ALL worker sessions killed a worker from another project (worker-decisions from SearXNG). Only kill sessions YOU spawned in THIS session.

**PROHIBITED:**
- `cp` from worktree to main repo — destroys git history, defeats worktree purpose
- Manually recreating files that the worker already committed
- Cherry-picking individual files instead of merging the branch

### RECAP Notes (MANDATORY during IMPLEMENT)

Create `recap_notes.md` in the project root at the START of IMPLEMENT phase. Add notes throughout implementation whenever you observe:
- Worker issues (wrong API calls, rule violations, missed patterns)
- Process inefficiencies (things that took longer than they should)
- Improvement ideas for automation files

**Why:** Context compression can drop earlier observations. The file persists and is read during RECAP phase. Delete the file during CLOSING (it's a process artifact, not repo content).

### After Workers Are Merged

1. **Verify** — run tests, MCP tool calls, check integration
2. **Glue work** — register tools, update imports, trivial wiring (1-3 lines)
3. **If issues found** — fix directly (small) or user spawns another worker (large)
4. Ask: "Proceed to RECAP?"

User confirms → next response starts with 🔍 RECAP

---

## Recap Phase (RECAP)

### Phase Entry

1. Ask user: "Activate Plan Mode for RECAP (`/plan`)"
2. Wait for Plan Mode system message
3. Proceed with evaluation report (read-only enforced by Plan Mode)

### Plan File Handling

**CRITICAL:** Report OVERWRITES plan file completely.

- **Executed tasks:** Only mentioned in Execution summary
- **Open items:** Listed in "## Open Items" section → handled in CLOSING phase (Bead or discard)
- **No "ORIGINAL PLAN" section** - plan is consumed by execution

### Report

Claude writes a report that OVERWRITES the plan file:

#### 1. Execution

- What matched the Plan File, what deviated from the Plan File

#### 2. Process Reflection

Explicitly analyze the planning phase across two dimensions:

##### 2.1 Efficiency

###### Questions During Planning
- Were my questions focused or scattered?
- Did we iterate too much? Could we have reached the finished plan faster?
- Did I correctly understand the user's answers?
- Did the user give insightful answers?

###### Red Flags
- More than 3 back-and-forth exchanges before stable plan
- User had to correct my assumptions multiple times
- I proposed solutions before understanding the problem
- Execution Path Errors (Most IMPLEMENT failures trace back to skipped verification in PLAN)
- User did not explicitly state what he wants, gave bad directions
- User did not understand you

###### References
- Did I explicitly ask for references early enough?
- Were the references helpful or did they lead me astray?
  - Should the references have been more granular or broader?

##### 2.2 Assumptions/Hallucinations

###### Questions
- Did I make assumptions that needed correction?
- Was the user's intent clear from the start?
- Did I verify assumptions or just proceed?

###### Categories
- **Structural:** Directory layout, file locations, naming conventions
- **Semantic:** What columns mean, what functions do, data flow
- **Behavioral:** Expected output format, error handling, edge cases

###### Rule
Every assumption should be either:
1. Verified by reading code/docs
2. Explicitly confirmed with user
3. Documented as "ASSUMPTION: ..." in plan file

##### 2.3 Algorithm Investigation

When investigating WHY something behaves a certain way (selection logic, thresholds, metrics):

1. **ASK FOR SOURCE CODE IMMEDIATELY**
   - "Where is [metric] calculated?"
   - "Which file contains the selection logic?"

2. **NEVER assume metric definitions**
   - Metric names can be misleading — always read the actual calculation
   - Read the calculation, don't infer from name

3. **Trace the data flow**
   - What data goes in?
   - When is it calculated? (Once? Per iteration?)
   - What triggers recalculation?

**Red Flag:** Making hypothesis about algorithm without reading source = hallucination risk

#### 3. Hooks Evaluation

Evaluate current hooks for improvements:

**Questions:**
- Did a hook block something it shouldn't have?
- Did a hook allow something it should have blocked?
- Is output silencing helping or hiding problems?
- Should a recurring command pattern become a hook rule?

**Improvement Candidates:**
- Commands that failed due to missing hook rules
- Verbose output that polluted context
- Security patterns that should be blocked

**Token Efficiency Analysis:**

Review Bash tool calls from this session and identify where hooks could have saved tokens:
- Commands with large outputs that could be piped through `head -N` or `tail -N`
- Repeated commands whose output could be cached or silenced after first run
- Commands where only a subset of output was needed (e.g., `ls` when only checking existence)
- Tools that returned full file contents when a targeted grep would suffice

For each finding: estimate token waste (small/medium/large) and propose a hook rule or pattern.

**Goal:** Keep context window clean so more work fits in a single session.

**Reference:** `~/.claude/scripts/README.md`

#### 4. Agent Evaluation

Evaluate subagent usage during the cycle (if agents were used).

##### 4.1 Self-Assessment (Opus only)

These require full session context that Sonnet does not have — Opus evaluates them directly.

**Missed Agent Usage:**

Identify situations where agent should have been used but wasn't:

| Situation | What I Did | What I Should Have Done |
|-----------|-----------|------------------------|
| ... | Manual search | Use agent for exploration |

**When to Use Agent:**
- Exploration over >3 files
- Unknown directory structure
- Pipeline tracing (input → output)
- When hook requests it

**Domain Skill Compliance Check (MANDATORY):**
For each active domain skill (reddit, github, etc.):
- Was the subagent dispatched when dispatch rules required it?
- If not: why? (single lookup = OK, multi-query research without sub = NOT OK)
- This catches the pattern: "I did it myself instead of dispatching" — which bypasses the skill's Dispatch First → Verify workflow

**When NOT to Use Agent (do it yourself):**
- Direct reads of known paths
- Verification after agent output
- Single targeted grep/glob

#### 5. Beads Evaluation

Run `bd list -s open` to check open beads, then evaluate:

##### 5.1 Active Beads

For each open bead touched this cycle:
- Was it commented after every significant action? If not → note the gap
- Is the latest comment sufficient for a fresh session to continue? If not → add comment in IMPROVE

##### 5.2 New Beads

Discovered work that needs cross-session tracking?
- List candidates with proposed title and description
- Title = topic, not date (e.g., "LSP Integration" not "Session 02.03")

##### 5.3 Close Completed Beads

For each bead where the topic is fully resolved:
- Mark for closing with reason

**Format:** `<id>: <reason>`

Example: `project-abc-e0m: Fixed threshold logic by adding null check in src/selection.py:42`

##### 5.5 IMPROVE Action List (MANDATORY)

**At the end of Section 5, produce a concrete action list for IMPROVE phase:**

```
BEADS ACTIONS:
- CLOSE: <id> — <reason>
- COMMENT: <id> — <what to write>
- CREATE: "<title>" — <description summary>
```

**Why:** Without an explicit action list, IMPROVE must re-derive actions from prose. The action list is the handoff contract between RECAP and IMPROVE — unambiguous, executable, no interpretation needed.

##### 5.4 Continuation Check (MANDATORY)

After listing all beads to close in 5.3, check: **Would closing them leave ZERO open beads?**

If yes → a Continuation-Bead MUST be created in IMPROVE phase:
- Title: Next work topic (NOT "Session YYYY-MM-DD")
- Description: What was done (context), what's next (scope), key files/repos

**Rationale:** A session with zero open beads = next session starts with zero context. The continuation bead is the bridge.

**This check is part of "Presenting Beads Hygiene" in chat text.** When all beads are proposed for closing, explicitly state: "All beads closed → Continuation-Bead needed" with proposed title and description.

#### 6. Improvements

**CRITICAL:** Every Process Improvement MUST reference an exact Automation File path + section.
Format: `[Description] → [Automation File path] → [Section to add/extend]`
Example: `API-Endpoints verifizieren → ~/.claude/rules/verify-before-execution.md → "Verify Before Execution"`
Improvements without concrete target path are not actionable → reject.

**Automation File Categories:**
1. `~/.claude/rules/*.md` (global — applies to ALL projects)
2. `<project>/CLAUDE.md` (project — applies to THIS project only)
3. Plugin files — see **Global Plugins** registry in `~/.claude/rules/plugins.md`
4. `.claude/commands/*.md` (project slash commands)
5. `~/.claude/scripts/` (hooks)

**Path Clarity (CRITICAL):** Always use FULL paths to distinguish global from project:
- Global: `~/.claude/rules/<name>.md` (e.g., `~/.claude/rules/verify-before-execution.md`)
- Project: `<project>/CLAUDE.md` or `<project>/.claude/rules/<name>.md`
- NEVER write just `CLAUDE.md` or rule file name without qualifier — ambiguous which one is meant

**Discovery:** Run `find ~/.claude/plugins/cache/brunowinter-plugins/ -name "plugin.json"` to locate plugin source paths.

##### 6.1 Content Improvements (Code/Docs)

Prioritization:
- **Critical:** Must fix (breaks functionality, wrong behavior)
- **Important:** Should fix (code quality, maintainability)
- **Optional:** Nice to have (style, minor optimizations)

**Handling in IMPROVE Phase:**
- Code (*.py, *.yml, etc.) → **Bead** (needs own PLAN→IMPLEMENT→RECAP cycle)
- Docs/README/Automation Files → **Direct Edit** in IMPROVE

##### 6.2 Process Improvements

Prioritization (by OUTCOME):
- **Critical:** Process errors that WOULD HAVE caused critical code issues
- **Important:** Process errors that caused detours but correct outcome
- **Optional:** Minor process inefficiencies

**Handling in IMPROVE Phase:**
- Automation Files (Skills, Commands, Agents, Hooks) → **Direct Edit** in IMPROVE
- Code → **Bead**

**CRITICAL: Process Improvements = Automation Files ONLY.**
Docs/README are Content Improvements (6.1), never Process Improvements.
If an "improvement" targets a DOCS.md or README → it belongs in 6.1, not here.

**Key insight:** OUTCOME determines severity. Wrong process + correct result = Important (not Critical).

**Recurring vs One-Off (CRITICAL):**
- Automation Files are for RECURRING issues that need persistent rules
- One-off problems (single edge case, one-time fix) do NOT belong in Automation Files
- Ask: "Will this issue come up again across multiple sessions/projects?" → YES = Automation File, NO = skip
- Polluting Automation Files with one-off rules degrades their signal-to-noise ratio

**CRITICAL: Every process error MUST produce a config change.**
- Identified process error without config change = wasted insight, error WILL repeat
- Each process improvement in RECAP MUST name the exact config file + section to change
- In IMPROVE: Execute that change. No exceptions.
- "Lesson Learned" that stays only in the RECAP report = FAILURE

**READ BEFORE PROPOSING (MANDATORY):**
- Before proposing ANY process improvement, READ the target automation file first
- You need to see what's already there to propose a meaningful change
- Without reading: you guess where it goes and what already exists → wrong proposal

##### 6.3 DOCS.md Check (MANDATORY)

**Note:** Reading DOCS.md files triggers `.claude/rules/documentation.md` (glob match on `**/*.md`). The documentation standard rules are automatically loaded during this check.

**For full structural reviews** (not just drift checks), use `/iterative-dev:doc-review` which provides a phased workflow for mapping, planning, and fixing documentation structure.

**ALWAYS explicitly answer:**
- Does DOCS.md need updating? YES/NO
- If YES: What sections? (new scripts, changed parameters, new outputs)

**CRITICAL - NON-NEGOTIABLE:**
- DOCS/README updates are **NEVER optional**
- DOCS/README updates are **NEVER skippable**
- DOCS/README updates are **NEVER "insignificant"**
- Every new script, changed behavior, or new parameter MUST be reflected **IMMEDIATELY**
- Skipping DOCS updates = **BROKEN WORKFLOW** for future sessions
- If Open Items include DOCS update → **DO IT IN IMPROVE, NOT LATER**

**Active Verification (MANDATORY — not a passive question):**

"Does DOCS.md need updating?" is NOT answered from memory. You MUST actively verify:

1. **Read ALL DOCS.md/README.md** in directories touched this cycle
2. **Compare directory trees** in docs vs actual files on disk (`ls` the directory)
3. **Check for drift** — concrete checklist per doc file:

| Check | How | Drift = |
|-------|-----|---------|
| Files listed in tree | `ls` actual dir, compare to tree in doc | File added/deleted/renamed but doc shows old tree |
| Function tables | Read source, compare to doc tables | Function added/removed/signature changed |
| Variables/constants | Read source, compare to doc tables | Value changed, new constant added |
| Architecture decisions | Compare doc claims to actual code | e.g. "Manual numpy/pandas" but code uses ta-lib |
| Entry points / CLI args | Read argparse in scripts, compare | New arg added, default changed |
| Import paths / dependencies | Read imports in source | New dependency, removed module |

4. **Report per file** in the RECAP plan file:

```
DOCS DRIFT CHECK:
- src/features/DOCS.md: OK / DRIFT (details)
- DOCS.md (root): OK / DRIFT (details)
- README.md: OK / DRIFT (details)
```

5. **Every DRIFT item → Content Improvement (6.1)** with priority Important or Critical

**Why this is non-negotiable:** Docs are the primary navigation tool for future sessions (AI reads DOCS.md before exploring code). Stale docs = wrong assumptions = wasted effort. A doc that lists a deleted file is WORSE than no doc at all — it actively misleads.

#### 7. Open Items

List any tasks from the original plan that were NOT executed.

**CRITICAL - EMPTY PLATE RULE:**
- Every Open Item MUST become a Bead before CLOSING
- NO exceptions - even "small" items get Beads
- Rationale: New session = zero context. Beads preserve continuity.
- Test: After CLOSING, could someone pick up this work with ONLY the Bead info?

### Presenting Beads Hygiene

**Section 5 Beads Hygiene MUST appear in BOTH the plan file AND in chat text.** The user cannot see the plan file — beads status only in the plan file is invisible to them.

**Format in chat (BEFORE Process Improvements):**

For each open bead:
```
**<id>** (<title>) — <ACTIVE or CLOSE vorgeschlagen>
- Stand: <last comment summary>
- Kommentiert diese Session: JA/NEIN
- Reason (if close): <why>
```

### Presenting Process Improvements

**Section 6.2 Process Improvements MUST appear in BOTH the plan file AND in chat text.** The user cannot see the plan file — improvements only in the plan file are invisible to them.

**Automation File Rule (CRITICAL):** BEFORE proposing WHERE an improvement goes, READ the target automation file. Decide placement based on actual content, not assumptions about what's in there. This means: read ALL target files DURING RECAP, BEFORE writing the Improvements section — not after presenting it to the user.

### Collecting Improvements

After presenting improvements:
1. Ask: "Any remarks?"
2. User gives remark → **Analyze for system improvement**
3. Ask: "More remarks?"
4. Repeat until user says "done" or "improve"

**CRITICAL: Remarks → Analyze → Propose Improvement + Location**

When user gives ANY remark:
1. **Analyze:** What went wrong? What could be better?
2. **Propose:** Concrete improvement
3. **Locate:** WHERE the improvement would happen (Automation File + path)

**Output Format:**
```
Remark: [User's remark]
Analysis: [What went wrong]
Improvement: [Concrete change]
Location: [Automation File + file path]
```

**The Goal:** Every remark → concrete improvement proposal with exact location.

### Phase Exit

1. Ensure all improvements are written to plan file
2. Call ExitPlanMode
3. Next response starts with 🛠️ IMPROVE

---

## Improve Phase (IMPROVE)

**Purpose:** Execute improvements from plan file.

**CRITICAL:** IMPROVE has no validation after it. Therefore:
- Code → Bead (own cycle with validation)
- Everything else → Direct Edit

### Workflow

1. Read plan file "## Improvements" and "## Open Items" sections
2. **DOCS/README updates FIRST** - these are NEVER skippable:
   - If any new script was created → update DOCS.md
   - If any script behavior changed → update DOCS.md
   - If any new output was generated → update DOCS.md
3. For each other improvement (see 6.1/6.2 Handling):
   - **Code?** → `bd create --title "..." --type=...`
   - **Automation Files?** → Edit workflow:
     **SOURCE REPO RULE (CRITICAL — Plugin Files):**
     Plugin automation files (agents, skills, commands) live in SOURCE REPOS, not in the plugin cache.
     - Cache path (`~/.claude/plugins/cache/...`) is a COPY — edits get overwritten by plugin-sync
     - ALWAYS resolve the source repo path first: check `~/.claude/rules/plugins.md` → Plugin Cache Management for repo paths
     - Edit in source repo → commit → plugin-sync → new session
     - If you edit cache directly = LOST WORK on next sync
     1. READ the target file fully
     2. SEARCH for overlapping rules/sections
     3. If overlap: EXTEND existing section with new content
     4. If no overlap: ADD new section, keeping all existing sections untouched
     5. If restructuring needed: MOVE text, never delete it
4. Handle Beads (from RECAP Section 5):
   - Create: `bd create --title "..." --type=...`
   - Update: `bd comments add <id> "..."`
   - Close: `bd close <id> --reason="..."`
5. **Handle Open Items (MANDATORY - EMPTY PLATE RULE):**
   - For EACH Open Item from RECAP Section 7:
   - `bd create --title "..." --description="..." --type=task`
   - NO exceptions - session ends with ZERO open items
6. Ask: "Proceed to CLOSING?"

User confirms → next response starts with ✅ CLOSING

---

## Closing Phase (CLOSING)

Only enter when user confirms (e.g., "proceed", "close", "done").

**PRE-CLOSE CHECK (MANDATORY):**
- Verify ALL Open Items from RECAP have Beads
- If ANY Open Item has no Bead → CREATE IT NOW before proceeding
- Delete `recap_notes.md` from project root (process artifact, not repo content)
- This check is NON-NEGOTIABLE

1. `bd export` (JSONL export — replaces old `bd sync`)
2. **Commit ALL repos with changes via git-committer agent:**

   **PRE-DISPATCH: Finish all edits first.**
   Before dispatching: ensure ALL file writes (Edit/Write tool calls) for this session are complete.
   Do NOT dispatch while still editing files — the agent runs git status immediately and will miss in-flight changes.

   **Dispatch is simple — just repo paths:**
   ```
   Task(subagent_type="git-committer", prompt="""
   Repos:
   - /path/to/project
   - /path/to/plugin-source
   """)
   ```
   - The git-committer handles EVERYTHING: status, diff, staging, commit message, commit, push
   - The git-committer auto-detects plugin repos and runs plugin-sync if needed
   - Your ONLY job: collect repo paths that had changes this session, then dispatch
   - No file lists, no gitignore checks, no plugin-sync instructions needed
   - NEVER run git commands yourself — the agent does it all

   **POST-DISPATCH VERIFY (NON-NEGOTIABLE — ONE COMMAND ONLY):**
   ```bash
   git -C /path/to/repo1 status --short && git -C /path/to/repo2 status --short
   ```
   Empty output = all committed + synced = done. That is the ONLY verification allowed.
   - Do NOT run `git log`, `git diff`, `git diff --stat`, or any other git command
   - Do NOT check commits individually per repo
   - Do NOT "spot-check" what was committed
   - The git-committer agent + plugin-sync already handled everything — trust the process
   - If output is NOT empty → check: are the remaining files in gitignored/excluded directories (`.beads/`, `.claude/`)? If YES → nothing to do, move on immediately. Do NOT run further git commands to "investigate".
   - If output shows genuinely untracked/modified files outside exclusions → re-dispatch ONCE for that repo only with this NOTE:
     ```
     NOTE: Previous commit was incomplete — check git status carefully and stage ALL remaining changes.
     ```
     Do NOT list specific files — the agent finds them via git status.

   **CRITICAL: When nothing to commit, STOP IMMEDIATELY.**
   If git-committer reports "nothing to commit" or only gitignored files remain → accept the result and move on. Do NOT run additional git commands to "confirm" or "investigate". One `status --short` tells you everything — 5 follow-up git commands to verify "nothing" = wasted tokens.

3. Ask: "New cycle or done for now?"

---

## Explore Agent (code-investigate-specialist)

Full rules in `~/.claude/rules/code-investigate-agent.md` (global — applies to all projects).
