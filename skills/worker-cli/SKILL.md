---
name: worker-cli
description: See ~/.claude/shared-rules/global/cli-skills.md
---

# Worker CLI Skill

All worker lifecycle operations via `~/.local/bin/worker-cli` wrapper.
`worker_spawn` and `worker_send` remain as MCP tools (execution-critical).

## Commands

| Operation | CLI |
|---|---|
| List active workers | `worker-cli list <project_path>` |
| Check worker status | `worker-cli status <name> <project_path>` |
| Capture pane to file | `worker-cli capture <name> <project_path>` |
| Read last N lines | `tail -n <N> <output_file_from_capture>` |
| Merge worker branch | `worker-cli merge <name> <project_path>` |
| Kill worker | `worker-cli kill <name> <project_path>` |

The wrapper internally sources `$PLUGIN/src/spawn/tmux_spawn.sh` and calls the bash functions. Override plugin location via `CLAUDE_PLUGIN_ROOT` env var.

## Examples

```bash
PROJECT=~/Documents/ai/Monitor_CC

# List workers
worker-cli list "$PROJECT"

# Check status before capturing
worker-cli status inject-fixes "$PROJECT"

# Capture + read last 50 lines
worker-cli capture inject-fixes "$PROJECT"
# → prints path like /tmp/worker_capture_inject-fixes_123456.txt
tail -n 50 /tmp/worker_capture_inject-fixes_123456.txt

# Merge after verification
worker-cli merge inject-fixes "$PROJECT"

# Kill (tmux + worktree + branch in one shot)
worker-cli kill inject-fixes "$PROJECT"
```

## Rules

**NEVER kill without checking status first.** If status is `working` → do NOT kill.

Session name pattern used internally: `worker-<basename(project_path)>-<name>`.
Example: project `/Users/x/Monitor_CC` + worker `inject-fixes` →
session `worker-Monitor_CC-inject-fixes`.

## Fallback (wrapper unavailable)

If `~/.local/bin/worker-cli` is missing or out of date:

```bash
PLUGIN=~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0
SPAWN="$PLUGIN/src/spawn/tmux_spawn.sh"
bash -c "source \"$SPAWN\" && worker_status \"<name>\" \"<project_path>\""
```
