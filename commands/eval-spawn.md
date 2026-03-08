Spawn a Sonnet worker that runs /eval for a project asynchronously.

Input: $ARGUMENTS
Format: `<project_path>` or `<project_path> session`
Example: `/eval-spawn ~/Documents/ai/MyProject session`

If $ARGUMENTS is empty, ask the user: "Fuer welches Projekt? (Pfad angeben)"

PLUGIN_DIR: the iterative-dev plugin root (resolve from this command's path: go up one level from commands/)

---

## Execute

```bash
source $PLUGIN_DIR/src/spawn/tmux_spawn.sh

TASK="Read $PLUGIN_DIR/commands/eval.md and execute it for project <project_path>. Use session mode if 'session' was given. Non-interactive: write reports to <project_path>/Evaluation_Proposals/ instead of presenting to user."

spawn_claude_worker "workers" "eval" "<project_path>" "sonnet" "$TASK"
```

Report: Worker spawned, tmux session, Ghostty window should open.
