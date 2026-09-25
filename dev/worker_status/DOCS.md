# dev/worker_status/

## Role

Tests for worker status detection, the closed working, idle and dead vocabulary. Exercises the real detection against throwaway tmux sessions. Touch when changing status detection.

## Public Interface

No `__init__.py`; run manually: `bash dev/worker_status/test_worker_status.sh` and `bash dev/worker_status/test_status_detection.sh`.

## Flow

Each status case is a parallel strand with its own home directory (hence its own hooks file), tmux server and fixture worker. A grep strand checks the retired vocabulary is gone from the status module.

## Modules

### test_worker_status.sh (355 LOC)

**Purpose:** Integration coverage for the working, idle and dead vocabulary including hook, quiet-pane, killed-child, killed-session and context-limit cases.
**Reads:** `src/spawn` shell modules (sourced).
**Writes:** stdout; throwaway tmux servers, project dirs and home directories, removed on exit.
**Called by:** Run manually.
**Calls out:** tmux, jq, `dev/strand_runner.sh`.

---

### test_status_detection.sh (31 LOC)

**Purpose:** Verifies tmux marks a pane dead after its process exits under remain-on-exit.
**Reads:** Nothing persistent.
**Writes:** stdout; a throwaway tmux server.
**Called by:** Run manually.
**Calls out:** tmux, `dev/strand_runner.sh`.

## State

Each strand owns a private scratch directory (home, logs, registry, its own tmux server); nothing is shared between strands or with the real user state.
