# dev/model_selector/

## Role

Verification scripts for worker-model resolution from the shared model-selection config, across bin/worker-cli, src/spawn/spawn.py and the src/spawn shell modules. Re-run after changing resolution, its call sites or the spawn subcommand.

## Public Interface

No `__init__.py`; run manually: `bash dev/model_selector/verify_worker_model_precedence.sh` and `python3 dev/model_selector/verify_spawn_model_resolution.py`.

## Flow

Each script drives the real resolver (shell and Python side respectively) against temporary config files, with independent cases as parallel strands. The Python side also writes its report to md/.

## Modules

### verify_worker_model_precedence.sh (208 LOC)

**Purpose:** Verifies the shell resolver, its call-site pattern, static wiring, and real worker-cli spawns against a mock claude, including the abort on a malformed config.
**Reads:** Only temporary config files; the real model-selection config is never touched.
**Writes:** stdout; per-strand tmux servers, runner scripts and markers, all removed.
**Called by:** Run manually as a regression guard.
**Calls out:** jq, tmux, `src/spawn` shell modules, `bin/worker-cli` (subprocess), `dev/strand_runner.sh`.

---

### verify_spawn_model_resolution.py (161 LOC)

**Purpose:** Verifies the Python resolver's config cases, the abort on a malformed config, and that an omitted model argument never leaks the string None.
**Reads:** Only temporary config files.
**Writes:** stdout; `md/verify_spawn_model_resolution.md`.
**Called by:** Run manually as a regression guard.
**Calls out:** `src/spawn/spawn.py` (loaded by path), `dev/strand_runner.py`.

## State

Each strand owns a private scratch directory (home, logs, registry, its own tmux server); nothing is shared between strands or with the real user state. The Python cases load the spawn module fresh in separate processes because the resolver's config path is module state.
