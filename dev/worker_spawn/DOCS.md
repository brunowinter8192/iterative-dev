# dev/worker_spawn/

## Role

Smoke tests for the worker spawn flow in src/spawn: tmux session creation, environment inheritance, proxy setup, cross-project worktrees, pane capture cleaning. No live Claude Code session; mocks and stubs stand in.

## Public Interface

No `__init__.py`; each script is run manually: `python3 dev/worker_spawn/test_capture_clean.py`, `bash dev/worker_spawn/test_direct_command.sh`, `bash dev/worker_spawn/test_spawn_flow.sh`, `bash dev/worker_spawn/test_xproject_worktrees.sh`, `bash dev/worker_spawn/render_runner_flags.sh`, `bash dev/worker_spawn/verify_no_viewer.sh`, `bash dev/worker_spawn/verify_viewer_app.sh`, and the live measurement `bash dev/worker_spawn/measure_viewer_focus.sh <window count>`.

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

### test_direct_command.sh (39 LOC)

**Purpose:** Verifies a tmux session started with a direct command inherits environment variables and PATH.
**Reads:** The environment of the run.
**Writes:** stdout; a throwaway tmux server.
**Called by:** Run manually.
**Calls out:** tmux, `dev/strand_runner.sh`.

---

### test_spawn_flow.sh (202 LOC)

**Purpose:** Tests the spawn flow without real Claude Code: viewer launch, proxy setup with a stub proxy binary, and a full spawn with a mock.
**Reads:** `src/spawn` shell modules (sourced).
**Writes:** stdout; throwaway tmux servers, repos, proxy marker file, all removed.
**Called by:** Run manually.
**Calls out:** tmux, python3, `dev/strand_runner.sh`.

---

### test_xproject_worktrees.sh (180 LOC)

**Purpose:** Smoke test for cross-project worktree tracking in worker-cli: create, kill cleanup, sidecar skipping in listings, orphan removal.
**Reads:** Nothing persistent.
**Writes:** stdout; throwaway repos and registries removed.
**Called by:** Run manually.
**Calls out:** `bin/worker-cli` (subprocess), git, `dev/strand_runner.sh`.

---

### render_runner_flags.sh (93 LOC)

**Purpose:** Renders the runner-script flags produced by spawn, file-based spawn and revive with mocked tmux, and asserts the permission mode.
**Reads:** `src/spawn` shell modules (sourced).
**Writes:** stdout; `md/render_runner_flags.md`; a fake home directory removed on exit.
**Called by:** Run manually.
**Calls out:** bash only (tmux and helpers mocked).

---

### verify_no_viewer.sh (117 LOC)

**Purpose:** Verifies that a real worker-cli spawn opens the viewer by default and opens none when the viewer is suppressed.
**Reads:** Nothing persistent; osascript and open are stubs on PATH, the Ghostty app is a fixture.
**Writes:** stdout; per-strand stub call log and tmux server, removed.
**Called by:** Run manually.
**Calls out:** `bin/worker-cli` (subprocess), tmux, `dev/strand_runner.sh`, `viewer_fixture.sh`.

---

### verify_viewer_app.sh (124 LOC)

**Purpose:** Strands for the viewer app lifecycle: build, stale rebuild, single build under parallel callers, window script shape, suppression, missing Ghostty.
**Reads:** Nothing persistent; a fixture Ghostty app, stubbed open, osascript, pgrep and codesign; the shim is compiled for real.
**Writes:** stdout; per-strand scratch directory, removed.
**Called by:** Run manually.
**Calls out:** `src/spawn/worker_io.sh` (sourced), `dev/strand_runner.sh`, `viewer_fixture.sh`.

---

### viewer_fixture.sh (40 LOC)

**Purpose:** Shared test fixture: a fake Ghostty app bundle with version and commit, plus a signing stub.
**Reads:** `STRAND_DIR` of the sourcing strand.
**Writes:** the fake app and `codesign` stub inside the strand directory; exports `VIEWER_SOURCE_APP`.
**Called by:** `verify_viewer_app.sh`, `verify_no_viewer.sh`, `test_spawn_flow.sh` (sourced).
**Calls out:** none.

---

### measure_viewer_focus.sh (217 LOC)

**Purpose:** Live measurement: opens N viewer windows through the real path and checks frontmost app, main Ghostty front window and focus unchanged, windows attached and found by marker.
**Reads:** frontmost app (`lsappinfo`), main Ghostty state (read-only AppleScript), the shim log, `measure_viewer_focus_windows.js` output.
**Writes:** `md/measure_viewer_focus.md`, `md/measure_viewer_focus_samples.txt` (raw timestamped samples); opens windows on the live desktop and removes them.
**Called by:** Run manually; disturbs the desktop, so run it deliberately.
**Calls out:** `src/spawn/worker_io.sh` (sourced), tmux, osascript, lsappinfo.

---

### measure_viewer_focus_windows.js (7 LOC)

**Purpose:** JXA helper that lists onscreen layer-0 windows front to back with owner pid and bounds.
**Reads:** the CoreGraphics window list.
**Writes:** stdout.
**Called by:** `measure_viewer_focus.sh`.
**Calls out:** none.

## State

Each strand owns a private scratch directory (home, logs, registry, its own tmux server); nothing is shared between strands or with the real user state.
