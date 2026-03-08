You are evaluating a subagent session interactively with the user.

**FIRST:** Activate Skill('rag:RAG') for correct RAG MCP tool usage.

Input: $ARGUMENTS
Format: `<project_path>` or `<project_path> <count>` or `<project_path> session` (e.g., `~/Documents/ai/MyProject`, `~/Documents/ai/MyProject 3`, `~/Documents/ai/MyProject session`)

PLUGIN_DIR: the iterative-dev plugin root (resolve from this command's path: go up one level from commands/)
RAG_DIR: ~/Documents/ai/Meta/ClaudeCode/MCP/RAG

---

# Phase 1: Find Subagent

1. Run list_agents.py to get all subagents with their types:
   ```bash
   # All agents:
   cd $PLUGIN_DIR && python3 -m src.pipeline.list_agents --project <project_path>
   # Latest session only:
   cd $PLUGIN_DIR && python3 -m src.pipeline.list_agents --project <project_path> --session latest
   ```
   This outputs: agent_id, agent_type, timestamp, size (sorted newest first).
   The script resolves agent_type from the main session's Agent/Task tool_use block (handles both foreground and background agents).

2. Present the table to user
3. If `session` was given: use `--session latest` flag, take all agents from most recent session
4. If `<count>` was given: take the N most recent from today's date, no user selection needed
5. If user says "the newest" or similar: take the single most recent from today's date
6. Otherwise: ask user which subagent(s) to evaluate
6. For the selected agent(s), get the JSONL path from the script output or derive it:
   `~/.claude/projects/<escaped-project-path>/*/subagents/agent-<agent_id>.jsonl`

---

# Phase 2: JSONL to MD, Chunk, Index

For each selected subagent:

```bash
# Convert JSONL to MD with dispatch context (produces TWO files)
# <agent_id>.md = tool call details only (for RAG)
# <agent_id>_summary.md = dispatch context + task prompt + summary table + final response (for Read tool)
cd $PLUGIN_DIR && python3 -m src.pipeline.jsonl_to_md \
    --input "<jsonl_path>" --output "$RAG_DIR/data/documents/Subagents/<agent_id>.md" --dispatch

# Chunk (only the details file, NOT the summary)
$RAG_DIR/venv/bin/python $RAG_DIR/workflow.py chunk \
    --input "$RAG_DIR/data/documents/Subagents/<agent_id>.md" --chunk-size 1000 --overlap 200

# Index
$RAG_DIR/venv/bin/python $RAG_DIR/workflow.py index-json \
    --input "$RAG_DIR/data/documents/Subagents/<agent_id>.json"
```

---

# Phase 3: Read & Evaluate

## 3.1 Read Session Overview

Use the **Read tool** (NOT RAG) to read the summary file directly:

```
Read $RAG_DIR/data/documents/Subagents/<agent_id>_summary.md
```

This gives you the complete overview in one call:
- Dispatch Context (pre-dispatch messages, dispatch prompt, post-dispatch)
- Task Prompt
- Tool Call Summary Table (all calls with input and output sizes)
- Final Response

## 3.2 Systematic Tool Call Reading

The summary table shows output SIZES, not content. The actual tool call details are in RAG.

**Use RAG tools** (following the activated RAG Skill) to read tool call details:

```
mcp__plugin_rag_rag__read_document(collection="Subagents", document="<agent_id>.md", start_chunk=0, num_chunks=10)
```

**MANDATORY:** Read the actual tool call outputs for:
- All calls with large outputs (>1000 chars) — these contain the real findings
- All calls with small outputs (<400 chars) — verify if empty/error/short result
- Calls where the agent changed strategy — read what triggered the change
- The last 3 calls before the final response — understand what led to the conclusion

Continue reading chunks until you have covered ALL tool call sections.

## 3.3 Evaluate

Present findings to user interactively. For each section, discuss with user before moving on.

### What Went Well
For each positive:
- **What:** Concrete observation
- **Why it matters:** What this prevented or enabled

### What Went Wrong
For each problem:
- **What:** Concrete observation
- **Why:** Root cause — trace to the automation file rule that was violated or missing
- **Evidence:** Exact quote from agent output or tool call

**Dispatch errors ARE automation file problems (MANDATORY):**
Every dispatch problem traces to a Skill section that controls prompt construction. The dispatcher is controlled by Skills (iterative-dev SKILL.md for git-committer, github SKILL.md for github-search, etc.). NEVER dismiss dispatch errors as "one-off" or "not fixable via automation files." If the dispatch prompt contained wrong information → the Skill needs a rule to prevent it.

### Dispatch Quality
- Was the task prompt precise enough?
- Did the sub receive all necessary context?
- Did the main agent meaningfully use the sub's response?
- Did dispatch quality cause any of the sub's failures?

### Model-Specific Patterns
Based on the model used:
- **Haiku:** Format drift, scope creep, path hallucinations, stop criteria ignored
- **Sonnet/Opus:** Over-engineering, unnecessary verbosity

---

# Phase 4: Read Automation Files

## 4.1 Identify Plugin

Match agent name to plugin:

| Agent | Plugin |
|-------|--------|
| github-search | github-research |
| reddit-search | reddit |
| code-investigate-specialist | iterative-dev |
| web-research | searxng |

## 4.2 Locate Plugin Source

```bash
find ~/.claude/plugins/cache/brunowinter-plugins/ -name "plugin.json" | head -10
```

Read the plugin.json to find paths for agent definition + skills.

## 4.3 Read Automation Files

Read ALL relevant files using the Read tool:
- Agent definition (agents/<name>.md)
- Agent skill (skills/agent-<name>/SKILL.md)
- Domain skill (skills/<domain>/SKILL.md)

These are the targets for improvement proposals. You MUST read them BEFORE writing any proposals in Phase 5.

**Read Before Proposing (CRITICAL):** Proposals that contradict existing rules in the target file waste everyone's time. Reading the target file first prevents this. Do NOT formulate proposals during Phase 3 evaluation — wait until you have read the automation files here in Phase 4.

**Plugin-Scope Rule:** Proposals target the plugin that OWNS the agent:
- Global agents (code-investigate-specialist, git-committer) → iterative-dev plugin source
- Project-scoped agents (github-search, reddit-search, web-research) → their respective plugin source repo
- Edits go in the plugin SOURCE repo, not in the cache. See `~/.claude/CLAUDE.md` Plugin Cache Management.

---

# Phase 5: Proposals & Report

## 5.1 Root Cause Analysis

| Problem | Symptom | Root Cause | Automation File |
|---------|---------|------------|-----------------|
| ... | ... | ... | ... |

## 5.2 Concrete Proposals

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
- **No contradictions:** Verify the proposal does not conflict with existing rules in the same file or in `~/.claude/CLAUDE.md`
- **Cost awareness:** Before proposing "dispatcher should verify X before dispatch," consider model costs. Dispatcher = Opus, Sub = Haiku. An Opus verification call may cost MORE than the sub's error recovery. Prefer giving the sub better self-recovery instructions over adding Opus pre-checks.

## 5.3 Apply Proposals

Apply proposals directly to the automation files. No report file needed — the eval runs in the same session that implements the fixes.

---

# Phase 6: Cleanup

After proposals are applied:

```bash
# Delete from RAG
cd $RAG_DIR && ./venv/bin/python workflow.py delete --collection Subagents --document <agent_id>.md

# Remove temp files (details + summary + chunks JSON)
rm -f $RAG_DIR/data/documents/Subagents/<agent_id>.md
rm -f $RAG_DIR/data/documents/Subagents/<agent_id>_summary.md
rm -f $RAG_DIR/data/documents/Subagents/<agent_id>.json
```

Verify cleanup:
```
mcp__plugin_rag_rag__list_documents(collection="Subagents")
```
