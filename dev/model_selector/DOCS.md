# dev/model_selector/

## Role

Verification scripts for the model-selector line of work's plugin-side half (milestone 3,
cross-repo with monitor-cc): worker-model resolution in `bin/worker-cli`, `src/spawn/spawn.py`,
and `src/spawn/tmux_spawn.sh` from `~/.claude/shared-rules/model_selection.json`.

## Public Interface

Both scripts are run manually, no importable interface: `bash dev/model_selector/verify_worker_model_precedence.sh`, `python3 dev/model_selector/verify_spawn_model_resolution.py`.

## Flow

No CLI input — each script drives the real `_resolve_worker_model()` (bash and Python sides respectively) against temp config paths, then prints a PASS/FAIL report to stdout (the Python side also writes its report to `md/`).

## Modules

### verify_worker_model_precedence.sh (207 LOC)

**Purpose:** Verifies `tmux_spawn.sh`'s `_resolve_worker_model()`, its 3 call-site expansion patterns, and a real `bin/worker-cli spawn` subprocess entry point.
**Reads:** nothing persistent — all config cases use a `mktemp -d` path via `MODEL_SELECTION_FILE`.
**Writes:** stdout only (no report file); real-entry-point section creates and cleans up its own tmux sessions, runner scripts, and `/tmp/worker-<name>.done` markers.
**Called by:** run manually — regression guard; re-run after any change to `_resolve_worker_model`, its 3 call sites, or `bin/worker-cli`'s `spawn)` case.
**Calls out:** `jq`, `tmux`, `src/spawn/tmux_spawn.sh` (sourced for real), `bin/worker-cli` (invoked for real via subprocess).

---

### verify_spawn_model_resolution.py (118 LOC)

**Purpose:** Verifies `spawn.py`'s `_resolve_worker_model()` config-resolution cases and confirms argparse's omitted-arg default never leaks the string `"None"`.
**Reads:** nothing persistent — all config cases use a `tempfile.TemporaryDirectory()`.
**Writes:** `md/verify_spawn_model_resolution.md`.
**Called by:** run manually — regression guard; re-run after any change to `spawn.py`'s model resolution or argparse setup.
**Calls out:** `src/spawn/spawn.py` (loaded by path).

## State

No shared state between the two scripts — each resolves its own temp config path independently. Neither touches the real `~/.claude/shared-rules/model_selection.json` or `~/.claude/.worker-registry`.
