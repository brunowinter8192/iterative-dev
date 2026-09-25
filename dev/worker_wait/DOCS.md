# dev/worker_wait/

## Role

Integration tests for the worker-cli wait command, the pull-based replacement for the orchestrator's sleep timer. Touch when changing wait, its exit rules or worker status detection.

## Public Interface

No `__init__.py`; run manually: `bash dev/worker_wait/test_worker_wait.sh`. Pass a strand name to re-run only that one.

## Flow

Each test is a parallel strand with its own home directory (own hooks file), trace log and tmux server. Fixture workers are dummy processes; wait runs for real and exit reason and timing are asserted.

## Modules

### test_worker_wait.sh (33 LOC)

**Purpose:** Entry point: sources the runner, fixtures and test files, declares the strands and starts them.
**Reads:** Nothing persistent.
**Writes:** stdout.
**Called by:** Run manually.
**Calls out:** `fixtures.sh`, `tests_gate.sh`, `tests_transitions.sh`, `dev/strand_runner.sh`.

---

### fixtures.sh (212 LOC)

**Purpose:** Fixture library: fake-worker builders, hook-entry helpers, fake background-task handles and per-strand setup and cleanup.
**Reads:** The strand's private home directory.
**Writes:** Its hooks file, project dirs and tmux sessions.
**Called by:** `test_worker_wait.sh`, sourced.
**Calls out:** tmux, jq.

---

### tests_gate.sh (152 LOC)

**Purpose:** Test functions for the transition-gate proofs: idle from start, no worker, working then idle, concurrent waits, vanished session.
**Reads:** Fixtures from `fixtures.sh`.
**Writes:** stdout via the runner's pass and fail.
**Called by:** `test_worker_wait.sh`, sourced.
**Calls out:** `bin/worker-cli` (subprocess).

---

### tests_transitions.sh (214 LOC)

**Purpose:** Test functions for background-task handles, probe errors, no-hook self-heal, dead paths, mixed projects and the second transition.
**Reads:** Fixtures from `fixtures.sh`.
**Writes:** stdout via the runner's pass and fail.
**Called by:** `test_worker_wait.sh`, sourced.
**Calls out:** `bin/worker-cli` (subprocess), lsof.

## State

Each strand owns a private scratch directory (home, logs, registry, its own tmux server); nothing is shared between strands or with the real user state.
