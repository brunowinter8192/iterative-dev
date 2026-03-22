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

**Session start:** `bd list -s open` → read relevant work beads. No bead for current work → create one before starting.

**Session end:** ONE `bd comments add <bead-id>` with STAND block — what was done, what's open. That's the only bead comment per session. No mid-session commenting.

EVERY RESPONSE STARTS WITH A PHASE INDICATOR:
- `📋 PLAN` - Planning phase (Plan Mode active)
- `🔨 IMPLEMENT` - Implementation phase

---

## Planning Phase (PLAN)

### ExitPlanMode Timing (CRITICAL)

- ExitPlanMode = "Ich bin fertig mit dem gesamten Plan, User soll approven"
- NICHT nach jedem Teilschritt, NICHT nach jeder Analyse, NICHT nach jeder Frage
- When the user works iteratively (plugin by plugin, file by file): ExitPlanMode only when ALL parts are planned
- When unsure if done: Ask "Weiter mit X, oder sind wir durch?" — do NOT call ExitPlanMode
- Red Flag: User rejected ExitPlanMode → you called too early. Learn from it for the rest of the session.

### Beads Check (BEFORE Exploration)

**MANDATORY:** Run `bd list -s open` BEFORE launching any exploration agents.

Beads provide cross-session context. Agent exploration without bead context = wasted effort.

**Note:** Always use `-s open` by default. Show closed beads only when user explicitly asks.

**Priority:** Read the most recently updated bead FIRST (`bd show` shows Created/Updated dates). The newest bead has the freshest context and is most likely the current session target.

**After reading bead comments, VERIFY:** Does the bead already answer the scope question you're about to ask? If the bead comments contain explicit next steps, decisions, or approaches — state them as fact ("Laut Bead: FFS mit Korrelations-Ranking"), don't re-ask as an open question. Re-asking what's already documented = not reading carefully enough.

### Scoping (BEFORE Exploration)

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
→ Only when connections are clear: read DOCS.md

**4. REFERENCES - Is there an existing pattern to follow?**
→ "Is there an existing pattern in your other projects we should follow?"
→ Especially for testing, debug, infrastructure tasks
→ User's existing patterns beat generic best practices

**THEN:** Explore with direction (DOCS.md → relevant scripts → structures)

### Implementation Flow

When the scope is clear and the task involves implementing or fixing something in the repo:

**1. Status Quo (STOP — present to user)**

Read relevant `decisions/` files + existing code. Present to user:
- IST-Zustand in 2-3 Sätzen (what is currently implemented?)
- Divergences between bead context and current decisions (things may have changed)
- If decisions/ is outdated or missing for this component → flag explicitly
- **STOP:** Wait for user confirmation before proceeding

**2. Evidenzlage (STOP — present to user)**

Check `dev/` and existing codebase for prior work on this problem. Present findings:
- Existing dev scripts that address this problem area? (DOCS.md of relevant dev/ subdir first)
- Existing fixes/workarounds? (`fixes/`, `debug/`, `KNOWN_ISSUES`, `CHANGELOG`)
- Test suites that cover the affected code? Do they actually IMPORT the module being changed, or have their own copy?
- Agent/workflow instruction files if optimizing an automated workflow? (Read the instruction file BEFORE proposing changes)
- When debugging: read ACTUAL DATA first (dump, sample, log output), research external sources only AFTER the data doesn't self-explain
- "No code change needed" conclusion? → Verify: what happens at the boundary between existing and new data? What failure modes exist?
- **STOP:** Wait for user confirmation before proceeding

**3. Source Assessment**
- Produce an honest assessment of the knowledge foundation in ONE pass
- **List components:** What technologies/libraries/algorithms does this task use?
- **CLAUDE.md Sources Table:** For EACH component, check — is there an indexed source?
- **Search indexed sources:** Does the source actually ANSWER the open questions, or just mention the topic?
- **Plugin sources:** GitHub repos, Reddit threads, or other plugin-accessible sources relevant?
- **Identify gaps:** For which components do we have NO source?
- **Declare:** Present as table: Component | Source | Coverage | Gap
- Only AFTER the assessment: decide whether to research (for gaps) or proceed (if covered)
- Wait for user input on whether research is needed
- Do NOT claim "no sources needed" without having checked the Sources table
- **Eval tasks:** Source Assessment MUST complete BEFORE designing eval methodology.

**4. Worker Scoping**
- Each deliverable = potential worker task
- Identify which tasks are parallelizable (disjoint files) vs sequential (dependencies)
- For each worker task: specify input data, reference files, target files, constraints
- Glue work (server.py registration, config edits) stays with Opus
- Plan file MUST include a Workers section:
```
## Workers
- Worker A: <name> — <deliverable> — <target files>
- Worker B: <name> — <deliverable> — <target files>
- Glue: <what Opus does after merge>
```

**5. Remarks**
- Ask user explicitly for remarks before finalizing plan
- Map the complete plan: short form in chat, long form in plan file

**After Implementation:**
- If this cycle changed production code that affects a pipeline decision → update the relevant `decisions/` file (IST section)

---

## Implementation Phase (IMPLEMENT)

### Auto-Loop (Autonomous Execution)

After plan approval, Claude can start an autonomous loop that works through all deliverables without user intervention.

**When to use:** User approved the plan and wants hands-off execution.

**How to start:** Call `/iterative-dev:auto-loop <plan-file>` (or user calls it directly).

**How it works:**
1. Setup script creates state file `.claude/auto-loop.local.md`
2. Stop hook intercepts every session exit and re-injects the plan prompt
3. Claude works through deliverables one by one
4. When ALL deliverables are complete: output `<promise>ALL_DELIVERABLES_COMPLETE</promise>`
5. Stop hook detects promise → loop ends

**Safety:** Max iterations default 20. Override with `--max-iterations N`.

**Cancel:** `/iterative-dev:cancel-loop` or user removes `.claude/auto-loop.local.md`.

**Rules during auto-loop:**
- Work systematically through the plan file
- Verify each deliverable before moving to the next
- Do NOT output the promise until ALL deliverables are genuinely complete
- Do NOT lie to exit the loop — the promise must be TRUE

### Workers

Implementation happens through **workers** (see `~/.claude/rules/workers.md` for spawn/orchestrate/merge procedures).

### Opus Role

Opus orchestrates workers for substantial tasks and does small tasks directly:
- **Direct implementation** for single-point changes (one file, one function, one config value)
- **Spawn workers** for:
  - Substantial tasks (200+ lines, unclear pattern, new infrastructure)
  - **Bulk edits** (same change across multiple files — e.g., header renames, format migrations)
  - **Code-vs-docs verification** (comparing source code against documentation sections)
  - Any task that is repetitive and mechanical, even if individually trivial
- **Glue work** after workers are merged (trivial wiring: imports, tool registration, small config edits)
- **Verification** after merge (run tests, MCP tool calls)

**Principle:** Opus spends context on decisions and orchestration, not on repetitive edits. If you're about to make 3+ similar Edit calls, spawn a worker instead.

### Scope Extension During IMPLEMENT

When the user introduces a new scope during IMPLEMENT (e.g., "let's also build X"):
1. **Do NOT expand the current cycle** — finish what's planned first
2. **Dispatch a worker** for the new scope (worktree if code-only, project-dir if MCP needed)
3. **User works directly with the worker** on the new scope
4. **Opus stays on the original scope** and closes the cycle cleanly (verify, glue)
5. Worker results are merged in the NEXT cycle

**Why:** Scope creep within a cycle blurs boundaries. Workers isolate new scope without blocking the current cycle.

### After Workers Are Merged

1. **Verify** — run tests, MCP tool calls, check integration
2. **Glue work** — register tools, update imports, trivial wiring (1-3 lines)
3. **If issues found** — fix directly (small) or user spawns another worker (large)
4. Activate `/iterative-dev:recap` for cycle review
