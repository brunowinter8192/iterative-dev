# src/spawn/

## Role

Worker spawning and orchestration: tmux sessions, git worktrees, Ghostty viewers, proxy injection, status detection. Touch when changing how workers are spawned, observed or revived. Do not touch for `worker-cli` subcommand behaviour; that lives in `src/worker_cli/`.

## Public Interface

Sourced by `~/.local/bin/worker-cli` (all subcommands):
- `tmux_spawn.sh` — bash library entry point for worker lifecycle ops; sources the `worker_*.sh` siblings

Invoked via `python3 -m src.spawn.spawn` by `worker-cli spawn`:
- `spawn.py` — worktree setup + tmux session launch (stdlib only)

## Flow

`worker-cli spawn <name> <prompt_file> <project_path> [model]` in → `spawn.py` resolves the model + sets up the git worktree → sources `tmux_spawn.sh` and launches the tmux session + Ghostty viewer → session name out.

## Modules

### tmux_spawn.sh (172 LOC)

**Purpose:** Entry point sourced by callers — sources the sibling libs, owns session naming, model resolution and `spawn_claude_worker`.
**Reads:** `~/.claude/shared-rules/model_selection.json`.
**Writes:** tmux sessions, runner scripts, `/tmp/worker-<name>.done` signal file.
**Called by:** `~/.local/bin/worker-cli` (via `source`); `spawn.py` (via subprocess for `spawn_claude_worker_from_file`); `dev/` suites.
**Calls out:** tmux, `~/.local/bin/claude-280`, jq.

---

### worker_status.sh (154 LOC)

**Purpose:** Working/idle/dead status detection plus `worker_list` and `worker_status`.
**Reads:** tmux pane state, session JSONL, `~/Library/Application Support/com.brunowinter.monitor-cc-menubar/hooks.json`.
**Writes:** stdout.
**Called by:** `tmux_spawn.sh` (sourced); `bin/worker-cli` via `bash -c source`.
**Calls out:** tmux, jq, pgrep.

---

### worker_io.sh (151 LOC)

**Purpose:** Pane capture, message delivery, viewer window and orchestrator-signal file updates.
**Reads:** tmux panes, `_capture_clean.py`.
**Writes:** `/tmp/worker-<name>-pane.txt`, orchestrator signals file, Ghostty windows.
**Called by:** `tmux_spawn.sh` (sourced); `bin/worker-cli` via `bash -c source`.
**Calls out:** tmux, osascript/Ghostty, python3.

---

### worker_log_sidecar.sh (62 LOC)

**Purpose:** Log-directory retention sweep and start/stop of the `worker_logger.sh` sidecar.
**Reads:** log directory, `/tmp/worker-logger-<name>.pid`.
**Writes:** deletes stale log files, `log_sweep.log`, starts the sidecar process.
**Called by:** `tmux_spawn.sh` (sourced); `bin/worker-cli` via `bash -c source`.
**Calls out:** `worker_logger.sh`.

---

### worker_proxy.sh (108 LOC)

**Purpose:** Per-worker mitmproxy setup shared by spawn and revive; publishes the `WORKER_PROXY_*` globals.
**Reads:** proxy marker `/tmp/.monitor_cc_proxy_<session_id>`.
**Writes:** live addon copies, mitmdump process, `WORKER_PROXY_*` globals.
**Called by:** `tmux_spawn.sh`, `worker_revive.sh`.
**Calls out:** mitmdump, lsof.

---

### worker_revive.sh (148 LOC)

**Purpose:** `worker_revive` — recreates a dead-pane worker session via `claude --resume`.
**Reads:** tmux session environment, session JSONL, worktree dir.
**Writes:** tmux session, runner script, death log, `_REVIVE_*` globals.
**Called by:** `bin/worker-cli revive` via `bash -c source`.
**Calls out:** tmux, `~/.local/bin/claude-280`.

---

### worker_logger.sh (169 LOC)

**Purpose:** Standalone sidecar sampling a worker pane and writing a forensic snapshot on death.
**Reads:** tmux pane state, process table, session JSONL.
**Writes:** `<name>_<ts>_<event>.log`, `_DEATH.txt` in the log dir, `/tmp/worker-logger-<name>.pid`.
**Called by:** `worker_log_sidecar.sh` (started detached on every spawn and revive).
**Calls out:** tmux, ps, pgrep.

---

### _capture_clean.py (150 LOC)

**Purpose:** Scope + clean worker pane output. Takes `<pane_file> <worker_name>`, prints the cleaned body to stdout.
**Reads:** raw tmux pane file (arg); searches backward for last `❯ <non-whitespace>` prompt anchor.
**Writes:** stdout only.
**Called by:** `worker_io.sh` (clean pane capture, via `python3`).
**Calls out:** nothing (stdlib only).

---

### spawn.py (126 LOC)

**Purpose:** Set up the git worktree and launch the worker session, resolving the model (CLI argument wins over the config file) before handing off.
**Reads:** prompt file, project dir (`.claude/settings.local.json`, `venv/`), `~/.claude/shared-rules/model_selection.json`.
**Writes:** git worktree at `.claude/worktrees/<name>`, copies `settings.local.json`, symlinks `venv/`, then hands the session launch to `tmux_spawn.sh` via bash subprocess.
**Called by:** `~/.local/bin/worker-cli spawn` (via `cd "$PLUGIN" && python3 -m src.spawn.spawn`).
**Calls out:** git (via subprocess), bash + tmux_spawn.sh (via subprocess).

## State

Worker model resolution has two layers that must not both run: `spawn.py` resolves once in Python for the `worker-cli spawn` path and hands `tmux_spawn.sh` an already-concrete model string; `tmux_spawn.sh` keeps its own model resolution as the fallback for direct callers of its spawn functions and for the revive path. See `process-docs/worker_spawn/` for the full model-resolution and status-detection history.
