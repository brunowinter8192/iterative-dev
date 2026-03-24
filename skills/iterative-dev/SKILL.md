---
name: iterative-dev
description: (project)
---

# Iterative Development Skill

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

**Step 1 — Session Scope 🛑 STOP**

Repeat what the user wants in your own words. Wait for remarks before proceeding.

**Step 2 — Status Quo 🛑 STOP**

1. **Decisions Check** — Read the relevant `decisions/` file(s) for this topic area.
   - What is the current documented IST-Stand? What is SOLL?
   - What items are marked OPEN?
   - If `decisions/` is outdated or missing for this component → flag explicitly
2. **Code Check** — Read the actual implementation files referenced in the decisions.
   - Does the code match the documented state?
   - Any drift between `decisions/` and what's in source? → flag explicitly
3. **Present status quo to user.**

Wait for remarks before proceeding.

**Step 3 — Dev Scripts Check 🛑 STOP**

Read `dev/` DOCS.md → identify scripts that address this topic area. Present findings:
- Existing dev scripts relevant to this problem?
- Existing fixes/workarounds? (`fixes/`, `debug/`, `KNOWN_ISSUES`, `CHANGELOG`)
- Test suites that cover the affected code? Do they IMPORT the module being changed, or have their own copy?
- Agent/workflow instruction files if optimizing an automated workflow? (Read the instruction file BEFORE proposing changes)
- When debugging: read ACTUAL DATA first (dump, sample, log output); research external sources only AFTER the data doesn't self-explain

Wait for remarks before proceeding.

**Step 4 — Gap Analysis 🛑 STOP**

- Do we need more information? Which? (produce a sources table if relevant: Component | Source | Coverage | Gap)
- Do we need more dev scripts? Which?
- If research is needed → existing pattern in other projects to follow? User's existing patterns beat generic best practices.
- Close all gaps BEFORE moving to Phase 2.

Wait for remarks before proceeding.

### Phase 2 — Worker Scoping

**Step 1 — Worker Split**

- How to split workers across the task
- Which gaps (from Phase 1, Step 4) does each worker close first

**Step 2 — Deliverables & KPIs 🛑 STOP**

Define deliverables with measurable completion criteria:
- Each deliverable: WHAT is done, HOW to verify (test command, file exists, output matches)
- **Investigation-first deliverables:** When root cause is UNKNOWN, split the deliverable: Phase 1 = investigate (what is the actual behavior, how does the system work), Phase 2 = fix based on findings. NEVER prescribe a solution in the worker prompt when the cause is unverified.
- Plan file MUST include a Deliverables section with KPIs
- **Per worker: define what exactly, up to which point, and the approval gate** — especially when research is involved: worker stops at a defined checkpoint, user gives approval before the next step begins

Concrete failure (2026-03-23): "Token-Tracking Bug fixen" with prescribed "5h block ceiling" in worker prompt. Root cause was unknown — should have been "Investigate how JSONL files are organized per session, then fix." Result: wrong fix implemented, then corrected (3 commits instead of 1).

Wait for remarks before calling ExitPlanMode.

**After Plan Approval — IMPLEMENT Kickoff (MANDATORY):**
Before starting implementation, summarize in chat:
- Deliverables with exit criteria (what signals "done")
- All affected file categories (src/, decisions/, dev/, docs)
- Worker dispatch plan (which workers, which files each)
This is NOT optional. The user must see the execution plan before workers are spawned.
Concrete failure (2026-03-23): Deliverables and affected decisions/ files only in plan file, not in chat. User had to ask twice.

---

## Implementation Phase (IMPLEMENT)

Workers and orchestration: see `~/.claude/rules/workers.md`

### Worker Lifecycle

- **Keep workers alive** at all times — do NOT kill until user explicitly approves
- **When a worker finishes a step:** code review FIRST (read every changed file), then merge
- **After a deliverable is done:** do NOT re-prompt the worker — the deliverable is closed

### Worker Wait Pattern (Background Timer)

After spawning workers, estimate how long they need and set a background timer:

```
Bash(command="sleep 120 && echo 'workers check'", run_in_background=true)
```

When the timer fires (task-notification), check worker status:
- `worker_status(name)` → `idle` = done, `working` = set another timer
- If all idle → `worker_capture(name, tail=30)` to review results, then merge

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

**2. Scope user verification (🛑 STOP)**

For each deliverable: propose a concrete verification step the **user** can perform as the final quality gate.
- What exactly to click, run, or check
- What the expected output or behavior is
- NOT how Opus would check it — how the user can confirm it themselves

Wait for remarks. When user has no remarks → run verification together.

**3. Glue work** — trivial wiring (imports, registration, small config edits)


