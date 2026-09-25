# dev/worker_merge/

## Role

Test for the worker-cli merge command's built-in outcome verification, which replaced the orchestrator's manual post-merge check. Touch when changing merge output or its exit codes.

## Public Interface

No `__init__.py`; run manually: `bash dev/worker_merge/test_merge_verify.sh`.

## Flow

Two strands against throwaway repos: a real merge followed by a repeat merge (no-op), and a genuine conflict. Output, error text and exit codes are asserted.

## Modules

### test_merge_verify.sh (126 LOC)

**Purpose:** Exercises the real merge command against throwaway git repos: real merge, no-op re-merge, and conflict.
**Reads:** Nothing persistent.
**Writes:** stdout; throwaway repos removed on exit.
**Called by:** Run manually.
**Calls out:** `bin/worker-cli` (subprocess), git, `dev/strand_runner.sh`.

## State

Each strand owns a private scratch directory (home, logs, registry, its own tmux server); nothing is shared between strands or with the real user state.
