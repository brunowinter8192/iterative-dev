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
- These KPIs feed the auto-loop — loop ends when all KPIs are met or max 20 iterations
- Plan file MUST include a Deliverables section with KPIs

**5. Remarks**

Ask user explicitly for remarks before calling ExitPlanMode.

**After Implementation:**
- If this cycle changed production code that affects a pipeline decision → update the relevant `decisions/` file

---

## Implementation Phase (IMPLEMENT)

### Auto-Loop (MANDATORY)

After plan approval, ALWAYS call `/iterative-dev:auto-loop <plan-file>`.
Stop hook fires `continue` on idle — no prompt re-injection, just keeps Claude going.
Loop runs until:
- All deliverables complete → output `<promise>ALL_DELIVERABLES_COMPLETE</promise>`
- OR max iterations reached (default 20)

Workers and orchestration: see `~/.claude/rules/workers.md`

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
