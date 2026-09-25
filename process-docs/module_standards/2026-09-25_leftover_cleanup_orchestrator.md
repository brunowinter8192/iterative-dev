# Leftover cleanup after the refactor sweep, orchestrator record (2026-09-25)

Orchestrator entry for the follow-up session that closed the open items of the 2026-09-24/25 refactor sweep. Worker entries: area `module_standards` (worker itdevspawn, model resolution and plugin-sync.sh), area `session_pipeline` (worker itdevpath, list_agents path encoding), area `skill_maintenance` (refactor skill Phase 2), and in reddit-cli area `discovery` (garbage filter numbers).

## Owner decisions taken in the chat

- Delete the shell `_resolve_worker_model`; the model argument of `spawn_claude_worker` and `spawn_claude_worker_from_file` is mandatory. Evidence given to the owner: no code caller omits the model except the dev/model_selector tests; `worker-cli spawn` always resolves in `spawn.py`; `worker_revive` reads the stored `WORKER_MODEL`.
- Delete `plugin-sync.sh`. Evidence: a scan of every session JSONL under `~/.claude/projects` (all tool_use Bash commands, 2026-09-25) found zero executions of the script, only reads, edits and mentions. The root `DOCS.md` documented only this script and was deleted with it (one DOCS.md per module directory; the root holds no module anymore).

## Done directly by the orchestrator

- `~/.local/bin/dev-sync` and `~/.local/bin/show` re-pointed from the removed `Meta/blank/bin/` to `Meta/iterative-dev/bin/`. Checked: `dev-sync` runs and refuses correctly when not on a dev branch; `show /nonexistent_xyz` prints `show: not found`. No other symlink in `~/.local/bin` points into `Meta/blank`.

## Traps seen in this session

- `worker-cli merge <name> <monitor-cc path>` for a worker that was spawned in monitor-cc but committed in a worktree of iterative-dev or reddit-cli is a no-op ("carried no commits"). The project_path must be the repo that holds the branch, e.g. `worker-cli merge itdevspawn ~/Documents/ai/Meta/iterative-dev`.
- A hook blocks `cd <worktree>` from the orchestrator; run worktree scripts by absolute path or use `git -C`.
- zsh expands a bare `=====` argument to `echo` as a command lookup and aborts the chain; use quoted separators.

## Verification state on 2026-09-25

- `src/spawn/*.sh` is loaded from the plugin cache. The model-argument change is live only after `plugin-publish`; the production check (a real spawn with and without explicit model) is due after the publish.
- `list_agents` could not be verified against real data: no directory under `~/.claude/projects` contains `*/subagents/agent-*.jsonl` on 2026-09-25. The hermetic test in dev/session_pipeline is the only evidence.
