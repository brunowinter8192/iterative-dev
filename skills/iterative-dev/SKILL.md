---
name: iterative-dev
description: (project)
---

# Iterative Development Skill

### Session Start (MANDATORY)

`bead_list(status="open")` → read relevant work beads. No bead for current work → `bead_create(title, description)` before starting.

**Priority:** Read the most recently updated bead FIRST (`bead_show(id)` shows Created/Updated dates). The newest bead has the freshest context and is most likely the current session target.

**After reading bead comments, VERIFY:** Does the bead already answer the scope question you're about to ask? If the bead comments contain explicit next steps, decisions, or approaches — state them as fact, don't re-ask as an open question.

### Session End

ONE `bead_comment(id, text)` with STAND block — what was done, what's open. That's the only bead comment per session. No mid-session commenting.

EVERY RESPONSE STARTS WITH A PHASE INDICATOR:
- `📋 PLAN` - Planning phase (Plan Mode active)
- `🔨 IMPLEMENT` - Implementation phase

---

## Planning Phase (PLAN)

### Scoping

Clarify with the user:

**1. SCOPE - What is the end goal?**
→ "What should the output be?"
→ File? Script? Documentation? Analysis?
→ **If Documentation:** "Who is the target reader?"
  - **Default assumption:** AI (you) is the primary reader
  - Optimize for: clarity, structure, completeness (AI needs full context)

**2. SOURCES - Which files/folders are relevant?**
→ "Which folders should I look at?"
→ "Is there a reference script?"
→ User knows the structure better than you

**3. CONNECTIONS - How do the sources relate?**
→ "How does X use data from Y?"
→ read DOCS.md

**4. REFERENCES - Is there an existing pattern to follow?**
→ "Is there an existing pattern in your other projects we should follow?"
→ Especially for testing, debug, infrastructure tasks
→ User's existing patterns beat generic best practices

**THEN:** Explore with direction (DOCS.md → relevant scripts → structures)

### Planning Flow

Sequential steps. STOP after each step, present findings to user. Proceed only when user confirms.

**1. Status Quo (STOP — present to user)**

Read relevant `decisions/` files + existing code. Present to user:
- Current state in 2-3 sentences (what is currently implemented?)
- Divergences between bead context and current decisions (things may have changed)
- If decisions/ is outdated or missing for this component → flag explicitly

**2. Evidence Base (STOP — present to user)**

Check `dev/` and existing codebase for prior work on this problem. Present findings:
- Existing dev scripts that address this problem area? (DOCS.md of relevant dev/ subdir first)
- Existing fixes/workarounds? (`fixes/`, `debug/`, `KNOWN_ISSUES`, `CHANGELOG`)
- Test suites that cover the affected code? Do they actually IMPORT the module being changed, or have their own copy?
- Agent/workflow instruction files if optimizing an automated workflow? (Read the instruction file BEFORE proposing changes)
- When debugging: read ACTUAL DATA first (dump, sample, log output), research external sources only AFTER the data doesn't self-explain

**3. Source Assessment (STOP — present to user)**

- Produce an honest assessment of the knowledge foundation in ONE pass
- **List components:** What technologies/libraries/algorithms does this task use?
- **CLAUDE.md Sources Table:** For EACH component, check — is there an indexed source?
- **Search indexed sources:** Does the source actually ANSWER the open questions, or just mention the topic?
- **Plugin sources:** GitHub repos, Reddit threads, or other plugin-accessible sources relevant?
- **Identify gaps:** For which components do we have NO source?
- **Declare:** Present as table: Component | Source | Coverage | Gap
- Only AFTER the assessment: decide whether to research (for gaps) or proceed (if covered)
- Do NOT claim "no sources needed" without having checked the Sources table

**4. Deliverables & KPIs (STOP — present to user)**

Define deliverables with measurable completion criteria:
- Each deliverable: WHAT is done, HOW to verify (test command, file exists, output matches)
- **Investigation-first deliverables:** When root cause is UNKNOWN, split the deliverable: Phase 1 = investigate (what is the actual behavior, how does the system work), Phase 2 = fix based on findings. NEVER prescribe a solution in the worker prompt when the cause is unverified.
- Plan file MUST include a Deliverables section with KPIs

Concrete failure (2026-03-23): "Token-Tracking Bug fixen" with prescribed "5h block ceiling" in worker prompt. Root cause was unknown — should have been "Investigate how JSONL files are organized per session, then fix." Result: wrong fix implemented, then corrected (3 commits instead of 1).

**5. Remarks**

Ask user explicitly for remarks before calling ExitPlanMode.

**After Plan Approval — IMPLEMENT Kickoff (MANDATORY):**
Before starting implementation, summarize in chat:
- Deliverables with exit criteria (what signals "done")
- All affected file categories (src/, decisions/, dev/, docs)
- Worker dispatch plan (which workers, which files each)
This is NOT optional. The user must see the execution plan before workers are spawned.
Concrete failure (2026-03-23): Deliverables and affected decisions/ files only in plan file, not in chat. User had to ask twice.

---

## Implementation Phase (IMPLEMENT)

### Autonomous Execution

After plan approval, work through deliverables systematically:
1. Read plan file → identify open deliverables
2. Implement next deliverable (or spawn workers)
3. Verify against KPI
4. Repeat until all complete

Workers and orchestration: see `~/.claude/rules/workers.md`

### Worker Wait Pattern (Background Timer)

After spawning workers, estimate how long they need and set a background timer:

```
Bash(command="sleep 120 && echo 'workers check'", run_in_background=true)
```

When the timer fires (task-notification), check worker status:
- `worker_status(name)` → `idle` = done, `working` = set another timer
- If all idle → `worker_capture(name, tail=30)` to review results, then merge

### Cross-Session Verification Pattern

When a change cannot be tested in the current session (e.g., plugin changes that need CC restart):
1. **Worker implements** the change (retains full context)
2. **Bead tracks** what's DONE and what's OPEN (verification pending)
3. **Next session:** test the change. If it fails → re-send the worker via `worker_send` with fix instructions. The worker has the full context from implementation — no re-exploration needed.
4. **Keep the worker's tmux session open** for re-send in next session. Worker kill only after verification passes + user approval. Document alive workers in Bead STAND block.

### Scope Extension During IMPLEMENT

When the user introduces a new scope during IMPLEMENT (e.g., "let's also build X"):
1. **Do NOT expand the current cycle** — finish what's planned first
2. **Dispatch a worker** for the new scope (worktree if code-only, project-dir if MCP needed)
3. **User works directly with the worker** on the new scope
4. **Opus stays on the original scope** and closes the cycle cleanly (verify, glue)
5. Worker results are merged in the NEXT cycle

### After Deliverables Complete

1. **Verify** — run KPIs from plan
2. **Glue work** — trivial wiring (imports, registration, small config edits)
