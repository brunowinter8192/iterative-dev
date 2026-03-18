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

EVERY RESPONSE STARTS WITH A PHASE INDICATOR:
- `📋 PLAN` - Planning phase (Plan Mode active)
- `🔨 IMPLEMENT` - Implementation phase

---

## Planning Phase (PLAN)

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

**1. Decisions**
- Read relevant `decisions/` files if the project has them
- Map divergences between bead context and current decisions (things may have changed since the bead was written)
- **decisions/ Update Rule:** If this cycle's implementation changes production code that affects a pipeline decision → the relevant `decisions/` file MUST be updated. Note which file needs updating.

**2. Dev Check**
- Does `dev/` already have modules/scripts that address this problem area?
- Read DOCS.md of the relevant `dev/` subdirectory FIRST, then only read module code if needed
- Existing dev scripts > building new ad-hoc test scripts
- For bugs: reproduce in dev/ with test DB first, THEN research causes
- For features: build a minimal prototype/test in dev/ first, THEN research best approaches
- Are new dev scripts needed? If yes: which directory, what pattern to follow?
- Research agents dispatched before reproduction = wasted effort on assumptions

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

---

## Implementation Phase (IMPLEMENT)

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
