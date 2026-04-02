---
name: iterative-dev
description: (project)
---

# Iterative Development Skill

**Glue work** (imports, registration, trivial wiring, small config edits) is done by Opus directly — dynamically while workers are running or after a worker merges. Not a phase, not a step. Standard behavior.

### Session Start (MANDATORY)

`bead_list(status="open")` → read relevant work beads.

---

**EVERY RESPONSE STARTS WITH A POSITION INDICATOR** — phase + current step:
- `📋 PLAN — Phase 1, Step 1: Session Scope`
- `📋 PLAN — Phase 1, Step 2: Status Quo`
- `📋 PLAN — Phase 1, Step 3: Dev Scripts Check`
- `📋 PLAN — Phase 1, Step 4: Gap Analysis`
- `📋 PLAN — Phase 2, Step 1: Worker Split`
- `📋 PLAN — Phase 2, Step 2: Deliverables & KPIs`
- `🔨 IMPLEMENT — [current section, e.g. "Worker Lifecycle" / "After Deliverables Complete"]`

---

## Planning Phase (PLAN)

### Phase 1 — Understand

Sequential steps. After each step: present findings, wait for remarks, then proceed.

**Step 1 — Session Scope**

Repeat what the user wants in your own words.

🛑 STOP — Ask for remarks.

**Step 2 — Status Quo**

1. **Decisions Check** — Read the relevant `decisions/` file(s) for this topic area.
   - What is the current documented IST-Stand? What is SOLL?
   - What items are marked OPEN?
   - If `decisions/` is outdated or missing for this component → flag explicitly
2. **Code Check** — Read the actual implementation files referenced in the decisions.
   - Does the code match the documented state?
   - Any drift between `decisions/` and what's in source? → flag explicitly
   - **Flag reference patterns:** Which existing files/functions serve as the pattern for new code? Mark them explicitly as Reference Files.
3. **Present status quo to user.** State explicitly:
   - Which files/components are affected
   - What the current state is (IST) and why it matters for this task
   - Where the work will happen (which directories, which decision areas)
   - **Reference Files** identified — existing code that workers must follow as pattern

🛑 STOP — Ask for remarks.

**Step 3 — Dev Scripts Check**

Dispatch a `code-investigate-specialist` agent with the context from Steps 1+2 (scope, affected files, IST-Stand). Agent scans `dev/` independently and reports back what is relevant and why:

- Dev scripts AFFECTED by the change (need updating as part of this task)
- Dev scripts that INFORM the task (reproduction scripts, validation suites, existing benchmarks)
- Existing fixes/workarounds (`fixes/`, `debug/`, `KNOWN_ISSUES`, `CHANGELOG`)
- Test suites that cover the affected code (do they IMPORT the module being changed, or have their own copy?)
- Agent/workflow instruction files if optimizing an automated workflow

**Agent prompt pattern:** "Given that we are changing [X files] for [Y purpose], scan `dev/` and report: (1) which dev scripts are affected by this change, (2) which dev scripts could help validate/reproduce the issue, (3) any existing workarounds or fixes."

**Why agent, not Opus:** Opus already has code context from Step 2. Dev exploration is scout work — send the specialist, keep Opus context clean.

- When debugging: read ACTUAL DATA first (dump, sample, log output); research external sources only AFTER the data doesn't self-explain

🛑 STOP — Ask for remarks.

**Step 4 — Gap Analysis**

Be brutally honest: could you implement this feature or fix with 99% accuracy using only the information gathered so far? If not — what exactly is missing?

- Do we need more information? Which? Research sources available: web, GitHub, Reddit, arxiv. Produce a sources table: Component | Source | Coverage | Gap
- Do we need more dev scripts? Which?
- If research is needed → existing pattern in other projects to follow? User's existing patterns beat generic best practices.
- Close all gaps BEFORE moving to Phase 2.

**Gap Closing = ACTUALLY reading the sources (CRITICAL):**
- When gaps are identified: check `sources/sources.md` — is the needed info already indexed?
- If indexed: QUERY the source (RAG search, file read) and extract the answer NOW
- "We have it indexed" ≠ gap closed. Gap is closed when you KNOW the answer, not when you know WHERE the answer might be.
- User approves moving to Phase 2 → all listed gaps must be closed with concrete answers, not pointers to sources.
- Concrete failure (2026-03-31): Identified 3 knowledge gaps (Crawl4AI PDF handling, cookie-wall DOM patterns, SearXNG language filtering). All sources were indexed in RAG. Said "alles im RAG verfügbar, kein Research nötig" without querying RAG. User had to push 3 times before actual RAG queries were fired.

🛑 STOP — Ask for remarks.

### Phase 2 — Worker Scoping

**Step 1 — Worker Split**

- How to split workers across the task
- Which gaps (from Phase 1, Step 4) does each worker close first

**Step 2 — Deliverables & KPIs**

Define deliverables with measurable completion criteria:
- Each deliverable: WHAT is done, HOW to verify (test command, file exists, output matches)
- **Investigation-first deliverables:** When root cause is UNKNOWN, split the deliverable: Phase 1 = investigate (what is the actual behavior, how does the system work), Phase 2 = fix based on findings. NEVER prescribe a solution in the worker prompt when the cause is unverified.
- Plan file MUST include a Deliverables section with KPIs
- **Per worker: define what exactly, up to which point, and the approval gate** — especially when research is involved: worker stops at a defined checkpoint, user gives approval before the next step begins

**Present in chat for each deliverable:**
- What will be built/fixed
- How Opus verifies it (run tests, MCP call, check output) — code review does NOT count as verification
- How the user verifies it as final quality gate (what to click, run, or check; expected outcome)
- All affected file categories (src/, decisions/, dev/, docs)
- Worker dispatch plan (which workers, which files each, which Reference Files to follow as pattern)

🛑 STOP — Ask for remarks before calling ExitPlanMode.

---

## Implementation Phase (IMPLEMENT)

Workers, lifecycle, background timer, merging: see `~/.claude/rules/workers.md`

### Dev-Branch Setup (MANDATORY at IMPLEMENT start)

Before spawning any workers:
1. `git checkout -b dev` (or `git checkout dev` if it exists)
2. All workers branch from `dev`, all merges land on `dev`
3. Opus reviews on `dev` — execution rules do NOT trigger (worktree-only paths)
4. At session end: `git checkout main && git merge dev` to sync

### Scope Extension During IMPLEMENT

When the user introduces a new scope during IMPLEMENT (e.g., "let's also build X"):

Mini-scoping (no full Phase 1 needed):
1. Summarize in chat: what is the user's task, what would a worker do
2. Spawn worker if user has no remarks

### After Deliverables Complete

**1. Present status table in chat:**

| Deliverable | Status | What was done | Opus verification |
|-------------|--------|---------------|-------------------|
| … | ✅ Done / ⚠️ Partial | … | Code review / Test run / Not verified |

Be brutally honest in the "Opus verification" column — code read ≠ verified, test ran in worktree without venv ≠ verified.

**Code Review happens on `dev` branch** (normal project path), NOT by reading worktree files. This means execution-focused shared-rules (code-standards, server-pattern, etc.) do NOT trigger during Opus review — they only trigger inside `.claude/worktrees/` paths where workers operate.

**2. Scope user verification (🛑 STOP)**

For each deliverable: propose a concrete verification step the **user** can perform as the final quality gate.
- What exactly to click, run, or check
- What the expected output or behavior is
- NOT how Opus would check it — how the user can confirm it themselves

Wait for remarks. When user has no remarks → run verification together.



