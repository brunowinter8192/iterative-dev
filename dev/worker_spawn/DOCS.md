# dev/worker_spawn/

## Role

Smoke tests for the worker spawn flow (`src/spawn/`) — tmux session creation, env inheritance, cross-project worktree tracking, pane capture cleaning. No live Claude Code session started; dummy commands stand in.

## Public Interface

Each script is run manually, no importable interface: `python3 dev/worker_spawn/test_capture_clean.py`, `bash dev/worker_spawn/test_direct_command.sh`, `bash dev/worker_spawn/test_spawn_flow.sh [--no-ghostty]`, `bash dev/worker_spawn/test_xproject_worktrees.sh`.

## Flow

No shared input — each script drives `src/spawn/` (directly or via `bin/worker-cli`) against a throwaway tmux session, proxy, or git repo, then prints PASS/FAIL to stdout.

## Modules

### test_capture_clean.py (156 LOC)

**Purpose:** Fixture-based smoke for `src/spawn/_capture_clean.py`.
**Reads:** nothing external — writes its own fixture to a temp file.
**Writes:** stdout (pass/fail).
**Called by:** run manually.
**Calls out:** `src/spawn/_capture_clean.py` (via subprocess).

---

### test_direct_command.sh (28 LOC)

**Purpose:** Verifies tmux session inherits env vars (GH_TOKEN, PATH) when using direct command arg.
**Reads:** ambient env vars (GH_TOKEN, PATH).
**Writes:** stdout; creates and kills a throwaway tmux session.
**Called by:** run manually.
**Calls out:** tmux.

---

### test_spawn_flow.sh (158 LOC)

**Purpose:** Tests the full spawn flow without starting a real Claude Code session (dummy command instead of `claude-patched`).
**Reads:** `src/spawn/tmux_spawn.sh` (sourced).
**Writes:** stdout; creates and kills a throwaway tmux session + proxy + Ghostty window.
**Called by:** run manually.
**Calls out:** tmux, Ghostty, `src/spawn/tmux_spawn.sh`.

---

### test_xproject_worktrees.sh (159 LOC)

**Purpose:** Smoke test for cross-project worktree tracking in `worker-cli`.
**Reads:** nothing persistent — uses `WORKER_REGISTRY_DIR` + throwaway git repos.
**Writes:** stdout; throwaway git repos and registry files (cleaned up on exit).
**Called by:** run manually.
**Calls out:** `bin/worker-cli` (via subprocess), git.
