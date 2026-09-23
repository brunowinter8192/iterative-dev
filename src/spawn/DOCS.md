# src/spawn/

## Role

Worker spawning and orchestration — tmux sessions, git worktrees, Ghostty viewers, proxy injection. Touch this package when changing how workers are spawned, how worktrees are set up, or how the proxy is injected into worker environments.

## Public Interface

Sourced by `~/.local/bin/worker-cli` (all subcommands):
- `tmux_spawn.sh` — bash library for worker lifecycle ops

Invoked via `python3 -m src.spawn.spawn` by `worker-cli spawn`:
- `spawn.py` — worktree setup + tmux session launch (stdlib only)

## Flow

`worker-cli spawn <name> <prompt_file> <project_path> [model]` in → `spawn.py` resolves the model + sets up the git worktree → sources `tmux_spawn.sh` and launches the tmux session + Ghostty viewer → session name out.

## Modules

### tmux_spawn.sh (912 LOC)

**Purpose:** Bash library — worker lifecycle: spawn, list, status, capture, send. Resolves the worker model, injects the Monitor_CC proxy, detects working/idle/dead status.
**Reads:** tmux session list, proxy marker `/tmp/.monitor_cc_proxy_<session_id>`, project path, `~/Library/Application Support/com.brunowinter.monitor-cc-menubar/hooks.json`, `~/.claude/shared-rules/model_selection.json`.
**Writes:** tmux sessions, Ghostty windows, worker mitmproxy processes, `/tmp/worker-<name>.done` signal file.
**Called by:** `~/.local/bin/worker-cli` (all subcommands via `source`); `spawn.py` (via subprocess for `spawn_claude_worker_from_file`).
**Calls out:** tmux, osascript/Ghostty, mitmdump, `~/.local/bin/claude-280`, `jq`.

---

### _capture_clean.py (150 LOC)

**Purpose:** Scope + clean worker pane output. Takes `<pane_file> <worker_name>`, prints the cleaned body to stdout.
**Reads:** raw tmux pane file (arg); searches backward for last `❯ <non-whitespace>` prompt anchor.
**Writes:** stdout only.
**Called by:** `worker_capture_clean()` in `tmux_spawn.sh` (via `python3 _capture_clean.py`).
**Calls out:** nothing (stdlib only).

---

### spawn.py (126 LOC)

**Purpose:** Worktree setup + worker session launch. Resolves the worker model (CLI arg wins over `~/.claude/shared-rules/model_selection.json`) before handing off to `tmux_spawn.sh`.
**Reads:** prompt file, project dir (`.claude/settings.local.json`, `venv/`), `~/.claude/shared-rules/model_selection.json`.
**Writes:** git worktree at `.claude/worktrees/<name>`, copies `settings.local.json`, symlinks `venv/`, then calls `spawn_claude_worker_from_file` via bash subprocess.
**Called by:** `~/.local/bin/worker-cli spawn` (via `cd "$PLUGIN" && python3 -m src.spawn.spawn`).
**Calls out:** git (via subprocess), bash + tmux_spawn.sh (via subprocess).

## State

Worker model resolution has two layers that must not both run: `spawn.py` resolves once in Python for the `worker-cli spawn` path and hands `tmux_spawn.sh` an already-concrete model string; `tmux_spawn.sh`'s own `_resolve_worker_model()` is the fallback for direct callers of `spawn_claude_worker`/`spawn_claude_worker_from_file` and for `worker_revive`. See `process-docs/worker_spawn/` for the full model-resolution and status-detection history.
