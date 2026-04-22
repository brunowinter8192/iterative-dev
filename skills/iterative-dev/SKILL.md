---
name: iterative-dev
description: (project)
---

# Iterative Development Skill

### Session Start (MANDATORY)

→ read beads.
→ activate the `tool-use` skill (parallel to the proxy-injected rules — enforces call-hygiene for all Bash tool calls).

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
1. **DOCS.md Check (FIRST)** — Read the DOCS.md of the affected subdir(s) BEFORE any source code. DOCS.md is the map (Role, Flow, Modules with LOC + Called-by + Calls-out, State, Gotchas); source is the chapter. Start with `src/DOCS.md` for the big picture, then the subdir's DOCS.md. If DOCS.md is missing, stale, or doesn't match reality: FIX that first — stale DOCS wastes every future exploration. A worker can be dispatched for the DOCS update while Opus continues reading code.
2. **Decisions Check** — Read relevant `decisions/` files. IST-Stand vs SOLL? OPEN items? Drift between docs and code?
3. **Code Check** — Read actual implementation files. Flag Reference Files (existing patterns for new code to follow). Use DOCS.md's Called-by + Calls-out to pick the minimum set of files to read.
4. **Dev Scripts Check** — Scan `dev/` for scripts affected by the change, scripts that inform the task (reproduction, validation), existing fixes/workarounds.

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

Produce a sources table: Component | Source | Coverage | Gap

**Explicitly enumerate ALL resource categories** — not only our own code:

1. **Our own code** — `src/`, `decisions/`, `dev/`, existing logs in `src/logs/` or `data/`
2. **3rd-party library source** — e.g. tmux (`tty-keys.c`), mitmproxy addon hooks, any dependency whose behavior you'd otherwise guess at. GitHub repos readable via the `github-search` skill.
3. **Vendor / API docs** — Anthropic API reference, Claude Code internals, etc. Often indexed in `sources/sources.md`.
4. **Live data** — greppable proxy JSONL, session JSONL, existing reports. Structural evidence beats guessing at shape.
5. **Web / Reddit / arxiv** — last resort for behavioral questions not answered by source or docs.

For each resource: state WHICH question it answers. If no resource is listed for a question, the question is OPEN.

**Gap-closed means EVIDENCE, not plausible extrapolation.**

- Closed ✅ = "I have concrete evidence from resource X (file:line, grep count, doc quote, log entry) that answers question Y."
- NOT closed ❌ = "The existing code looks like it probably does Z, so the fix is probably W."
- Reading existing code is evidence about OUR code. It is NOT evidence about 3rd-party semantics (tmux button codes, mitmproxy hook order, Anthropic field shapes) — those need their own source.

Concrete failure (2026-04-18): Gap analysis for Monitor_CC warnings-pane fix initially claimed "Alle Infos für die Fixes liegen im Code". User pushed back: the scroll-direction bug depends on tmux SGR button 64/65 semantics (tmux source `tty-keys.c`), the tool-error false-positive fix depends on Anthropic `is_error` field shape (Anthropic API docs + proxy JSONL live grep), and mitmproxy event model would be relevant if proxy-level failures were in scope. Three 3rd-party resources glossed over by "im Code". After enumeration: tmux source + JSONL grep gave concrete evidence for both fixes (proxy log: 36 `is_error` occurrences confirmed the field shape). "Im Code" ≠ gap closed.

Concrete failure (2026-03-31): Identified 3 knowledge gaps. All sources were indexed in RAG. Said "alles im RAG verfuegbar, kein Research noetig" without querying RAG. User had to push 3 times. Rule: "indexed" ≠ "answered". Query the source, extract the answer, cite file:line or doc quote.

**Worker can close gaps during Phase A investigation:**
- Worker has github-search skill, web search, file reading in the worktree
- If a gap needs 3rd-party source reading, include it in the worker prompt's Phase A with a specific citation request ("cite tmux source file:line for button 64/65 semantics")
- Do NOT hand off a gap as "figure it out" — specify WHICH resource the worker should consult and WHAT answer to return

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

**Background Timer Discipline:** ONE timer at a time. Start a background timer → WAIT for it to fire → THEN check status → THEN decide whether to set another. NEVER stack multiple timers in rapid succession. If you set `sleep 120` and it hasn't fired yet, do independent work (DOCS, bead updates, rule edits) — do NOT set a second timer "just in case".

Concrete failure (2026-04-22): Started sleep 45, sleep 30, sleep 30 within seconds of each other without waiting for any to complete. Each timer wake-up triggered another status check + another timer, creating a polling loop that wasted context and confused the user.

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
