# Eval Agent Skill

Evaluate subagent sessions: analyze tool usage, propose automation file improvements.

Input: $ARGUMENTS
Format: `<project_path>` or `<project_path> <count>` or `<project_path> session`

PLUGIN_DIR: the iterative-dev plugin root (resolve via `~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0`)

---

## CRITICAL RULES

### Stop on Error (NON-NEGOTIABLE)

If ANY step fails (JSONL conversion, extract_calls, file read):
- **STOP IMMEDIATELY**
- Report the exact error message
- Do **NOT** proceed with workarounds
- Do **NOT** skip the failed agent and continue with the next
- Do **NOT** invent alternative approaches

### Agent Loop (NON-NEGOTIABLE)

When multiple agents are selected for evaluation:
- Process ALL selected agents, not just the first one
- For EACH agent: execute Phases 2-5 completely before starting the next
- After finishing one agent, explicitly state: "Agent N/M done. Starting next agent."

---

## Phase 1: Find Subagent

### 1.1 Session JSONL Location

Session JSONLs are written **dynamically** during the session (not only at session end). The active session's JSONL is always available.

CC projects directory: `~/.claude/projects/<escaped-project-path>/`
- `<escaped-project-path>` = absolute project path with `/` replaced by `-` (leading `/` becomes `-`)
- Example: `/Users/foo/MyProject` → `-Users-foo-MyProject`

**Find the newest session (= the active one):**
```bash
ls -t ~/.claude/projects/<escaped-project-path>/*.jsonl | head -1
```

**Find subagents of that session:**
```bash
SESSION_DIR=$(ls -td ~/.claude/projects/<escaped-project-path>/*/ | head -1)
ls $SESSION_DIR/subagents/
```

### 1.2 List Agents

1. Run list_agents.py to get all subagents with their types:
   ```bash
   cd $PLUGIN_DIR && python3 -m src.pipeline.list_agents --project <project_path>
   # Latest session only:
   cd $PLUGIN_DIR && python3 -m src.pipeline.list_agents --project <project_path> --session latest
   ```
   This outputs: agent_id, agent_type, timestamp, size (sorted newest first).

   **If list_agents.py fails** (e.g., "Main session not found"): The script derives the main session JSONL from the subagent path. If the JSONL doesn't exist yet or the session directory is stale, use the manual approach from 1.1 to identify the correct session, then pass specific subagent paths directly to Phase 2.

2. Present the table to user
3. If `session` was given: use `--session latest` flag, take all agents from most recent session
4. If `<count>` was given: take the N most recent from today's date, no user selection needed
5. If user says "the newest" or similar: take the single most recent from today's date
6. Otherwise: ask user which subagent(s) to evaluate
7. For the selected agent(s), get the JSONL path:
   `~/.claude/projects/<escaped-project-path>/*/subagents/agent-<agent_id>.jsonl`

---

## Phase 2: Convert & Extract

For each selected subagent:

### 2.1 Convert JSONL to Summary

```bash
cd $PLUGIN_DIR && python3 -m src.pipeline.jsonl_to_md \
    --input "<jsonl_path>" --output "/tmp/eval-<agent_id>.md" --dispatch
```

This produces ONE file:
- `/tmp/eval-<agent_id>_summary.md` — dispatch context + task prompt + tool call summary + final response

### 2.2 Read Summary

Use the **Read tool** to read the summary file:

```
Read /tmp/eval-<agent_id>_summary.md
```

This gives the complete overview:
- Dispatch Context (pre-dispatch messages, dispatch prompt, post-dispatch)
- Task Prompt
- Tool Call Summary — each line shows: `[HH:MM:SS] #N tool_name: key=value, key=value  [size chars]` or `[no output]`
- Final Response

### 2.3 Extract Specific Tool Calls

Based on the summary, identify interesting calls and extract them:

```bash
cd $PLUGIN_DIR && python3 -m src.pipeline.extract_calls \
    --input "<jsonl_path>" --calls "1,3,7,12"
```

Or save to file:
```bash
cd $PLUGIN_DIR && python3 -m src.pipeline.extract_calls \
    --input "<jsonl_path>" --calls "1,3,7,12" --output "/tmp/eval-<agent_id>_calls.md"
```

**Which calls to extract:**
- All calls with large outputs (>1000 chars) — contain the real findings
- All calls with small outputs (<400 chars) — verify if empty/error/short result
- Calls where the agent changed strategy — read what triggered the change
- The last 3 calls before the final response — understand what led to the conclusion

---

## Phase 3: Evaluate

Present findings to user in chat.

### What Went Well
For each positive:
- **What:** Concrete observation
- **Why it matters:** What this prevented or enabled

### What Went Wrong
For each problem:
- **What:** Concrete observation
- **Why:** Root cause — trace to the automation file rule that was violated or missing
- **Evidence:** Exact quote from agent output or tool call

**Inconsistency check (MANDATORY):**
When an agent uses a parameter correctly in SOME calls but not others:
- Flag this as STRONGER evidence than complete absence — it proves the agent KNOWS the parameter but applies it inconsistently
- Include both the correct and incorrect usage as evidence in the proposal

**Dispatch errors ARE automation file problems (MANDATORY):**
Every dispatch problem traces to a Skill section that controls prompt construction. NEVER dismiss dispatch errors as "one-off" or "not fixable via automation files."

### Dispatch Quality
- Was the task prompt precise enough?
- Did the sub receive all necessary context?
- Did the main agent meaningfully use the sub's response?
- Did dispatch quality cause any of the sub's failures?

**Dispatch problems MUST produce proposals (NON-NEGOTIABLE):**
When you identify a dispatch problem:
- ALWAYS propose a concrete fix for the dispatcher's Skill
- Example: "Don't mix content-understanding questions with locate-only output format in the same dispatch"

### Model-Specific Patterns
Based on the model used:
- **Haiku:** Format drift, scope creep, path hallucinations, stop criteria ignored
- **Sonnet/Opus:** Over-engineering, unnecessary verbosity

### MCP Content Volume Check (MANDATORY for Haiku + MCP agents)

For Haiku agents fetching external content (LinkedIn, Reddit, GitHub): check whether the agent maximized content volume. Haiku should go **broad and heavy** — the goal is maximum raw input before any filtering.

**Check each search/fetch call:**
1. Did the agent use the maximum sensible count for each tool?
2. Did the agent use the tool's decision rules (e.g. count=50 for high-engagement posts)?
3. Are there tool calls with suspiciously small outputs (<500 chars) that aren't errors? → likely wrong parameters or stale watchlist entries
4. Did the agent skip optional fetch calls (reactions, second-page pagination) that would have added coverage?

**Report format:**
```
CONTENT VOLUME CHECK:
- search_posts: N calls × count=X → avg Yk chars per call [OK / BELOW MAX]
- get_post_comments: used count=X for posts with Y comments → [OK / TOO LOW]
- Skipped calls: [list any optional calls not made]
- Dead entries: [watchlist profiles/companies returning <100 chars]
```

**Proposals for volume problems:** Target the SKILL.md tool reference section (count decision rules) AND server.py defaults — NOT what the agent should filter.

### Server-Side Guardrails Check (MANDATORY for MCP agents)

When evaluating agents that call MCP tools, verify that server-side guardrails (floors, caps, score filters) are working correctly.

**For EACH MCP tool call in the session:**
1. Check the parameter values the agent sent (from tool call summary)
2. Verify floors are enforced: Did the server correct low values? (e.g., agent sent top_k=3 → server used 20)
3. Verify caps are enforced: Did the server cap high values? (e.g., agent sent limit=500 → server used 100)
4. Check score filter impact: How many results were returned vs how many the agent requested? If significantly fewer → score filter is working

**Known Guardrails to verify:**

| Plugin | Tool | Parameter | Floor | Cap |
|--------|------|-----------|-------|-----|
| GitHub | grep_repo | max_files | 20 | — |
| GitHub | search_repos | query words | — | 3 (truncated) |
| Reddit | search_*/get_* | limit | 5-25 | 100-500 |
| Reddit | get_post_comments | depth | 20 | 50 |
| RAG | search/search_hybrid/search_keyword | top_k | 20 | 50 |
| RAG | read_document | num_chunks | 10 | 20 |

**Red Flags:**
- Agent sends low values AND output shows few results → floor may not be working
- Agent sends reasonable values but output is empty → score filter too aggressive?
- Agent doesn't use a parameter at all → check if the default is sensible

**Report format:**
```
GUARDRAILS CHECK:
- Tool X: agent sent param=Y, expected floor Z → OK/ISSUE
- Score filter: N results returned from M requested → OK/AGGRESSIVE/NOT FILTERING
```

---

## Phase 4: Read Automation Files & Propose

### 4.1 Identify Plugin

Match agent name to plugin:

| Agent | Plugin | Model |
|-------|--------|-------|
| github-search | github-research | Haiku |
| reddit-search | reddit | Haiku |
| code-investigate-specialist | iterative-dev | Haiku |
| web-research | searxng | Haiku |
| git-committer | iterative-dev | Haiku |

### 4.2 Locate Plugin Source

```bash
find ~/.claude/plugins/cache/brunowinter-plugins/ -name "plugin.json" | head -10
```

Read the plugin.json to find paths for agent definition + skills.

### 4.3 Read Automation Files

Read ALL relevant files using the Read tool:
- Agent definition (agents/<name>.md)
- Agent skill (skills/agent-<name>/SKILL.md)
- Domain skill (skills/<domain>/SKILL.md)

**Read Before Proposing (CRITICAL):** Proposals that contradict existing rules in the target file waste everyone's time.

**Plugin-Scope Rule:** Proposals target the plugin that OWNS the agent:
- Global agents (code-investigate-specialist, git-committer) -> iterative-dev plugin source
- Project-scoped agents (github-search, reddit-search, web-research) -> their respective plugin source repo

### 4.4 Concrete Proposals

For EACH identified problem, propose a change:

```
### Proposal N: [Title]

**File:** [Full path to automation file]
**Location:** [Section name]

**WHY:** [Root cause]

**Current:**
[Exact current text from the file]

**Proposed:**
[Exact replacement text]

**Expected Impact:** [Concrete improvement]
```

CRITICAL:
- Every proposal MUST have a WHY
- Current text MUST be the actual text from the file (quoted exactly)
- Proposals target automation files (Skills, Agent definitions, Commands), NOT application code
- **No contradictions:** Verify the proposal does not conflict with existing rules
- **Cost awareness:** Dispatcher = Opus, Sub = Haiku. Prefer better sub instructions over Opus pre-checks.
- **Simplicity rule:** For Haiku agents: maximum 2-3 fields per block format

### 4.5 Write to Plan File

Write all proposals to the plan file (`~/.claude/plans/<active-plan>.md`).

- Use the **Write tool** to write the full proposal set to the plan file
- Format: same Proposal N structure from 4.4 (File, Location, WHY, Current, Proposed, Expected Impact)
- Do NOT apply changes yet
- Do NOT present proposals in chat
- After writing: report "done" to user — they will review the plan file and approve

The plan file doubles as the implementation blueprint — proposals written there are ready for direct execution after user approval.

---

## Phase 5: Cleanup

After proposals are written/applied:

```bash
rm -f /tmp/eval-<agent_id>_summary.md /tmp/eval-<agent_id>_calls.md
```

**Then proceed to next agent if more are queued.**
