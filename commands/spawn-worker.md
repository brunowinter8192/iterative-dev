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
- **Worker rules invocation** (ALWAYS, for worktree mode):

```
FIRST ACTION (before any file reads or edits):
Run: /worker-rules

This loads mandatory worktree isolation rules and report requirements.
Do NOT skip this step.
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
- tmux attach command: `tmux attach -t worker-<worker-name>`
- List all current workers: `tmux list-sessions | grep worker-`

### Step 8: Merging Worker Results

**CRITICAL: Always MERGE, never copy files from worktrees.**

When a worker is done (user confirms or you verify the worktree has commits):

```bash
# 1. Read worker report (handoff artifact)
cat .claude/worktrees/<worker-name>/WORKER_REPORT.md

# 2. Review commits
git log main..<worker-name> --oneline

# 3. Merge into current branch
git merge <worker-name>

# 4. Remove worker report (process artifact, not repo content)
git rm -f WORKER_REPORT.md && git commit -m "cleanup: remove worker report"

# 5. Cleanup worktree and branch
tmux kill-window -t workers:<worker-name> 2>/dev/null
git worktree remove .claude/worktrees/<worker-name>
git branch -d <worker-name>
```

**PROHIBITED:**
- `cp` from worktree to main repo — destroys git history, defeats worktree purpose
- Manually recreating files that the worker already committed
- Cherry-picking individual files instead of merging the branch

**Why merge:** The worker commits on its branch. `git merge` brings all changes cleanly with full history. Copy = lost authorship, lost diff, extra work.
