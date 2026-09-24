# itdevdev worker: Phase 1 (size and complexity) on dev/

Scope: dev/ of iterative-dev, findings scanned 2026-09-24 on integration 05609b9.

## What changed

- dev/worker_wait/test_worker_wait.sh (739 LOC) split into four files that are sourced by
  the entry script: fixtures.sh (295), tests_gate.sh (187, Tests 1/1b/1c/2/2b/3/3b/4),
  tests_transitions.sh (276, Tests 5-11), test_worker_wait.sh (65, constants, cleanup trap,
  ordered calls). Every test became one function (max 42 LOC). Test variables stay global, as
  they were at script level (Test 1 and Test 1c share TRACE_SIZE_BEFORE1 and PROJ1).
- create_worker (wait 65 LOC, status 56 LOC) is the same fixture builder in both areas
  (code identical, only comments differed). Extracted per area, no cross-area lib:
  encode_proj_dir, start_tmux_session, register_jsonl, write_wrap_bg/chatty/plain/no_pid,
  write_worker_wrapper. create_worker_dead / _no_hook / _no_jsonl / _limit_reached reuse them.
- verify_worker_model_precedence.sh: _run_e2e_spawn split into _write_mock_claude,
  _spawn_via_cli, _assert_spawn_models.
- probe_bracketed_paste.sh: run_delivery_case and run_old_method_demo share init_scratch_case,
  register_jsonl_dir, sample_latencies, verify_delivery, send_via_worker_send,
  paste_old_method. Helpers that must mutate the SCRATCH_DIRS/SESSIONS arrays return values
  through globals (CASE_SCRATCH, CASE_SESSION, CASE_JSONL_DIR, VERIFY_*) because a $(...)
  call would lose the array appends.

## Testing method

Baseline runs of all four suites on the unchanged files, then the same runs after the change,
each under `lockf /tmp/itdev-suite.lock` (another worker runs suites in parallel and the wait
and status suites share the real hooks.json and tmux namespace). Copies of the originals are in
/tmp/itdevdev/dev_orig, outputs in /tmp/itdevdev/base and /tmp/itdevdev/after. The baseline
must not be edited while a suite is running: bash reads a script incrementally, so I staged
all new files in /tmp/itdevdev/new and copied them in under the lock afterwards.
probe_bracketed_paste.sh rewrites the tracked md/ report on every run; restore it with git
checkout so the commit contains no report churn.

## Open items for the follow-up after itdevcore is merged (src/spawn/tmux_spawn.sh split)

1. verify_worker_model_precedence.sh structural check greps tmux_spawn.sh for >= 4
   occurrences of _resolve_worker_model. It counted 5 (definition, one doc comment, three
   call sites). Once Phase 2 removes the comment it is 4, and after the split the call sites
   may live in sibling files, so the grep must point at the right files.
2. test_worker_status.sh greps tmux_spawn.sh for the retired strings `limit reached` and
   `echo "unknown"`. The status code moves to worker_status.sh, so the grep passes trivially
   against tmux_spawn.sh. It must scan the new files.
3. Comments inside helper blocks (moved verbatim) are still present; Phase 2 strips them.

## Phase 3 notes (not acted on)

- wait and status suites mutate the one real hooks.json and use the shared tmux namespace,
  so they cannot run in parallel with each other or with other workers' suites (lockf used).
- Wait tests are strictly sequential with 25s-40s waits each; independent tests
  (1, 2, 2b, 6, 8) could only run concurrently with a per-strand hooks.json path, which
  bin/worker-cli does not currently allow.
- TRACE_FILE is shared and appended by any real wait invocation.
- Suites do not stop at the first failure; they only set RESULT=1.

# Phase 2 (comments and docstrings in dev/), 2026-09-24, base integration b27dc91

All comments were removed from dev/*.sh with a script (kept outside the repo; it walks each
file with a quote/heredoc-aware scanner, so `#!` lines, `#` inside quotes and heredoc bodies
stay). Nothing in dev/ reads its own comments at runtime (no `sed -n ... "$0"` style help
output). Knowledge that only lived in comments is recorded here, per source file.

## Carried-over items, done

- test_worker_status.sh: 422 LOC before, 362 after the comment removal, so no split needed.
- The retired-string greps (`limit reached`, `echo "unknown"`) now scan
  src/spawn/worker_status.sh, where _worker_detect_status lives after the itdevcore split.
  A third assertion first requires `^_worker_detect_status()` in that file, so the greps
  cannot pass vacuously against a file that no longer holds the code. The suite has 3 grep
  cases now instead of 2 (an intended, additive change).
- verify_worker_model_precedence.sh structural check: the old `>= 4 occurrences in
  tmux_spawn.sh` counted a doc comment. It now requires exactly 1 definition
  (`^_resolve_worker_model()` in tmux_spawn.sh) and exactly 3 `$(_resolve_worker_model)` call
  sites across tmux_spawn.sh (spawn_claude_worker, spawn_claude_worker_from_file) and
  worker_revive.sh (revive fallback). Observed counts on b27dc91: 1 definition, 3 call sites.
- dev/*/DOCS.md: paths updated to src/worker_cli/*.sh and src/spawn/worker_*.sh; every .sh
  module heading now carries its exact LOC.

## Knowledge from removed comments

verify_worker_model_precedence.sh
- The isolated resolver checks passed while the assembled path (bin/worker-cli spawn ->
  spawn.py -> tmux_spawn.sh) was dead code, because a fifth hardcode in bin/worker-cli
  pre-resolved the "no model" case. Only the real-entry-point section (subprocess call of
  bin/worker-cli) catches that class of bug.
- The real-entry-point call must export CLAUDE_PLUGIN_ROOT to the worktree. Without it
  bin/worker-cli falls back to the INSTALLED plugin cache copy and silently tests stale code
  (observed: the installed copy still had the old hardcoded default).
- Isolation: MODEL_SELECTION_FILE points at a temp file, WORKER_REGISTRY_DIR and CLAUDE_BIN are
  overridden, PROXY_PROJECT_PATH is unset so an ambient proxied session cannot redirect the
  scratch project path. The real ~/.claude/shared-rules/model_selection.json is never read.
- `set -uo pipefail` deliberately has no `-e`: a failed assertion must not abort the script.
- `sleep 1` after the spawn call lets the runner script materialize and the tmux env settle.

test_janitor.sh
- Uses WORKER_REGISTRY_DIR plus a throwaway git repo and an isolated tmux server (`tmux -L`,
  reached through a PATH-shadowing wrapper), so the real-run pass cannot touch live sessions
  even with --max-age-hours 0. session_created cannot be faked: the age gate is exercised via
  --max-age-hours 0 (killed) and the default 12h (spared).
- Project subdir needs a dot-free basename: mktemp's tmp.XXXXXXXX contains a ".", tmux rewrites
  "." to "_" in session names and the live name then differs from what _worker_session_name
  computes from the basename.
- The `sleep 1` after session creation lets session_created / pane state settle.
- Cases: 1 dry-run lists a synthetic session, 2 real run kills it, 3 fresh session spared by
  the age gate, 4 orphan registry entry (no tmux session) cleaned.

test_merge_verify.sh
- Throwaway git repo on main with a real commit, explicit project_path argument, no registry,
  no tmux. Cases: 1 real merge brings in a file, 2 re-merge of the same branch is a no-op,
  3 real conflict: git's own conflict output must reach the caller.

probe_bracketed_paste.sh
- cleanup_case sleeps 1.5s before removing dirs: Claude Code writes an async post-turn title
  record shortly after the turn appears in the JSONL, and an immediate kill-session raced that
  write and left a one-line orphan project dir (observed live).
- Message sizes and background are in the process-docs of area worker_message_delivery.

test_direct_command.sh (test H1) and test_status_detection.sh (test H2)
- H1: a direct command argument to tmux new-session inherits env vars and executes
  immediately, no polling; checks GH_TOKEN and PATH in the captured pane.
- H2: #{pane_dead} goes 0 -> 1 after the process exits under remain-on-exit.

test_spawn_flow.sh
- Covers: proxy starts with PROXY_LOG_ID; tmux session creation is non-blocking; Ghostty
  open_tmux_viewer is non-blocking (skipped with --no-ghostty for headless/CI);
  spawn_claude_worker returns within 5s; worker proxy writes a separate log file; proxy is
  killed on session exit. Uses a dummy command instead of claude-patched to avoid token cost.
- The project under test is Monitor_CC because the proxy marker files live there. The worker
  proxy port is MAIN_PORT + 100 to avoid collisions. Elapsed time handles both ns and s clocks.
- The mock is written to the fixed shared path /tmp/claude-patched and PATH is extended
  temporarily (phase 3: shared file, cannot run in parallel with another copy).
- A missing worker proxy process at the end is accepted: it may already be killed or was never
  started because no marker exists.

test_xproject_worktrees.sh
- Cases: 1 worktree tw1 <target> creates the cross-project worktree; 2 kill tw1 cleans BOTH the
  spawn side (worktree, branch, registry entry) and the cross-project side (sidecar, registry);
  no tmux, so session-kill is a no-op and spawn helpers carry `|| true`; 3 list and
  status --all skip *.worktrees sidecars (a planted sidecar must not appear as a worker);
  4 worktree-rm removes an orphaned cross-project worktree and branch.

test_sweep_logs.sh
- Ages are faked with `touch -t` (macOS `date -v`, GNU `date -d` fallback, same idiom as
  test_janitor.sh). Cases: 1 dry-run deletes nothing, 2 real run removes stale and spares fresh,
  3 wait_trace.log is exempt regardless of age, 4 default threshold is 72h and not "match
  everything", 5 the real spawn/revive trigger _start_worker_logger sweeps the directory it is
  about to write into.

log_permission_request.sh
- Hook script: appends the timestamped PermissionRequest input to
  /tmp/permission_request_log.jsonl (one JSON object per line), then passes the input through
  unchanged so the normal permission flow is not disturbed. Install by adding it under
  hooks.PermissionRequest in ~/.claude/settings.json.

worker_wait fixtures and tests (moved-in comments from Phase 1 split)
- BG=1 fixture: the claude-dummy must stay a real bash process. If it were exec'd away,
  _worker_detect_status finds no claude-named descendant and misreports a dead worker. The
  persistent tooling grandchild (pyright-langserver-dummy) is never killed; the handle-based
  bg-task check must ignore it (the old process-tree walk read any grandchild as busy).
- CHATTY=1 is the only way to keep #{window_activity} fresh past 10s, which is the demote
  threshold for hook status working. A silent wrapper goes stale after ~10s regardless of what
  hooks.json says. go_quiet touches PROJ_DIR/.chatty-quiet to stop the loop.
- Fixtures must set WORKER_SPAWNED and WORKER_PURPOSE in the tmux env: worker_list's
  show-environment lookup errors on a missing variable, which under set -euo pipefail aborts
  the whole function silently.
- tmux reports pane_current_path canonicalized (macOS /tmp -> /private/tmp), so the encoded
  ~/.claude/projects directory must be derived from the real path (pwd -P). raw_tasks_dir keeps
  the unresolved /tmp prefix on purpose: the handle is opened via /tmp while detection resolves
  /private/tmp, proving the same file is matched.
- kill_claude_child kills only the recorded claude-dummy pid; remain-on-exit then leaves the
  pane dead (pane_dead=1 -> dead). Killing the whole SESSION is a different path (empty NAMES,
  never dead). delete_hook_entry alone is not a dead signal any more; Test 10 pairs it with
  kill_claude_child.
- create_worker_dead: wrapper exits immediately, pane_dead=1, returns before JSONL/hooks lookups.
- TRACE_FILE is the real shared wait_trace.log; tests diff byte sizes before/after and grep the
  test's own project= tag because a concurrent real wait writes to the same file.
- Test intent per number: 1 idle-from-start never exits, 1c trace shows no saw_working=1,
  1b tooling-child incident plus gate unlock, 2/2b no worker never exits (only timeout),
  3 chatty working then idle exits, 3b two concurrent waits exit together, 4 vanished session
  ends in timeout, 5 open *.output handle holds until closed (5a checks /private/tmp
  resolution), 6 lsof unresolvable via stripped PATH gives timeout, 7 no hook entry
  self-heals working -> idle, 8 dead from start times out, 8b working then killed child exits
  "worker dead", 9 mixed dead + working exits "worker dead" after the busy one idles,
  10 dead with open bg handle still exits promptly (bg probe skipped for dead), 11 armed while
  idle survives 18s and exits only after a later working -> idle edge.

test_worker_status.sh
- Same fixture builders as the wait suite (deliberately a standalone copy). Additional
  fixtures: create_worker_no_jsonl (no project dir entry at all, a fresh spawn),
  write_synthetic_marker_jsonl (last assistant entry with model "<synthetic>", text
  "Prompt is too long", isApiErrorMessage true, error invalid_request, usage all 0) and
  write_normal_assistant_jsonl (real model, no marker) to prove the guard has no false
  positive. Dead signals are checked before hook_status, so the marker overrides a hooks
  idle entry.
- Case intent: 1 hook idle wins, 2 hook working plus chatty stays working, 3 ESC case (working,
  quiet > 10s) reads idle, 4/5 no hook entry chatty vs quiet, 6 no JSONL reads working, 7 killed
  claude child dead, 8 pane dead, 9 killed session via worker_status dead (worker_status gates
  on has-session itself), 10 synthetic marker dead, 11 ordinary aborted message idle.

# Phase 3 (test structure of dev/), 2026-09-25, base integration c14831e

## Design

- dev/strand_runner.sh (sourced by every shell suite) and dev/strand_runner.py (Python suites)
  run each independent case as a strand in parallel. A suite declares `STRANDS=(...)`, defines
  one function `strand_<name>` per strand and ends with `strand_main "$@"`. Arguments select
  strands: `bash suite.sh conflict` re-runs only that strand.
- Fail-fast: `fail` prints and `exit 1` inside the strand subshell (`check` and `pass` are the
  shared helpers); a failing strand stops at its first failure, the other strands keep
  running, the suite exits 1 if any strand failed. In Python a failed assert raises and ends
  that strand only.
- Isolation per shell strand, no production change: HOME, WORKER_LOGGER_DIR and
  WORKER_REGISTRY_DIR point into a private mktemp dir; a PATH-shadowing tmux wrapper pins the
  strand to its own `tmux -L` server (with TMUX unset); git identity is exported through env.
  Because hooks.json (src/spawn/worker_status.sh), ~/.claude/projects and the default log dir
  all hang off $HOME, each strand has its own hooks.json without a WORKER_HOOKS_FILE override.
  The src/ override was proposed as a fallback and was not needed.
- Optional per-suite hooks: `strand_init` (runs inside the strand after the isolation) and
  `strand_cleanup` (runs from the EXIT trap, also after a fail-fast exit).
- Python runner uses a process pool (not threads): redirect_stdout and monkeypatching a module
  attribute are process-global. Case functions and the runner live at module top level so the
  spawn start method can pickle them; run_strands returns (exit_code, outputs) so a suite can
  still assemble its report file.
- One run per suite, no repetitions; a flake is reported, not re-run.

## Findings while converting (observed, each cost time)

- HOME override changes worker-cli's plugin fallback: without CLAUDE_PLUGIN_ROOT, bin/worker-cli
  resolves $HOME/.claude/plugins/cache/... (the INSTALLED copy). The janitor suite never set
  CLAUDE_PLUGIN_ROOT, so it had been testing the installed plugin copy, not the checkout. Under
  the fake HOME the janitor read "working" for every session (source of a missing file failed,
  the fallback answers working). Every suite that runs bin/worker-cli now exports
  CLAUDE_PLUGIN_ROOT to the checkout.
- Hidden case dependency: in test_sweep_logs.sh the fresh file of case 2 was created by case 1.
  Run as its own strand the case reported "stale file removed" as PASS although the stale file
  had never existed (a vacuous pass) and then failed on the missing fresh file. Fixed by giving
  each case its own fixture. Cases 1+2 of merge, and 1+2 of xproject (kill uses the cross-project
  worktree of case 1) are really dependent and stay together in one strand.
- Race on a fixed sleep: the sweep-logs case that starts the real worker logger checked for the
  new log file after `sleep 1`. Under 5 parallel strands the detached logger needed longer; the
  check now polls up to 10s for the file.
- test_worker_wait Test 6 strips /usr/sbin from PATH to make lsof unresolvable. Replacing PATH
  wholesale also drops the tmux wrapper, so the strand would have talked to the default tmux
  server and "passed" vacuously with timeout. PATH now keeps "$STRAND_DIR/bin" first.
- The wait trace: with a private WORKER_LOGGER_DIR per strand the byte-offset diff and the
  project= grep against the shared wait_trace.log are no longer needed for isolation (the
  project= grep stays, it is harmless and pins the assertion to the test's own project).
- test_direct_command.sh asserted `GH_TOKEN=ghp_` in the pane, i.e. it depended on the
  developer's real token. It now exports its own probe variable and asserts that it is inherited.
- Two PASS lines the old suites printed were environment checks, not code checks: spawn_flow
  Test 2 ("proxy marker exists") only proved that a monitor-cc proxy was running.

## test_spawn_flow.sh: why 3 of 7 failed, and the rebuild

1. TEST_PROJECT was .../ai/Monitor_CC (does not exist; the repo is monitor-cc).
2. The proxy marker /tmp/.monitor_cc_proxy_<md5> and /tmp/.monitor_cc_root exist only while a
   monitor-cc proxy session runs for that exact project. Tests 2 and 3 measured the machine.
3. The mock was named claude-patched on PATH, but spawn_claude_worker runs
   ${CLAUDE_BIN:-$HOME/.local/bin/claude-280}. The mock never ran; a real claude-280 started
   (token cost) in a nonexistent directory, hence "mock claude not found in pane".
4. spawn_claude_worker opens a Ghostty window in the background; --no-ghostty only covered Test 1.
5. The old mock did not print the `❯` prompt that _wait_for_input_ready waits for, so even a
   working mock would have hit the 30s timeout.

Rebuild (3 strands, all pass): viewer (open_tmux_viewer with stubbed ghostty/osascript/open, asserts
the tmux attach command reaches the launcher and returns fast), proxy (real _worker_proxy_setup
against a fixture marker + fake monitor root; only mitmdump is a stub that binds the requested
port, so port selection, wait-ready, env prefix, per-worker log file and cleanup are real; a real
mitmdump/addon is NOT exercised), spawn (real spawn_claude_worker with CLAUDE_BIN pointing at a
mock that prints the prompt line, viewer stubbed, project = throwaway git repo).
Limit: nothing in dev/ verifies that the real mitmdump proxy actually intercepts traffic.

## Runtime and counts (single runs, 2026-09-25)

| suite | strands | result | before | after |
|---|---|---|---|---|
| worker_wait/test_worker_wait.sh | 15 | 15 pass (22 asserts, same as before) | 319s | 41s |
| worker_status/test_worker_status.sh | 12 | 12 pass (14 asserts, +1 new grep) | 44s | 15s |
| worker_status/test_status_detection.sh | 1 | pass | 4s | 4s |
| worker_janitor/test_janitor.sh | 4 | pass (11) | 4s | 2s |
| worker_merge/test_merge_verify.sh | 2 | pass (10) | 0s | 1s |
| worker_sweep_logs/test_sweep_logs.sh | 5 | pass (12) | 2s | 2s |
| worker_spawn/test_xproject_worktrees.sh | 3 | pass (14) | 0s | 1s |
| worker_spawn/test_direct_command.sh | 1 | pass (2) | 2s | 1s |
| worker_spawn/test_spawn_flow.sh | 3 | pass (10 checks) | not timed, 4 pass / 3 fail | 3s |
| model_selector/verify_worker_model_precedence.sh | 4 | pass (16) | 5s | 3s |
| poread_cli/test_poread_cli.py | 5 | pass | 0s | 0s |
| worker_spawn/test_capture_clean.py | 3 | pass | 0s | 0s |
| model_selector/verify_spawn_model_resolution.py | 6 | pass | 0s | 0s |
| docs_drift_check/test_docs_drift_check.py | 16 (15 fixtures + missing-root) | pass | 1s | 1s |

Parallelism is bounded by the slowest strand: wait now costs about its slowest test (Test 11).
The wait and status suites no longer touch the real hooks.json; running them concurrently with
another worker's suites needs no lock.

## Not done / remaining

- probe_* scripts and other experiments are out of scope by the findings.
- The DOCS.md files of the dev areas still describe the old sequential/shared-hooks.json shape
  until the Phase 4 rewrite.
