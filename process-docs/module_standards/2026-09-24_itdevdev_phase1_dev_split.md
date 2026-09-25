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

# Phase 4 step 2 (dev/ DOCS.md rewrite), 2026-09-25

Every dev/*/DOCS.md was rewritten into the DOCS.md format (Role, Public Interface, Flow, Modules, State; Role up to 50 words, Purpose up to 25 words, exact LOC). Prose that was cut is kept verbatim below, per source file, as it stood on integration c14831e plus the Phase 3 tree (the wait, status and janitor texts therefore still describe the pre-Phase-3 sequential shape and shared hooks.json). Function and constant names were dropped from the DOCS.md files (docs-drift-check rule); the salvaged text keeps them.

## Salvage from dev/worker_wait/DOCS.md

````markdown
# dev/worker_wait/

## Role

Integration tests for `worker-cli wait` (`src/worker_cli/wait.sh`) — the pull-based
replacement for the orchestrator's background sleep-timer.

## Modules

### test_worker_wait.sh (33 LOC)

**Purpose:** Entry point of the suite: sets constants and the cleanup trap, sources the three sibling files, then calls every test function in order.
**Calls out:** `fixtures.sh`, `tests_gate.sh`, `tests_transitions.sh` (sourced, not executed on their own).

### fixtures.sh (212 LOC)

**Purpose:** Sourced fixture library: hooks.json backup/restore/set, fake-worker builders (`create_worker*`, `destroy_worker`), wrapper writers, fake bg-task handles.

### tests_gate.sh (152 LOC)

**Purpose:** Sourced test functions for Tests 1, 1b, 1c, 2, 2b, 3, 3b, 4 (transition-gate core proofs).

### tests_transitions.sh (214 LOC)

**Purpose:** Sourced test functions for Tests 5 to 11 (bg handle, lsof error, no-hook self-heal, dead paths, mixed project, second transition).

The description below applies to the suite as a whole.

**Purpose:** Exercise the real `worker-cli wait` binary against real tmux sessions + a
scoped `hooks.json` entry (backed up/restored around the run, never left dirty).

**Transition-gate contract (2026-09-02):** `wait` may only exit `"workers idle"` or `"worker
dead"` if THIS invocation observed at least one `working`-status poll first (`SAW_
WORKING`, set only on a verbatim `working` classification, never on the `dead`/default-arm
busy path). An idle-at-arm or never-registered worker is a *state*, not a *transition* —
`wait` now keeps polling through it instead of exiting on it. The `"no workers"` fast-exit
(C3, 2026-08-18) is removed entirely: an empty roster is just another non-exiting state,
same reasoning as idle-at-arm. Covers: idle-from-start and never-registered never exit
early (run to the timeout ceiling instead), a genuinely `working` (chatty print-loop, keeps
`#{window_activity}` fresh past the 10s demote threshold — `src/spawn/worker_status.sh`) worker edging
to idle DOES exit `"workers idle"` within the existing 3-sample/5s-poll stability window,
two concurrent `wait` processes armed during a real working phase exit together on the same
edge, a working worker whose claude child is killed (session/pane stay alive via
`remain-on-exit`, distinct from a killed SESSION which stays on the untouched empty-`NAMES`
path) edges to `"worker dead"`, and `wait` armed while idle survives an idle-only stretch
well past the old 15s threshold before exiting only after a later working->idle edge, never
the first idle phase. The `saw_working=` flag is on every per-poll and exit trace line for
direct before/after diffing.

**Working/idle/dead vocabulary (2026-09-02, milestone 2 of the status-vocabulary change):**
the consumers in `src/worker_cli/` of `_worker_detect_status`/`worker_status` were moved from
the retired `working`/`idle`/`"limit reached"`/`unknown` set to the closed three-value
`working`/`idle`/`dead` set `src/spawn/worker_status.sh` now returns (milestone 1, same area). `wait`'s
classification switch collapsed the `"limit reached"|unknown)` arm into a single `dead)`
arm — trace fields renamed `class=dead`, `reason=worker_dead`, `any_dead=`; exit line
`"worker dead"`. A `worker_status`/`_worker_detect_status` subprocess-call FAILURE (not a
worker_status "dead" answer, which already returns 0) is a probe error, not a worker state —
`wait`'s fallback is `probe-error`, which lands in the switch's `*)` default arm (stays
blocking, never arms `SAW_WORKING`) and is visible verbatim on the trace's `status=` field.

**A vocabulary consequence discovered by running the suite, not assumed:** a fresh pane
with no hooks.json entry (`create_worker_no_hook`) is no longer a distinct terminal state.
It now shares the SAME window-activity check as any other no-hook-data case — it reads as
`working` for its first ~10s (a just-created pane's activity is genuinely fresh; this is a
correct default, not a misclassification) and self-heals to `idle` once quiet. This retires
Test 7's original "stuck forever" framing: the 2026-08-19 incident it regression-guarded is
now fixed by self-healing rather than a special carve-out, so Test 7 was RE-PURPOSED (not
just relabeled) to assert `"workers idle"` after the self-heal, with a trace check for
`status=working` polls settling into `status=idle` polls. The "never observed working, gate
holds" proof for a from-the-start case still lives in Tests 1/2/11a, which use an explicit
`idle` hook status or no worker at all — neither goes through this shared fresh-pane
window. Similarly, `delete_hook_entry` ALONE is no longer a dead signal (same reasoning) —
Test 10 now combines it with `kill_claude_child` (the real dead signal) to build a
realistic dead-and-hook-orphaned worker, rather than relying on hook-deletion by itself.

**Also covers (unchanged by the transition gate or the vocabulary move, verified
compatible): the C1 (2026-08-18) trace-observability check (`event=start`/`event=exit`
lines diffed via before/after byte offset on the real, shared, gitignored
`wait_trace.log`, now additionally grep-scoped to this test's own `project=` tag — a
concurrently running REAL `wait` invocation elsewhere on the machine writes to the same
shared file and would otherwise pollute a byte-offset-only diff, observed live during this
milestone), a live incident regression (idle worker with a **persistent tooling-child
process** under its `claude` pid, e.g. a language server, correctly ignored by the
handle-based bg-task check), a vanished probe target (killed SESSION, not just the claude
child) never yielding a false `"workers idle"`, a genuinely open `*.output` write handle
holding off exit until closed — including the `/tmp` vs `/private/tmp` resolution gotcha —
and an `lsof`-unresolvable probe error never yielding a false `"workers idle"` either.

**Dead-worker wake (2026-08-19 incident regression, terminology updated 2026-09-02):** a
stably `dead` worker (after a real working phase, per the transition gate above) folds
into the same "non-blocking" bucket as `idle` on the existing stability window, exiting
`"worker dead"` (distinct from `"workers idle"`). Covers: a killed claude child with the
pane held alive via `remain-on-exit` (`kill_claude_child`), a wrapper that exits
immediately (`create_worker_dead`, `#{pane_dead}=1` directly), a mixed project (one dead +
one genuinely `working` worker — proves dead doesn't short-circuit a real busy worker, and
the exit line stays `"worker dead"` once the busy one finishes), and a dead worker (process
killed AND hook entry deleted) with a live open `*.output` handle still exiting promptly
(proves the bg-task probe is deliberately skipped for dead statuses, not applied like it
is for `idle`).

**Chatty fixture gotcha:** `create_worker`'s `CHATTY=1` mode is the only way to keep
`#{window_activity}` fresh past 10s (a plain/`BG=1` worker is silent, so a `working` status
flipped in well after creation demotes to `idle` before ever being read as `working`).
`go_quiet()` stops the print loop; `kill_claude_child()` kills just the recorded
claude-dummy pid (leaves the session/pane alive, which then goes dead via `remain-on-exit`
once the wrapper's own `wait $CLAUDE_PID` returns) — do not confuse with killing the whole
tmux SESSION, which routes through the untouched empty-`NAMES` path instead and never
classifies as dead. `delete_hook_entry()` alone does NOT make a worker dead (see the
vocabulary-consequence note above) — pair it with `kill_claude_child()` for a genuine dead
fixture.

**Usage:** `bash dev/worker_wait/test_worker_wait.sh` (~5-6min; spins up/tears down
throwaway tmux sessions under `worker-<basename>-<name>`, plus throwaway `*.output` file
handles under `/tmp/claude-<uid>/`; appends to the real `wait_trace.log`, never truncates
it). Run it ONCE at a time — concurrent invocations race on the same real `hooks.json`
backup/restore cycle and can corrupt each other's in-progress fixtures (observed once
during an earlier milestone from an accidental double-invocation, not a bug in the suite
itself).
````

## Salvage from dev/worker_status/DOCS.md

````markdown
# dev/worker_status/

## Role

Tests for worker status detection (`_worker_detect_status` in `src/spawn/worker_status.sh`).

## Modules

### test_status_detection.sh (31 LOC)

**Purpose:** Verify tmux `#{pane_dead}` transitions from 0→1 after process exits (remain-on-exit mode).
**Usage:** `bash dev/worker_status/test_status_detection.sh`

### test_worker_status.sh (355 LOC)

**Purpose:** Integration coverage for the closed three-value status vocabulary
(`working`/`idle`/`dead`, 2026-09-02) that replaced `working`/`idle`/`"limit reached"`/
`unknown`. Exercises the real `_worker_detect_status` (and `worker_status`, for the
missing-session case) against real throwaway tmux sessions + a scoped `hooks.json` entry
(backed up/restored around the run, never left dirty). Fixture style copied from
`dev/worker_wait/test_worker_wait.sh` (`create_worker` idle/working/bg/chatty modes,
`go_quiet`, `kill_claude_child`, `delete_hook_entry`) — standalone copy, not an import.

Covers: `idle` from a verbatim hooks.json `idle` entry regardless of pane activity;
`working` from hook `working` with fresh (chatty) activity; the ESC-interrupt case —
hook `working` but the pane quiet > 10s — now reads as `idle` (was `"limit reached"`);
the same 10s demote rule applied to the two former `unknown` paths (no hook entry at all,
with chatty vs. quiet pane) and to a genuinely fresh spawn with no JSONL file yet at all
(`working`, the honest default); `dead` from a killed claude child (session/pane stay
alive via `remain-on-exit`), from `#{pane_dead}=1` directly, from a killed tmux SESSION
(via `worker_status`, which gates on `tmux has-session` itself before ever calling
`_worker_detect_status`), and from the session JSONL's last assistant-type entry being
Claude Code's client-side context-limit marker (`message.model=="<synthetic>"` + text
`Prompt is too long` + `isApiErrorMessage=true` + `error="invalid_request"` —
anthropics/claude-code #90113, #23377) even when hooks.json still says `idle` (dead
signals are checked before hook_status, so they take precedence). A companion case
writes an ORDINARY aborted assistant message (real model, no marker fields) to prove the
context-limit guard never false-positives on a plain ESC-interrupted turn. A final grep
assertion checks the retired strings `limit reached` and `echo "unknown"` no longer occur
anywhere in `src/spawn/worker_status.sh` (the file that defines `_worker_detect_status`; the test first asserts that definition is there, so the check cannot pass vacuously).

**JSONL marker fixture:** `write_synthetic_marker_jsonl`/`write_normal_assistant_jsonl`
overwrite the JSONL `create_worker` already touched empty, using `jq -n` to build the
JSON safely (no shell-quoting of the message text). `jsonl_path` derives the same
`~/.claude/projects/<encoded>/<session_id>.jsonl` path `_worker_detect_status` itself
resolves from `#{pane_current_path}`.

**Usage:** `bash dev/worker_status/test_worker_status.sh` (~1min; spins up/tears down
throwaway tmux sessions under `worker-<basename>-<name>`). Run it ONCE at a time — like
the wait suite, concurrent invocations race on the same real `hooks.json` backup/restore
cycle.
````

## Salvage from dev/worker_janitor/DOCS.md

````markdown
# dev/worker_janitor/

## Role

Smoke test for `worker-cli janitor` (`src/worker_cli/janitor.sh`) — the stale-worker
tmux/worktree/branch/registry cleanup sweep.

## Modules

### test_janitor.sh (127 LOC)

**Purpose:** Exercise the real `worker-cli janitor` binary against real tmux sessions in a
throwaway git repo, with `WORKER_REGISTRY_DIR`/`WORKER_LOGGER_DIR` overrides. Covers:
`--max-age-hours 0 --dry-run` listing a stale synthetic session as a candidate without
killing it; a real run (`--max-age-hours 0`) killing it end-to-end (tmux session + worktree
+ branch + registry, via the reused `kill` path) with a `janitor.log` line; a fresh synthetic
session spared by the default 12h age gate; an orphan registry entry (registry file with no
live tmux session, past the spawn-race grace window) cleaned via the same kill path.

**Tmux isolation:** `janitor` sweeps ALL `worker-*` sessions on the tmux server — unlike
`worker-cli wait`/`list` (project-scoped), there is no natural scope to keep a real-kill test
away from live sessions. The script PATH-shadows a `tmux` wrapper (`exec real-tmux -L
janitor_smoke_test_$$ "$@"`) for its own subprocess tree only: `tmux -L` spins up a fully
separate server, invisible to the default one (verified empirically — `TMUX_TMPDIR` alone
does NOT isolate when already inside a tmux session, since `$TMUX` wins). `bin/worker-cli`'s
bare `tmux` calls resolve through PATH to this wrapper transparently — zero source changes,
and the real-kill pass can never reach live state (`keep-filters`, `menubar-remote`, etc.)
even at `--max-age-hours 0` matching everything.

**Dot-in-basename gotcha:** project dirs use a dot-free subdir name (`mktemp -d`'s default
macOS `tmp.XXXXXXXX` prefix contains a `.`) — tmux silently rewrites `.`/`:` (reserved
target-spec separators) to `_` in session names, desyncing the actual live session name from
what `_worker_session_name` (`src/spawn/tmux_spawn.sh`) computes from the path's basename.
Latent in the wider spawn system too (not janitor-specific) — sidestepped here, not fixed.

**Usage:** `bash dev/worker_janitor/test_janitor.sh` (~10s; creates/kills real tmux sessions
on an isolated `-L` server + a throwaway git repo, all torn down via `trap ... EXIT`).
````

## Salvage from dev/worker_sweep_logs/DOCS.md

````markdown
# dev/worker_sweep_logs/

## Role

Smoke test for `worker-cli sweep-logs` (`src/worker_cli/cmd_lifecycle.sh`; implementation
`sweep_stale_logs` in `src/spawn/worker_log_sidecar.sh`) — the log-DIRECTORY retention sweep. Distinct
from `worker-cli janitor` (`dev/worker_janitor/`), which sweeps stale tmux WORKER SESSIONS —
the two share no code, no log file, and no naming.

## Modules

### test_sweep_logs.sh (148 LOC)

**Purpose:** Exercise the real `worker-cli sweep-logs` binary, and the real
`_start_worker_logger` auto-trigger, against a throwaway `WORKER_LOGGER_DIR`. Covers:
`--dry-run` listing a stale file without deleting it; a real run deleting a stale file while
sparing a fresh one, with a matching `log_sweep.log` line; `wait_trace.log` surviving even
`--max-age-hours 0` (it has its own line-count self-trim instead, see
`process-docs/worker_sweep_logs/`); the default threshold being 72h specifically (a 71h file
spared, a 73h file removed in the same run, no `--max-age-hours` passed); and a real
`_start_worker_logger` call sweeping a pre-existing stale file in the same directory it then
writes its own new log into — the actual spawn/revive trigger path, not just the CLI.

**Ages are faked, not waited for:** `touch -t` with the `date -v-<N>H` (macOS) /
`date -d "-<N> hours"` (GNU) fallback, same idiom as `dev/worker_janitor/test_janitor.sh`'s
own age-faking for `session_created`.

**Usage:** `bash dev/worker_sweep_logs/test_sweep_logs.sh` (a few seconds; all I/O confined to
one `mktemp -d`, torn down via `trap ... EXIT`. Never touches the real log directory).
````

## Salvage from dev/worker_merge/DOCS.md

````markdown
# dev/worker_merge/

## Role

Test for `worker-cli merge` (`src/worker_cli/cmd_lifecycle.sh`) — the merge command's
built-in outcome verification, which replaced the orchestrator's by-hand post-merge check.

## Modules

### test_merge_verify.sh (126 LOC)

**Purpose:** Exercise the real `worker-cli merge` binary against a throwaway git repo
(explicit `project_path` argument, no registry entry, no tmux). Covers a real merge
(branch with a commit) printing `=== Files merged ===` with the correct file list and
landing the merge commit; a repeat merge on the same fully-merged branch hitting the
"Already up to date" no-op path — asserts the stderr line names the no-op and both known
causes (missing `project_path` on a cross-project worker; a worker that never committed),
plus the non-zero exit code; and a genuine conflict (same file, diverging edits on both
sides) — asserts git's own `CONFLICT` text still reaches stdout and the exit code is
non-zero, guarding the `set +e` / explicit-`$?` capture around the merge call that keeps
a conflict's output from being swallowed by this script's own `set -e`.
**Usage:** `bash dev/worker_merge/test_merge_verify.sh`
````

## Salvage from dev/model_selector/DOCS.md

````markdown
# dev/model_selector/

## Role

Verification scripts for the model-selector line of work's plugin-side half (milestone 3,
cross-repo with monitor-cc): worker-model resolution in `bin/worker-cli`, `src/spawn/spawn.py`,
and the `src/spawn/` shell modules from `~/.claude/shared-rules/model_selection.json`.

## Public Interface

Both scripts are run manually, no importable interface: `bash dev/model_selector/verify_worker_model_precedence.sh`, `python3 dev/model_selector/verify_spawn_model_resolution.py`.

## Flow

No CLI input — each script drives the real `_resolve_worker_model()` (bash and Python sides respectively) against temp config paths, then prints a PASS/FAIL report to stdout (the Python side also writes its report to `md/`).

## Modules

### verify_worker_model_precedence.sh (185 LOC)

**Purpose:** Verifies the spawn library's `_resolve_worker_model()`, its 3 call-site expansion patterns (wiring checked statically in `tmux_spawn.sh` and `worker_revive.sh`), and a real `bin/worker-cli spawn` subprocess entry point.
**Reads:** nothing persistent — all config cases use a `mktemp -d` path via `MODEL_SELECTION_FILE`.
**Writes:** stdout only (no report file); real-entry-point section creates and cleans up its own tmux sessions, runner scripts, and `/tmp/worker-<name>.done` markers.
**Called by:** run manually — regression guard; re-run after any change to `_resolve_worker_model`, its 3 call sites, or the `spawn` subcommand in `src/worker_cli/cmd_lifecycle.sh`.
**Calls out:** `jq`, `tmux`, `src/spawn/tmux_spawn.sh` and `src/spawn/worker_revive.sh` (sourced / read for real), `bin/worker-cli` (invoked for real via subprocess).

---

### verify_spawn_model_resolution.py (159 LOC)

**Purpose:** Verifies `spawn.py`'s `_resolve_worker_model()` config-resolution cases and confirms argparse's omitted-arg default never leaks the string `"None"`.
**Reads:** nothing persistent — all config cases use a `tempfile.TemporaryDirectory()`.
**Writes:** `md/verify_spawn_model_resolution.md`.
**Called by:** run manually — regression guard; re-run after any change to `spawn.py`'s model resolution or argparse setup.
**Calls out:** `src/spawn/spawn.py` (loaded by path).

## State

No shared state between the two scripts — each resolves its own temp config path independently. Neither touches the real `~/.claude/shared-rules/model_selection.json` or `~/.claude/.worker-registry`.
````

## Salvage from dev/worker_message_delivery/DOCS.md

````markdown
# dev/worker_message_delivery/

## Role

Live-CC probe for text delivery into a worker tmux pane (`src/spawn/worker_io.sh`'s `worker_send` and the `spawn_claude_worker` prompt inject) — verifies bracketed-paste (`tmux paste-buffer -p`) delivers and submits complete messages on Claude Code 2.1.280, and measures paste-to-render latency against the fixed pre-Enter sleep. Runs a real `claude-280` binary (not mocked) — the bug this guards against is TUI-level paste parsing, not reproducible with a dummy command.

## Public Interface

Each script is run manually, no importable interface: `bash dev/worker_message_delivery/probe_bracketed_paste.sh`.

## Flow

No shared input — the script generates its own test messages, boots throwaway `claude-280` sessions in scratch git dirs, delivers each message through the real `worker_send()` (sourced from `src/spawn/tmux_spawn.sh`), reads the worker's own session JSONL to verify complete/correct delivery, then writes a report to `md/`.

## Modules

### probe_bracketed_paste.sh (322 LOC)

**Purpose:** Verifies bracketed-paste delivery across four message sizes plus one contrasting run of the pre-fix (no `-p`) method; measures paste-render latency.
**Reads:** `src/spawn/tmux_spawn.sh` (sourced, pulls in `worker_io.sh` for the real `worker_send`), `~/.local/bin/claude-280`.
**Writes:** stdout; throwaway tmux sessions and scratch git dirs (both removed on exit); `md/probe_bracketed_paste_report.md`.
**Called by:** run manually.
**Calls out:** tmux, git, `~/.local/bin/claude-280`, python3.

---

### _verify_user_message.py (58 LOC)

**Purpose:** Reads a worker session JSONL, extracts the last `type=="user"` entry, strips CC's `<pasted_content>` wrapper, and checks it against the expected message.
**Reads:** JSONL path and expected-message file path (argv).
**Writes:** stdout (key=value diagnostic lines); exit code 0 on exact match, 1 otherwise.
**Called by:** `probe_bracketed_paste.sh` (via subprocess).
**Calls out:** nothing (stdlib only).
````

## Salvage from dev/worker_spawn/DOCS.md

````markdown
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
````

## Salvage from dev/poread_cli/DOCS.md

````markdown
# dev/poread_cli/

## Role

Regression suite for `src/poread_cli/__main__.py`'s boundary behavior (valid file, oversize file, missing file, directory, bad argv), calling `main()` directly. Touch when changing argument handling, size-ceiling check, or marker format. The cross-repo recognition proof lives in `dev/proxy/poread_inject_tests.py (Monitor_CC)` instead.

## Public Interface

Run manually, no importable interface: `python3 dev/poread_cli/test_poread_cli.py` (from project root).

## Flow

No CLI input — drives `main()` directly against temp fixtures for each boundary case → pass/fail summary out (stdout).

## Modules

### test_poread_cli.py (122 LOC)

**Purpose:** Unit-level regression guard for `main()`'s five boundary cases, asserted against a pinned literal copy of the marker contract (not imported from the module under test).
**Reads:** nothing external — builds its own temp files/directories per test, cleans them up.
**Writes:** stdout (pass/fail via `check()`); no filesystem writes outside its own temp fixtures.
**Called by:** none — manual regression guard, re-run after any change to `src/poread_cli/__main__.py`.
**Calls out:** `src.poread_cli.__main__` (`main`).
````

## Salvage from dev/session_pipeline/DOCS.md

````markdown
# dev/session_pipeline/

## Role

Scripts for auditing and evaluating the session pipeline (`src/pipeline/`). All commands assume CWD = project root (iterative-dev/).

## Public Interface

Run manually, no importable interface: `python3 dev/session_pipeline/audit_error_patterns.py [path/to/specific.jsonl]`.

## Flow

JSONL paths in (arg, or all of `~/.claude/projects/` by default) → scans `tool_result` blocks, classifies hard/soft errors → Markdown report out (`md/error_patterns_<timestamp>.md`) + stdout summary.

## Modules

### audit_error_patterns.py (222 LOC)

**Purpose:** Scans Claude Code session JSONLs for error patterns in `tool_result` blocks — evidence for `is_tool_error()` design decisions.
**Reads:** Claude Code session JSONL files (arg, or all of `~/.claude/projects/`).
**Writes:** `dev/session_pipeline/md/error_patterns_<timestamp>.md`; stdout summary.
**Called by:** run manually.
**Calls out:** nothing (stdlib only).
````

## Salvage from dev/desktop_targeting/DOCS.md

````markdown
# dev/desktop_targeting/

## Role

Probe for macOS Space-move APIs, backing the desktop-targeting investigation (see `process-docs/desktop_targeting/`).

## Public Interface

Invoked directly: `python3 dev/desktop_targeting/probe.py [--space <id>] [--debug]`. No `__init__.py` — `objc_bridge`, `spaces`, `window_probe`, `move_test` import each other by bare module name (the script's own directory is on `sys.path[0]` for direct execution).

## Flow

CLI args in → space discovery (`spaces`) and TextEdit test-window lifecycle (`window_probe`) → CGS/SLS move + verify (`move_test`) → PASS/FAIL summary out (stdout).

## Modules

### probe.py (111 LOC)

**Purpose:** Orchestrates the space-move API probe (macOS 15.7) — tests CGS/SLS move APIs from an unprivileged process.
**Reads:** CLI args (`--space`, `--debug`).
**Writes:** stdout.
**Called by:** run manually.
**Calls out:** `objc_bridge`, `spaces`, `window_probe`, `move_test`.

---

### objc_bridge.py (121 LOC)

**Purpose:** Low-level ctypes/ObjC bridge — CoreGraphics/SkyLight library handles, `objc_msgSend` helpers, CF container accessors.
**Reads:** nothing.
**Writes:** nothing (debug lines to stdout when `_DEBUG` is set).
**Called by:** `spaces.py`, `window_probe.py`, `move_test.py`, `probe.py`.
**Calls out:** CoreGraphics.framework, SkyLight.framework (private), libobjc (via ctypes).

---

### spaces.py (70 LOC)

**Purpose:** Enumerates Mission Control Spaces per display and selects the move target (explicit `--space` override or first non-active Space on the active display).
**Reads:** live space state via `objc_bridge`.
**Writes:** stdout (Space overview).
**Called by:** `probe.py`.
**Calls out:** `objc_bridge`.

---

### window_probe.py (76 LOC)

**Purpose:** Creates, detects (before/after window-list diff), and closes the TextEdit window used as each test's move target.
**Reads:** live window list via `objc_bridge`.
**Writes:** stdout; opens/closes a real TextEdit window as a side effect.
**Called by:** `probe.py`.
**Calls out:** `objc_bridge`, `osascript`/TextEdit (via subprocess).

---

### move_test.py (85 LOC)

**Purpose:** Performs one move (CGS or SLS API) and verifies the window's resulting Space via two independent readback APIs.
**Reads:** live window/space state via `objc_bridge`.
**Writes:** stdout.
**Called by:** `probe.py`.
**Calls out:** `objc_bridge`.

## State

`objc_bridge._DEBUG` is the one piece of cross-module mutable state: `probe.py`'s `main()` sets it directly (`objc_bridge._DEBUG = args.debug`) after parsing `--debug`, rather than through a setter function — a plain module-attribute assignment, not a new public API. `objc_bridge._dbg()` reads it to decide whether to print raw API values; `window_probe.py` and `move_test.py` both call `_dbg()` but never touch the flag itself.
````

## Salvage from dev/docs_drift_check/DOCS.md

````markdown
# dev/docs_drift_check/

## Role

Regression suite for `docs-drift-check`. Runs the real wrapper against fixture projects built in isolated temp directories. Touch when changing the checks or the DOCS.md rules they encode.

## Public Interface

Run manually, no importable interface: `python3 dev/docs_drift_check/test_docs_drift_check.py` (from project root). Exit 0 = all cases passed.

## Flow

Fixture definitions → one temp project per case, all cases in parallel → wrapper invoked with the fixture as cwd → exit code and output assertions per case → pass/fail summary.

## Modules

### test_docs_drift_check.py (223 LOC)

**Purpose:** Fixture-based regression cases for path, LOC and rule checks, scope exclusions and cwd independence.
**Reads:** nothing external; builds its own temp projects.
**Writes:** stdout (pass/fail per case); no writes outside its temp fixtures.
**Called by:** none, manual regression guard.
**Calls out:** `bin/docs-drift-check` (subprocess).
````

## Salvage from dev/cc_hooks/DOCS.md

````markdown
# dev/cc_hooks/

## Role

Claude Code hook-input inspection helpers — install as a CC hook to log raw hook payloads for debugging.

## Modules

### log_permission_request.sh (8 LOC)

**Purpose:** Log Claude Code PermissionRequest hook input to file for inspection.
**Usage:** install as hook in `~/.claude/settings.json` under `hooks.PermissionRequest`; output `/tmp/permission_request_log.jsonl`
````
