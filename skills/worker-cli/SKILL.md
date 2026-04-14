---
name: worker-cli
description: See ~/.claude/shared-rules/global/cli-skills.md
---

# Worker CLI Skill

All worker lifecycle operations via `tmux_spawn.sh` bash functions and direct git commands.
`worker_spawn` and `worker_send` remain as MCP tools (execution-critical).

## Prerequisites

```bash
PLUGIN=~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0
SPAWN="$PLUGIN/src/spawn/tmux_spawn.sh"
```

Source `tmux_spawn.sh` in the same bash -c call — it does not persist across calls.

## Commands

| Operation | CLI |
|---|---|
| List active workers | `bash -c "source \"$SPAWN\" && worker_list \"<project_path>\""` |
| Check worker status | `bash -c "source \"$SPAWN\" && worker_status \"<name>\" \"<project_path>\""` |
| Capture pane to file | `bash -c "source \"$SPAWN\" && worker_capture \"<name>\" \"\" \"<project_path>\""` |
| Read last N lines | `tail -n <N> <output_file_from_capture>` |
| Merge worker branch | `git -C <project_path> log dev..<name> --oneline && git -C <project_path> merge <name>` |
| Kill worker | See multi-step below |

## Worker Kill (3 Steps in Order)

```bash
# Step 1 — kill tmux session
tmux kill-session -t "worker-$(basename <project_path>)-<name>" 2>/dev/null

# Step 2 — remove git worktree
git -C <project_path> worktree remove --force .claude/worktrees/<name>

# Step 3 — delete branch
git -C <project_path> branch -d <name>
```

Session name pattern: `worker-<basename(project_path)>-<name>`  
Example for project `/Users/x/Monitor_CC` and worker `inject-fixes`:  
session = `worker-Monitor_CC-inject-fixes`

**NEVER kill without checking status first.** If status is `working` → do NOT kill.

## Examples

```bash
PLUGIN=~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0
SPAWN="$PLUGIN/src/spawn/tmux_spawn.sh"
PROJECT=~/Documents/ai/Monitor_CC

# List workers
bash -c "source \"$SPAWN\" && worker_list \"$PROJECT\""

# Check if worker is idle before capturing
bash -c "source \"$SPAWN\" && worker_status \"inject-fixes\" \"$PROJECT\""

# Capture output and read last 50 lines
bash -c "source \"$SPAWN\" && worker_capture \"inject-fixes\" \"\" \"$PROJECT\""
# → prints path like /tmp/worker_capture_inject-fixes_123456.txt
tail -n 50 /tmp/worker_capture_inject-fixes_123456.txt

# Merge worker branch
git -C "$PROJECT" log dev..inject-fixes --oneline
git -C "$PROJECT" merge inject-fixes

# Kill worker after verification
tmux kill-session -t "worker-Monitor_CC-inject-fixes" 2>/dev/null
git -C "$PROJECT" worktree remove --force .claude/worktrees/inject-fixes
git -C "$PROJECT" branch -d inject-fixes
```
