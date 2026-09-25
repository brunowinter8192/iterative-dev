# dev/worker_sweep_logs/

## Role

Smoke test for the worker-cli sweep-logs command, the log-directory retention sweep, and its automatic trigger at spawn. Distinct from janitor, which sweeps worker sessions.

## Public Interface

No `__init__.py`; run manually: `bash dev/worker_sweep_logs/test_sweep_logs.sh`.

## Flow

Five cases run as parallel strands, each with its own log directory and faked file ages: dry run, real run, trace-log exemption, default threshold, automatic trigger.

## Modules

### test_sweep_logs.sh (148 LOC)

**Purpose:** Exercises the real sweep-logs command and the real logger start against private log directories with backdated files.
**Reads:** Nothing persistent.
**Writes:** stdout; private log directories removed on exit.
**Called by:** Run manually.
**Calls out:** `bin/worker-cli` (subprocess), `src/spawn` shell modules (sourced), `dev/strand_runner.sh`.

## State

Each strand owns a private scratch directory (home, logs, registry, its own tmux server); nothing is shared between strands or with the real user state.
