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
