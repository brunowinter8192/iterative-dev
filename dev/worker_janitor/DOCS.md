# dev/worker_janitor/

## Role

Smoke test for the worker-cli janitor command, which cleans up stale worker sessions, worktrees, branches and registry entries. Touch when changing janitor behavior.

## Public Interface

No `__init__.py`; run manually: `bash dev/worker_janitor/test_janitor.sh`.

## Flow

Four cases run as parallel strands: dry run, real kill, fresh session spared, orphan registry entry cleaned. Each strand has its own tmux server, registry, log directory and throwaway repo.

## Modules

### test_janitor.sh (127 LOC)

**Purpose:** Exercises the real janitor against real tmux sessions on isolated servers, one strand per case.
**Reads:** Nothing persistent.
**Writes:** stdout; throwaway repos, sessions and logs, removed on exit.
**Called by:** Run manually.
**Calls out:** `bin/worker-cli` (subprocess), tmux, git, `dev/strand_runner.sh`.

## State

Each strand owns a private scratch directory (home, logs, registry, its own tmux server); nothing is shared between strands or with the real user state.
