Spawn a Sonnet worker that evaluates all subagents from a session asynchronously.

**Plan Mode Safe:** This command only reads files and spawns a tmux process. No project files are modified.

Input: $ARGUMENTS
Format: `<project_path>` or `<project_path> <count>` or `<project_path> session`
Example: `/eval-spawn ~/Documents/ai/MyProject session`

PLUGIN_DIR: the iterative-dev plugin root (resolve from this command's path: go up one level from commands/)
RAG_DIR: ~/Documents/ai/Meta/ClaudeCode/MCP/RAG

---

## Step 1: Find Agents

Run list_agents.py to get all subagents:

```bash
cd $PLUGIN_DIR && python3 -m src.pipeline.list_agents --project <project_path>
# or with --session latest if "session" was given
```

Parse the output table. Collect for each agent: agent_id, agent_type, JSONL path.

If `session` was given: use `--session latest` flag.
If `<count>` was given: take the N most recent from today's date.
Otherwise: take all agents.

---

## Step 2: Build Prompt

Read the eval command file from the plugin:

```bash
cat $PLUGIN_DIR/commands/eval.md
```

Write a combined prompt to `/tmp/eval-spawn-<timestamp>.txt` with this structure:

```
# NON-INTERACTIVE EVAL MODE

You are running autonomously — no user interaction. Execute all phases below without waiting for input.

## Pre-Resolved Agents

| agent_id | agent_type | jsonl_path |
|----------|-----------|------------|
<filled in from Step 1>

## Output Rules

- Phase 1 is ALREADY DONE — agents are listed above. Skip Phase 1 entirely.
- Phase 3.3: Do NOT present to user. Write all findings directly.
- Phase 5.3: Do NOT apply proposals. Write the COMPLETE report (Phases 3-5) to:
  `<project_path>/Evaluation_Proposals/<agent_id>.md` (one file per agent)
- Phase 6: Execute cleanup as written.

## Eval Instructions

<paste full eval.md content here>
```

---

## Step 3: Spawn tmux Window

```bash
# Create session if needed (idempotent)
tmux new-session -d -s workers 2>/dev/null || true

# Spawn Sonnet in the PROJECT directory (needs RAG MCP via plugin)
TASK_PROMPT="Read /tmp/eval-spawn-<timestamp>.txt and execute all instructions."
tmux new-window -t workers -n eval-<timestamp> \
  "cd <project_path> && claude --model sonnet --append-system-prompt \"$TASK_PROMPT\""
```

---

## Step 4: Confirm

Report to user:
- Worker name and tmux session
- Number of agents being evaluated
- tmux attach command: `tmux attach -t workers`
- Reminder: "Session bleibt offen fuer Review wenn Sonnet fertig ist."
