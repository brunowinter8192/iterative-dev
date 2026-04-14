---
name: eval-cli
description: See ~/.claude/shared-rules/global/cli-skills.md
---

# Eval CLI Skill

Post-session subagent analysis via Python pipeline modules in the iterative-dev plugin.

## Prerequisites

```bash
PLUGIN=~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0
```

Run from `$PLUGIN` directory so relative imports in `src.pipeline.*` resolve correctly.

## Commands

| Operation | CLI |
|---|---|
| List subagents for latest session | `cd $PLUGIN && python3 -m src.pipeline.list_agents <project_path>` |
| List subagents for specific session | `cd $PLUGIN && python3 -m src.pipeline.list_agents <project_path> --session latest` |
| Convert JSONL → markdown summary | `cd $PLUGIN && python3 -m src.pipeline.jsonl_to_md <jsonl_path> /tmp/eval_out.md` |
| Extract specific tool call numbers | `cd $PLUGIN && python3 -m src.pipeline.extract_calls <jsonl_path> <call_num1,call_num2>` |

## Output

- `list_agents`: prints a table of subagent IDs + JSONL paths
- `jsonl_to_md`: writes markdown summary to output path (includes dispatch + tool call summary)
- `extract_calls`: prints the specific tool call blocks to stdout

## Workflow

1. `list_agents` → get JSONL path for the agent you want to inspect
2. `jsonl_to_md` → convert to markdown for overview
3. `extract_calls` → drill into specific tool calls if needed

## Examples

```bash
PLUGIN=~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0
PROJECT=~/Documents/ai/Monitor_CC

# Step 1: find subagent JSONL files from latest session
cd "$PLUGIN" && python3 -m src.pipeline.list_agents "$PROJECT"
# → table: agent_id | path
# → JSONL paths: agent-abc123: ~/.claude/projects/.../subagents/agent-abc123.jsonl

# Step 2: convert worker JSONL to readable markdown
cd "$PLUGIN" && python3 -m src.pipeline.jsonl_to_md \
  ~/.claude/projects/-Users-brunowinter2000-Documents-ai-Monitor_CC/subagents/agent-abc123.jsonl \
  /tmp/agent_abc123_summary.md

# Step 3: read the summary
cat /tmp/agent_abc123_summary.md

# Extract specific tool calls (e.g., calls 3 and 7)
cd "$PLUGIN" && python3 -m src.pipeline.extract_calls \
  ~/.claude/projects/.../subagents/agent-abc123.jsonl \
  3,7
```
