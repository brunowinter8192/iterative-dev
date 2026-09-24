# dev/worker_spawn/

## Role

Smoke tests for the worker spawn flow in src/spawn: tmux session creation, environment inheritance, proxy setup, cross-project worktrees, pane capture cleaning. No live Claude Code session; mocks and stubs stand in.

## Public Interface

No `__init__.py`; each script is run manually: `python3 dev/worker_spawn/test_capture_clean.py`, `bash dev/worker_spawn/test_direct_command.sh`, `bash dev/worker_spawn/test_spawn_flow.sh`, `bash dev/worker_spawn/test_xproject_worktrees.sh`, `bash dev/worker_spawn/render_runner_flags.sh`.

## Flow

Each suite drives src/spawn or bin/worker-cli against private throwaway tmux servers, repos and registries, with independent cases as parallel strands. Mock claude and stubbed viewer or proxy binaries replace the real ones.

## Modules

### test_capture_clean.py (156 LOC)

**Purpose:** Fixture-based smoke for the pane-capture cleaner, one strand per check group.
**Reads:** Nothing external; writes its fixture to a temporary file.
**Writes:** stdout.
**Called by:** Run manually.
**Calls out:** `src/spawn/_capture_clean.py` (subprocess), `dev/strand_runner.py`.

---

### test_direct_command.sh (28 LOC)

**Purpose:** Verifies a tmux session started with a direct command inherits environment variables and PATH.
**Reads:** The environment of the run.
**Writes:** stdout; a throwaway tmux server.
**Called by:** Run manually.
**Calls out:** tmux, `dev/strand_runner.sh`.

---

### test_spawn_flow.sh (158 LOC)

**Purpose:** Tests the spawn flow without real Claude Code: viewer launch, proxy setup with a stub proxy binary, and a full spawn with a mock.
**Reads:** `src/spawn` shell modules (sourced).
**Writes:** stdout; throwaway tmux servers, repos, proxy marker file, all removed.
**Called by:** Run manually.
**Calls out:** tmux, python3, `dev/strand_runner.sh`.

---

### test_xproject_worktrees.sh (159 LOC)

**Purpose:** Smoke test for cross-project worktree tracking in worker-cli: create, kill cleanup, sidecar skipping in listings, orphan removal.
**Reads:** Nothing persistent.
**Writes:** stdout; throwaway repos and registries removed.
**Called by:** Run manually.
**Calls out:** `bin/worker-cli` (subprocess), git, `dev/strand_runner.sh`.

---

### render_runner_flags.sh (50 LOC)

**Purpose:** Renders the runner-script flags produced by spawn, file-based spawn and revive with mocked tmux, and asserts the permission mode.
**Reads:** `src/spawn` shell modules (sourced).
**Writes:** stdout; `md/render_runner_flags.md`; a fake home directory removed on exit.
**Called by:** Run manually.
**Calls out:** bash only (tmux and helpers mocked).

## State

Each strand owns a private scratch directory (home, logs, registry, its own tmux server); nothing is shared between strands or with the real user state.
