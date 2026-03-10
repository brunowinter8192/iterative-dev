Spawn a Sonnet worker that runs the eval pipeline for a project asynchronously.

Input: $ARGUMENTS
Format: `<project_path>` or `<project_path> session`
Example: `/eval-spawn ~/Documents/ai/MyProject session`

If $ARGUMENTS is empty, ask the user: "Fuer welches Projekt? (Pfad angeben)"

PLUGIN_DIR: the iterative-dev plugin root (resolve from this command's path: go up one level from commands/)

---

## Execute

```bash
source $PLUGIN_DIR/src/spawn/tmux_spawn.sh

TASK="Activate Skill('iterative-dev:eval-agent') with arguments: <project_path> session. Non-interactive: write reports to <project_path>/Evaluation_Proposals/ instead of presenting to user. Schreibe auf Deutsch.

CRITICAL: The project path is <project_path>. The CC projects directory for this project is: ~/.claude/projects/$(echo '<project_path>' | sed 's|^/|-|;s|/|-|g')/. Find the newest session JSONL by modification time (ls -t *.jsonl | head -1) — this is the active session whose subagents you must evaluate."

spawn_claude_worker "workers" "eval" "<project_path>" "sonnet" "$TASK"
```

Report: Worker spawned, tmux session, Ghostty window should open.
