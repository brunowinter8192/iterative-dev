# Core (bin/, src/) Phase 1: size and complexity split, 2026-09-24

## What was done

Behaviour-preserving split of the two files over 400 LOC and extraction of helpers from every function of 50 LOC or more.

| Before | After |
|---|---|
| `bin/worker-cli` 895 LOC (inline `case` branches) | `bin/worker-cli` 64 LOC dispatcher + `src/worker_cli/{registry,cmd_query,cmd_lifecycle,wait,janitor}.sh`; every branch is now a `cmd_<name>` function |
| `src/spawn/tmux_spawn.sh` 937 LOC | `tmux_spawn.sh` 238 LOC (entry, naming, model resolution, spawn) + `worker_status.sh`, `worker_io.sh`, `worker_log_sidecar.sh`, `worker_proxy.sh`, `worker_revive.sh` |
| `worker_logger.sh` `_sample` 63 LOC | `_sample` + `_find_claude_pid`, `_claude_rss_mb`, `_total_rss_gb`, `_jsonl_age_s` |

`tmux_spawn.sh` stays THE file everything sources (dev suites, `bash -c "source $SPAWN && fn"`); it sources its siblings via `_SPAWN_LIB_DIR`. All function names called from outside a file are unchanged. No function in bin/ or src/ is at or above 50 LOC now (largest: `_janitor_resolve_worker` 49, unchanged; `worker_revive` 47; `cmd_wait` 44).

## Decisions a successor needs

- **worker-cli lib resolution uses the script's real path, not `$PLUGIN`.** `~/.local/bin/worker-cli` is a symlink into the integration checkout; `_resolve_cli_lib_dir` follows the symlink chain and loads `src/worker_cli/` from the checkout the script itself lives in. `$SPAWN` still comes from `$PLUGIN` (plugin cache), exactly as before. Consequence: a suite that runs `bin/worker-cli` from a worktree loads the worktree's `worker_cli` libs, but loads spawn libs from the cache unless `CLAUDE_PLUGIN_ROOT` points at the worktree. Suites `worker_merge`, `worker_janitor`, `worker_spawn/test_xproject_worktrees.sh` do NOT export `CLAUDE_PLUGIN_ROOT` themselves; export it before running them or they test the cached (old) spawn code.
- **Deploy order:** the plugin cache needs the new `src/spawn/*.sh` files together with `tmux_spawn.sh` (it now sources five siblings). A partial copy breaks every worker.
- **Errexit preservation in `worker_revive`:** the stored-env reads (`WORKER_MODEL`, `WORKER_PURPOSE`, `WORKER_PARENT`) live in `_revive_load_env`, which assigns globals `_REVIVE_*` and is called plainly. Wrapping the pipeline in `$(...)` would silently drop the inherited `set -e`/pipefail abort that the original inline code had when a variable is missing from the tmux environment. Keep it that way.
- **Cross-iteration state in the wait/janitor loops** became prefixed globals (`_WAIT_SAW_WORKING`, `_WAIT_ALL_NONBLOCKING`, `_WAIT_ANY_TERMINAL`, `_JANITOR_DRY_RUN` ...). The per-worker classification `_wait_classify_status` returns 0 (non-blocking) / 1 (blocking) instead of `break`; trace line texts are byte-identical to before (dev/worker_wait greps them).
- **`exit` inside helpers:** `_response_find_jsonl` and `_merge_*` keep `exit 2/3/4/1`; when a helper runs inside `$(...)` the exit only leaves the subshell and the outer assignment propagates the code via `set -e`. Do not remove `set -e` from `bin/worker-cli` without re-checking `response`.

## Dev-suite static checks that the split touches (dev/ is owned by another worker)

- `dev/model_selector/verify_worker_model_precedence.sh` requires >= 4 occurrences of `_resolve_worker_model` in `tmux_spawn.sh`. After the move of `worker_revive` the file has exactly 4 (doc comment, definition, two call sites); comment stripping in Phase 2 drops it to 3. The check should count code references or look at the whole `src/spawn/` directory.
- `dev/worker_status/test_worker_status.sh` greps `tmux_spawn.sh` for the retired strings `limit reached` and `echo "unknown"`; the status code now lives in `worker_status.sh`, so the grep passes trivially.

## Test results

See the Phase 1 report in the chat for per-suite results; every suite was run under `lockf /tmp/itdev-suite.lock` with `CLAUDE_PLUGIN_ROOT` set to the worktree.
