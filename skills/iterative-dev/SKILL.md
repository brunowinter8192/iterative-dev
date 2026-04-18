---
name: iterative-dev
description: (project)
---

# Iterative Development Skill

### Session Start (MANDATORY)

→ read beads.

---

**EVERY RESPONSE STARTS WITH A POSITION INDICATOR** — phase + current step:
- `📋 PLAN — Phase 1, Step 1: Session Scope`
- `📋 PLAN — Phase 1, Step 2: Investigation`
- `📋 PLAN — Phase 1, Step 3: Gap Analysis`
- `📋 PLAN — Phase 2, Step 1: Worker Split`
- `📋 PLAN — Phase 2, Step 2: Deliverables & KPIs`
- `🔨 IMPLEMENT — [current section]`

---

## Planning Phase (PLAN)

### Phase 1 — Understand

Sequential steps. After each step: present findings, wait for remarks, then proceed.

**Step 1 — Session Scope**

Repeat what the user wants in your own words.

🛑 STOP — Ask for remarks.

**Step 2 — Prep Investigation (Opus reads code DIRECTLY)**

This is Opus's OWN preparation investigation — NOT to be confused with the worker's later cross-model investigation in Phase 2 (workers-2). Two independent investigations are the whole point of the orchestration model:

- **Phase 1 prep (here):** Opus reads code directly to build an own mental model. Cannot be delegated — if Opus has no model, Opus cannot evaluate worker findings later.
- **Phase 2 cross-model (workers-2):** the dispatched worker reads files in the worktree independently, reports findings. Opus compares the two models. Convergence → Go; divergence → iterate.

Delegating the Phase 1 prep to an "Investigation Worker" collapses the two sides into one — you lose the independent second model, and with it the verification power.

**Opus reads:**
1. **Decisions Check** — Read relevant `decisions/` files. IST-Stand vs SOLL? OPEN items? Drift between docs and code?
2. **Code Check** — Read actual implementation files. Flag Reference Files (existing patterns for new code to follow).
3. **Dev Scripts Check** — Scan `dev/` for scripts affected by the change, scripts that inform the task (reproduction, validation), existing fixes/workarounds.

**Present status quo to user:**
- Which files/components are affected
- Current state (IST) and why it matters
- Reference Files identified
- Relevant dev/ scripts

Concrete failure (2026-04-05, Session 16): Investigation Worker reported "keine Datenquelle für monitor/shared Content". Opus accepted this without challenge. Reality: the Hook-Script reads the files directly and injects them. Opus had no mental model to recognize the contradiction — because Opus never read the code.

🛑 STOP — Ask for remarks.

**Step 3 — Gap Analysis + Mental Model Check**

Two parts:

**Part A — Gap Analysis:**
- Do we need more information? Which? Sources available: web, GitHub, Reddit, arxiv. Produce a sources table: Component | Source | Coverage | Gap
- Do we need more dev scripts?
- If research is needed → existing pattern in other projects to follow?
- Close all gaps BEFORE moving to Phase 2. Worker can do research via `worker_send` (GitHub subagent, web search).

**Gap Closing = ACTUALLY reading the sources (CRITICAL):**
- When gaps are identified: check `sources/sources.md` — is the needed info already indexed?
- If indexed: QUERY the source (RAG search, file read) and extract the answer NOW
- "We have it indexed" ≠ gap closed. Gap is closed when you KNOW the answer, not when you know WHERE the answer might be.

Concrete failure (2026-03-31): Identified 3 knowledge gaps. All sources were indexed in RAG. Said "alles im RAG verfuegbar, kein Research noetig" without querying RAG. User had to push 3 times.

**Part B — Mental Model Milestone (MANDATORY):**

Before proceeding to Phase 2, Opus must be able to answer:
1. What is the actual problem? (not just symptoms)
2. Which files/functions are involved and what do they do?
3. If a worker delivers "all done" — would I recognize whether the deliverables address the RIGHT problem?

If NO → continue reading code. Do NOT proceed to worker scoping without this milestone. Root cause may be unclear — that's OK. But Opus must understand enough to EVALUATE worker output.

Concrete failure (2026-04-05): Opus proceeded to worker scoping for hooks-redesign without understanding why `process_sessions_for_system_reminders()` wasn't showing results. Worker implemented noise-filter and persisted-file-loading (valid features, wrong problem). Opus couldn't recognize the misalignment because Opus had no mental model of the problem.

🛑 STOP — Ask for remarks.

### Phase 2 — First Worker Scope + Deliverables

**Scope ONE worker at a time.** Do NOT pre-plan a worker pipeline. The orchestration model is: dispatch one worker → evaluate findings (Cross-Model Comparison) → reuse via `worker_send` or — when dead/done — scope the NEXT worker. Upfront multi-worker planning violates AGGRESSIVE REUSE (workers-3) and commits to a split before Phase 2 findings justify it.

**Step 1 — First Worker Scope**

- Which gap (from Phase 1, Step 3) does this first worker close?
- Is there an alive worker with overlapping context already? → prefer `worker_send` over a new spawn (see workers-3 AGGRESSIVE REUSE). Otherwise → fresh `worker_spawn`.
- Abstract task, relevant files, Reference Files to follow.
- Subsequent workers get scoped LATER, after the current one completes or dies.

**Step 2 — Deliverables & KPIs**

Define task-level deliverables with measurable completion criteria — NOT per worker. A single worker may close one deliverable or several (via follow-up `worker_send`). Worker-to-deliverable mapping emerges as the task runs.

- Each deliverable: WHAT is done, HOW to verify (test command, file exists, output matches)
- Plan file MUST include a Deliverables section with KPIs

**Present in chat for each deliverable:**
- What will be built/fixed
- How Opus verifies it (run tests, MCP call, check output) — code review does NOT count as verification
- How the user verifies it as final quality gate
- All affected file categories (src/, decisions/, dev/, docs)
- The FIRST worker's task + whether it's a fresh spawn or a reuse via `worker_send`

🛑 STOP — Ask for remarks before proceeding to IMPLEMENT.

---

## Implementation Phase (IMPLEMENT)

Workers, lifecycle, background timer, merging: see workers rules (opus-workers-1/2/3).

**Opus↔Worker Iteration (the core loop):**
All iteration happens between Opus and workers. Opus does NOT escalate to user for debugging, research, or implementation questions — Opus drives workers through these. This loop IS Phase 2 Cross-Model Comparison in action (see workers-2).

1. Worker reports findings or completion → `worker_status` FIRST (confirm idle), THEN `worker_capture`
2. **Cross-Model Comparison:** Opus compares worker's findings against own mental model from Phase 1 prep. Convergence → Go; divergence → iterate.
3. If misaligned → `worker_send` with correction: "This addresses X but the problem is Y. Focus on Y."
4. If aligned but incomplete → `worker_send` with next step
5. If done → merge, proceed to verification
6. User involvement ONLY for: scope changes, live testing that requires human interaction (UI, restart)

### Dev-Branch Setup (MANDATORY at IMPLEMENT start)

Before spawning any workers:
1. `git checkout -b dev` (or `git checkout dev` if it exists)
2. All workers branch from `dev`, all merges land on `dev`
3. Opus reviews on `dev` — execution rules do NOT trigger (worktree-only paths)
4. At session end: use `dev_sync` MCP tool to sync dev→main

### Scope Extension During IMPLEMENT

When the user introduces a new scope during IMPLEMENT:

Mini-scoping (no full Phase 1 needed):
1. Summarize in chat: what is the user's task, what would a worker do
2. Check `worker_list` — is there an alive worker with context overlap? Default to `worker_send` on that worker (AGGRESSIVE REUSE, workers-3). Only spawn fresh if no candidate fits.
3. Dispatch if user has no remarks — investigate-report-stop pattern still applies (see Phase 1 Prompt Structure in workers-1).

### After Deliverables Complete

**1. Present status table in chat:**

| Deliverable | Status | What was done | Opus verification |
|-------------|--------|---------------|-------------------|
| ... | Done / Partial | ... | Code review / Test run / Not verified |

Be brutally honest in the "Opus verification" column — code read ≠ verified.

**Code Review happens on `dev` branch** (normal project path), NOT by reading worktree files.

**2. Scope user verification (STOP)**

For each deliverable: propose a concrete verification step the **user** can perform as the final quality gate.
- What exactly to click, run, or check
- What the expected output or behavior is

Wait for remarks. When user has no remarks → run verification together.
