# Spawn Worker — Claude Session in Worktree via tmux

Spawn an interactive Claude session in a git worktree, accessible via tmux.

Input: $ARGUMENTS
Format: `<worker-name>` or `<worker-name> <brief-description>`
Example: `/spawn-worker auth-module` or `/spawn-worker auth-module JWT auth in src/auth/`

---

## Flow: Scope → Verify → Prompt → Spawn

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

### Step 3: Pre-Flight Check (MANDATORY for worktree mode)

**BEFORE creating the worktree**, verify that ALL target files are tracked by git:

```bash
git check-ignore <file-or-dir-1> <file-or-dir-2> ...
```

- If ANY target file/directory is gitignored → **STOP and warn the user**
- Gitignored files do NOT exist in worktrees — the worker will find nothing and fall back to editing main
- Options: (a) un-ignore the files first, (b) skip worktree and work in project directory directly

**Why this is critical:** Worktrees are created from the git index. Anything in `.gitignore` is invisible to the worker. Without this check, the worker silently edits main instead of the worktree — destroying isolation.

### Step 4: Build the Prompt

Write the prompt as a Markdown file at `/tmp/spawn-worker-<worker-name>.md`. This avoids shell escaping issues and makes the prompt reviewable.

Present it to the user:

"Prompt geschrieben nach `/tmp/spawn-worker-<worker-name>.md`:"

```
<the prompt content>
```

"Passt das, oder soll ich etwas aendern?"

The prompt MUST include:
- The specific task with concrete deliverables
- Which files/directories to work in
- Reference to plan file if one exists: "Read .claude/plans/*.md for full context"
- **Worktree isolation instruction** (if applicable):

```
CRITICAL: You are working in a git worktree at <worktree-path>.
- Your working directory is <worktree-path>, NOT the main repo.
- ALL file reads and edits MUST use paths relative to your working directory.
- NEVER use absolute paths to the main repo.
- Verify with `pwd` if unsure.
- Commit your changes to this branch when done.
```

Wait for user approval before proceeding.

### Step 5: Create Worktree (if applicable)

```bash
git worktree add -b <worker-name> .claude/worktrees/<worker-name>
```

If the branch already exists, STOP and inform the user.

### Step 6: Spawn

Resolve PLUGIN_DIR from this command's path (go up one level from commands/).

```bash
source $PLUGIN_DIR/src/spawn/tmux_spawn.sh
spawn_claude_worker_from_file "workers" "<worker-name>" "<project-or-worktree-path>" "sonnet" "/tmp/spawn-worker-<worker-name>.md"
```

### Step 7: Confirm

Report to user:
- Worker name and branch
- Worktree path (if applicable)
- Prompt file: `/tmp/spawn-worker-<worker-name>.md`
- tmux attach command: `tmux attach -t workers`
- List all current workers: `tmux list-windows -t workers`

### Step 8: Cleanup Instructions

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
