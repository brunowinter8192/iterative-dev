# itdevspawn: single worker-model resolution, dead plugin-sync.sh removed (2026-09-25)

Base: iterative-dev `integration`. Owner decisions, both implemented in this session.

## Model resolution

- The shell function `_resolve_worker_model` in `src/spawn/tmux_spawn.sh` is deleted. Only `src/spawn/spawn.py` resolves the model (config `worker` key of `model_selection.json`, else `claude-sonnet-5`, abort with `JSONDecodeError` on malformed JSON).
- New helper `_require_worker_model <model> <caller>` in `tmux_spawn.sh`. Empty model -> stderr `ERROR: <caller>: model argument is required`, return 1. Called first in `spawn_claude_worker` and `spawn_claude_worker_from_file` (before the prompt file is read). A missing 4th argument behaves like an empty one (`${4:-}`, no `set -u` crash).
- Unchanged: `worker_revive` (reads stored `WORKER_MODEL`), `cmd_spawn` (passes an empty model through to spawn.py), `spawn.py`.
- Consequence: a malformed config reports the same way on every path (spawn.py's JSONDecodeError); the shell no longer silently reads the config.

## plugin-sync.sh and root DOCS.md

- `plugin-sync.sh` deleted. The root DOCS.md documented only that script; the one-DOCS.md-per-module-directory rule left it empty, so it was deleted too. Checked before deleting: outside process-docs nothing references the root DOCS.md (`.rag-docs.json` matches `**/DOCS.md` by glob only; `dev/DOCS.md` links only to dev subareas).
- `bin/plugin-publish` covers the sync.

## Tests (dev/model_selector/verify_worker_model_precedence.sh)

Strands: `explicit_model`, `missing_model`, `e2e_no_model`, `e2e_explicit`, `e2e_malformed`, `structural`. The old `resolver` strand (shell config cases and the re-implemented call-site expansion) is gone; config cases live only in `verify_spawn_model_resolution.py`.
- `explicit_model`: sources tmux_spawn.sh, stubs `open_tmux_viewer`, calls `spawn_claude_worker_from_file` with a mock claude, asserts return 0, runner `--model` and tmux `WORKER_MODEL`.
- `missing_model`: both functions, empty and absent model -> non-zero, exact stderr message, no tmux session, no runner file.
- `structural`: 0 `_resolve_worker_model` references across `src/spawn/*.sh`, 1 helper definition, 2 helper calls, 1 stored-model read in worker_revive.sh.
- Trap (unchanged from earlier work): sourcing tmux_spawn.sh enables errexit in the strand; capture return codes with `cmd || rc=$?`.
- Other suites already passed a concrete model (`render_runner_flags.sh`, `test_spawn_flow.sh`); no change needed.

## Results (all with CLAUDE_PLUGIN_ROOT = worktree, parallel, hermetic)

- verify_worker_model_precedence.sh: 6 strands passed, 5s wall.
- verify_spawn_model_resolution.py: 6 cases passed.
- test_spawn_flow.sh 3/3, test_direct_command.sh 1/1, test_xproject_worktrees.sh 3/3, render_runner_flags.sh PASS.

## Stale statements in older process-docs (not edited, per rule)

The Phase 1/Phase 6 module_standards files describe two model resolvers and the plugin-sync.sh dead-code flag; both are superseded by this entry. The dev split file's model_selector salvage section describes the old shell resolver checks.

## Recap (2026-09-25)

- Files touched by this session: `src/spawn/tmux_spawn.sh`, `src/spawn/DOCS.md`, `dev/model_selector/verify_worker_model_precedence.sh`, `dev/model_selector/DOCS.md`, `dev/model_selector/md/verify_spawn_model_resolution.md` (regenerated report, timestamp only), deleted `plugin-sync.sh` and root `DOCS.md`.
- `git diff integration --name-only` additionally lists `skills/iterative-dev-refactor/SKILL.md`. That is not from this session: `integration` advanced past the branch base (f1650b3) with skill commits. Merging resolves it.
- Traps for a successor: the shell suite must run with `CLAUDE_PLUGIN_ROOT` at the checkout; sourcing `tmux_spawn.sh` enables errexit (capture rc with `|| rc=$?`); the live shell change only takes effect after `plugin-publish`, since `src/spawn/*.sh` loads from the plugin cache.
- Open: real-worker verification (with and without explicit model) after merge and publish is the orchestrator's step.
