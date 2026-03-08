# Spawn Worker — Claude Session in Worktree via tmux

Spawn an interactive Claude session in a git worktree, accessible via tmux.

Input: $ARGUMENTS
Format: `<worker-name>` or `<worker-name> <brief-description>`
Example: `/spawn-worker auth-module` or `/spawn-worker auth-module JWT auth in src/auth/`

---

## Flow: Scope → Prompt → Spawn

This command ALWAYS follows this sequence. No shortcuts.

### Step 1: Parse Arguments

Extract worker name (first word) from $ARGUMENTS. The rest (if any) is an initial hint, NOT the final prompt.

If no arguments provided, ask for a worker name.

### Step 2: Scope the Task

Have a conversation with the user to clarify:

1. **What** should the worker do? (concrete deliverable)
2. **Where** in the codebase? (files, directories)
3. **Constraints?** (don't touch X, follow pattern Y, use library Z)
4. **Gitignored files needed?** (.env, .mcp.json, .venv, etc.)
   - If YES: skip worktree, use project directory directly
   - If NO: proceed with worktree isolation

Keep it focused — 2-3 exchanges max to nail down the scope.

### Step 3: Build the Prompt

Write a clear, complete prompt based on the scoping conversation. Present it to the user:

"Das wird der Prompt für den Worker:"

```
<the prompt>
```

"Passt das, oder soll ich etwas ändern?"

The prompt MUST include:
- The specific task with concrete deliverables
- Which files/directories to work in
- Reference to plan file if one exists: "Read .claude/plans/*.md for full context"
- Worktree instruction (if applicable): "You are working in a git worktree. Commit your changes to this branch when done."

Wait for user approval before proceeding.

### Step 4: Create Worktree (if applicable)

```bash
git worktree add -b <worker-name> .claude/worktrees/<worker-name>
```

If the branch already exists, STOP and inform the user.

### Step 5: Write Prompt & Spawn

Write the approved prompt to a temp file, then spawn:

```bash
cat > /tmp/spawn-worker-prompt.txt << 'PROMPT_EOF'
<approved prompt here>
PROMPT_EOF
```

Resolve PLUGIN_DIR from this command's path (go up one level from commands/).

```bash
source $PLUGIN_DIR/src/spawn/tmux_spawn.sh
spawn_claude_worker_from_file "workers" "<worker-name>" "<project-or-worktree-path>" "sonnet" "/tmp/spawn-worker-prompt.txt"
```

### Step 6: Confirm

Report to user:
- Worker name and branch
- Worktree path (if applicable)
- tmux attach command: `tmux attach -t workers`
- List all current workers: `tmux list-windows -t workers`

### Step 7: Cleanup Instructions

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
