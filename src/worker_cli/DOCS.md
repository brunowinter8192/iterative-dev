# src/worker_cli/

## Role

Subcommand implementations of `bin/worker-cli`, split out of the former single script. Touch this directory when changing what a `worker-cli` subcommand does; `bin/worker-cli` itself only dispatches.

## Public Interface

No `__init__.py`. The `.sh` files are sourced by `bin/worker-cli` (resolved through the script's real path, so the symlink in `~/.local/bin` works) and define one entry function per subcommand plus helpers.

## Flow

`worker-cli <cmd> args` in -> `bin/worker-cli` sources the libs and dispatches to `cmd_<cmd>` -> the command resolves project/worker, calls the `src/spawn/` libs through a fresh `bash -c` that sources `tmux_spawn.sh` -> stdout/exit code out.

## Modules

### registry.sh (123 LOC)

**Purpose:** Project/worker path resolution, registry and sidecar file helpers, status probe wrapper.
**Reads:** worker registry dir, tmux session list.
**Writes:** registry and sidecar files.
**Called by:** all other worker_cli libs.
**Calls out:** tmux, git, `src/spawn/tmux_spawn.sh` (via `bash -c source`).

---

### cmd_query.sh (144 LOC)

**Purpose:** Read-only subcommands: list, status, capture, response.
**Reads:** registry, session JSONL, tmux via spawn libs.
**Writes:** stdout.
**Called by:** bin/worker-cli.
**Calls out:** tmux, git, `src/spawn/tmux_spawn.sh` (via `bash -c source`).

---

### cmd_lifecycle.sh (188 LOC)

**Purpose:** State-changing subcommands: merge, kill, send, spawn, revive, worktree, worktree-rm, sweep-logs.
**Reads:** registry, sidecar files.
**Writes:** git branches/worktrees, tmux sessions, registry, stdout.
**Called by:** bin/worker-cli.
**Calls out:** tmux, git, `src/spawn/tmux_spawn.sh` (via `bash -c source`).

---

### wait.sh (171 LOC)

**Purpose:** wait subcommand: poll loop, transition gate, trace log, background-task probe.
**Reads:** tmux via spawn libs, session tasks dir (lsof).
**Writes:** wait_trace.log, stdout.
**Called by:** bin/worker-cli.
**Calls out:** tmux, git, `src/spawn/tmux_spawn.sh` (via `bash -c source`).

---

### janitor.sh (181 LOC)

**Purpose:** janitor subcommand: age-gated session sweep and orphan registry sweep.
**Reads:** tmux sessions, registry.
**Writes:** janitor.log, kills via `worker-cli kill`, stdout.
**Called by:** bin/worker-cli.
**Calls out:** tmux, git, `src/spawn/tmux_spawn.sh` (via `bash -c source`).

---

## State

Cross-function state is held in prefixed shell globals (one prefix per command) set by the parse/poll helpers and read by later steps of the same command. Nothing persists across invocations except the registry, sidecar and log files.
