---
name: iterative-dev
description: (project)
---

# Iterative Development Skill

### Opus Role

Opus sits BETWEEN user and workers. User says what they want, Opus understands it, Opus drives workers to execute it. All iteration loops (research, debugging, corrections) happen between Opus and workers — NOT between user and Opus. User is only involved for scope decisions and final verification/testing.

- **Opus↔User:** Scope brainstorm, intent clarification, verification
- **Opus↔Worker:** Investigation, implementation, iteration, bug fixes
- **Never:** User↔Worker directly

### Session Start (MANDATORY)

`bead_list(status="open")` → read relevant work beads.

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

**Step 2 — Investigation**

Spawn an **Investigation Worker** (or use `worker_send` to an idle worker with relevant context). The worker reads decisions/, code, AND dev/ — everything in one pass. Opus NEVER reads source files directly during PLAN.

**Worker prompt must cover:**
1. **Decisions Check** — Read relevant `decisions/` files. IST-Stand vs SOLL? OPEN items? Drift between docs and code?
2. **Code Check** — Read actual implementation files. Flag Reference Files (existing patterns for new code to follow).
3. **Dev Scripts Check** — Scan `dev/` for scripts affected by the change, scripts that inform the task (reproduction, validation), existing fixes/workarounds.
4. **Report back:** IST-Stand summary, affected files, Reference Files, relevant dev/ scripts, any anomalies.

**Opus reads worker findings** via `worker_capture(tail=40-60)` and presents status quo to user:
- Which files/components are affected
- Current state (IST) and why it matters
- Reference Files identified
- Relevant dev/ scripts

Concrete failure (2026-04-05): Opus dispatched 2 subagents for Steps 2+3 (code investigation + decisions/dev check). Workers then had to re-read all the same files. Subagent findings = throwaway context. Investigation Worker does one thorough pass and reports — reuse only if context budget allows (>30%).

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

If NO → continue investigating via `worker_send` to the Investigation Worker. Do NOT proceed to worker scoping without this milestone. Root cause may be unclear — that's OK. But Opus must understand enough to EVALUATE worker output.

Concrete failure (2026-04-05): Opus proceeded to worker scoping for hooks-redesign without understanding why `process_sessions_for_system_reminders()` wasn't showing results. Worker implemented noise-filter and persisted-file-loading (valid features, wrong problem). Opus couldn't recognize the misalignment because Opus had no mental model of the problem.

🛑 STOP — Ask for remarks.

### Phase 2 — Worker Scoping

**Step 1 — Worker Split**

- How to split workers across the task
- Which gaps (from Phase 1, Step 3) does each worker close first
- Investigation Worker from Step 2 can be reused via `worker_send` if its context overlaps

**Step 2 — Deliverables & KPIs**

Define deliverables with measurable completion criteria:
- Each deliverable: WHAT is done, HOW to verify (test command, file exists, output matches)
- **Investigation-first deliverables:** When root cause is UNKNOWN, split: Phase 1 = investigate, Phase 2 = fix based on findings. NEVER prescribe a solution when the cause is unverified.
- Plan file MUST include a Deliverables section with KPIs
- **Per worker: define what exactly, up to which point, and the approval gate**

**Present in chat for each deliverable:**
- What will be built/fixed
- How Opus verifies it (run tests, MCP call, check output) — code review does NOT count as verification
- How the user verifies it as final quality gate
- All affected file categories (src/, decisions/, dev/, docs)
- Worker dispatch plan (which workers, which files each, which Reference Files to follow)

🛑 STOP — Ask for remarks before calling ExitPlanMode.

---

## Implementation Phase (IMPLEMENT)

Workers, lifecycle, background timer, merging: see workers rules (opus-workers-1/2/3).

**Opus↔Worker Iteration (the core loop):**
All iteration happens between Opus and workers. Opus does NOT escalate to user for debugging, research, or implementation questions — Opus drives workers through these.

1. Worker reports findings or completion → Opus reads via `worker_capture`
2. Opus evaluates: Does this align with the actual problem? Is the approach correct?
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
2. Spawn worker if user has no remarks

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
