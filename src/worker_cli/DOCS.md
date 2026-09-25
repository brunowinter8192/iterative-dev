# src/worker_cli/

## Role

Subcommand implementations of `bin/worker-cli`, split out of the former single script. Touch this directory when changing what a `worker-cli` subcommand does; `bin/worker-cli` itself only dispatches.

## Public Interface

No `__init__.py`. The `.sh` files are sourced by `bin/worker-cli` (resolved through the script's real path, so the symlink in `~/.local/bin` works) and define one entry function per subcommand plus helpers.

## Flow

`worker-cli <cmd> args` in -> `bin/worker-cli` sources the libs and dispatches to `cmd_<cmd>` -> the command checks its arguments against its exact form (surplus argument aborts with exit 2 and the correct form), resolves the worker from the registry, calls the `src/spawn/` libs through a fresh `bash -c` that sources `tmux_spawn.sh` -> stdout/exit code out.

## Modules

### args.sh (34 LOC)

**Purpose:** Argument tripwire shared by every subcommand: exact-arity check, abort with the correct form on a surplus or missing argument.
**Reads:** Nothing.
**Writes:** stderr, exit code 2.
**Called by:** all other worker_cli libs.
**Calls out:** none.

---

### registry.sh (62 LOC)

**Purpose:** Worker-to-project resolution from the registry only, registry and sidecar file helpers, status probe wrapper.
**Reads:** worker registry dir, tmux session list.
**Writes:** registry and sidecar files.
**Called by:** all other worker_cli libs.
**Calls out:** tmux, `src/spawn/tmux_spawn.sh` (via `bash -c` source).

---

### cmd_query.sh (113 LOC)

**Purpose:** Read-only subcommands: list, status, capture, response.
**Reads:** registry, session JSONL, tmux via spawn libs.
**Writes:** stdout.
**Called by:** bin/worker-cli.
**Calls out:** jq, `src/spawn/tmux_spawn.sh` (via `bash -c` source).

---

### cmd_lifecycle.sh (252 LOC)

**Purpose:** State-changing subcommands: merge (across every repo holding a branch of the worker), kill, send, spawn, revive, worktree, worktree-rm, sweep-logs.
**Reads:** registry, sidecar files.
**Writes:** git branches/worktrees, tmux sessions, registry, stdout.
**Called by:** bin/worker-cli.
**Calls out:** git, tmux, python3, `src/spawn/tmux_spawn.sh` (via `bash -c` source).

---

### wait.sh (179 LOC)

**Purpose:** wait subcommand: poll loop, transition gate, trace log, background-task probe.
**Reads:** tmux via spawn libs, session tasks dir (lsof).
**Writes:** wait_trace.log, stdout.
**Called by:** bin/worker-cli.
**Calls out:** tmux, lsof, `src/spawn/tmux_spawn.sh` (via `bash -c` source).

---

### janitor.sh (175 LOC)

**Purpose:** janitor subcommand: age-gated session sweep and orphan registry sweep.
**Reads:** tmux sessions, registry.
**Writes:** janitor.log, kills via `worker-cli kill`, stdout.
**Called by:** bin/worker-cli.
**Calls out:** tmux, git, `src/spawn/tmux_spawn.sh` (via `bash -c` source).

---

## State

Cross-function state is held in prefixed shell globals (one prefix per command) set by the parse/poll helpers and read by later steps of the same command. Nothing persists across invocations except the registry, sidecar and log files.
