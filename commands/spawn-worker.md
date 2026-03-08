# Spawn Worker — Claude Session in Worktree via tmux

Spawn an interactive Claude session in a git worktree, accessible via tmux.
Uses the Maniple-inspired 2-phase spawn pattern: start Claude first, wait for ready, then send prompt.

Input: $ARGUMENTS
Format: `<worker-name> <task-description>`
Example: `/spawn-worker auth-module Implement JWT authentication in src/auth/`

---

## Step 1: Parse Arguments

Extract worker name (first word) and task description (rest) from $ARGUMENTS.
If no arguments provided, ask the user for worker name and task.

## Step 1.5: Gitignore Scope Check

**BEFORE creating the worktree**, check if the task requires gitignored files (`.env`, `.mcp.json`, `.venv/`, `node_modules/`, etc.).

Worktrees do NOT contain gitignored files — they are isolated copies of tracked files only.

Ask the user: "Braucht dieser Task Zugriff auf gitignored Files (.env, .mcp.json, .venv, etc.)?"

- **If YES:** STOP. Inform the user that worktree isolation is not suitable for this task. Suggest running the worker directly in the project directory instead (skip Step 2, use project path in Step 4).
- **If NO or unclear:** Proceed with worktree creation.

## Step 2: Create Worktree

```bash
git worktree add -b <worker-name> .claude/worktrees/<worker-name>
```

Verify the worktree was created. If the branch already exists, STOP and inform the user.

## Step 3: Write Task Prompt

Write the task description to a temp file to avoid shell escaping issues:

```bash
cat > /tmp/spawn-worker-prompt.txt << 'PROMPT_EOF'
<task-description goes here>

You are working in a git worktree. Commit your changes to this branch when done.
PROMPT_EOF
```

The task prompt MUST include:
- The specific task from the user's arguments
- Reference to the plan file if one exists: "Read .claude/plans/*.md for full context"
- Instruction: "You are working in a git worktree. Commit your changes to this branch when done."

## Step 4: Spawn via tmux_spawn.sh

Resolve PLUGIN_DIR from this command's path (go up one level from commands/).

```bash
source $PLUGIN_DIR/src/spawn/tmux_spawn.sh
spawn_claude_worker_from_file "workers" "<worker-name>" "$(pwd)/.claude/worktrees/<worker-name>" "sonnet" "/tmp/spawn-worker-prompt.txt"
```

**Note:** Do NOT use `--append-system-prompt`. The spawn script sends the prompt as user input after Claude is ready.

## Step 5: Confirm

Report to user:
- Worker name and branch
- Worktree path
- tmux attach command: `tmux attach -t workers`
- List all current workers: `tmux list-windows -t workers`

## Step 6: Cleanup Instructions

When the user says a worker is done and wants to merge:

```bash
# Review what the worker committed
git log master..<worker-name> --oneline

# Merge into current branch
git merge <worker-name>

# Cleanup
tmux kill-window -t workers:<worker-name> 2>/dev/null
git worktree remove .claude/worktrees/<worker-name>
git branch -d <worker-name>
```
