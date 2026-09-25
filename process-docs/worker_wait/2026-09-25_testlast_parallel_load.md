# testlast: dev suites under parallel load (2026-09-25, base integration)

Task: dev/worker_wait and dev/worker_spawn/test_spawn_flow.sh must give the same result when all shell suites run at once. Only dev/ changed; src/ untouched.

## Reproduction (12 shell files at once: every dev/*/test_*.sh and verify_*.sh)

Before the fix, one run: test_spawn_flow failed 2 of 3 strands (`open_tmux_viewer took 15s (should be <5s)`, `spawn took 14766ms (<10s)`), test_worker_wait failed t2b (`elapsed=14s (expected 3-10s)` for `--timeout 3`). The other suites passed. wcli's earlier run failed t4, t5, t10 instead: the failing strands change from run to run.

## Causes (both confirmed by reading code and by the fix)

1. Fixed wall-clock upper bounds. wait.sh checks its timeout once per loop; each loop is a fresh `bash -c "source ..."` for worker_list plus `sleep 5`, so under load a `--timeout 3` wait returns after 14s. The viewer strand only calls three stubs and still took 15s because process startup itself is slow under load.
2. Fixed sleeps that assume the wait process has polled by then. Worker fixtures with hook status `working` and a silent pane are demoted to `idle` once the pane is quiet for 10s (`#{window_activity}`). If the first poll of `wait` comes later than 10s after creation, `saw_working` is never set and the wait can only end in `timeout`. This is why t4, t5, t10 (plain silent fixtures, `sleep 2/3` before the edge) failed for wcli, and t7 (no-hook fixture, self-heal depends on the first ~10s of fresh activity) had the same weakness.

## What changed

- fixtures.sh: `require_trace label pattern [count]` polls the strand's private `wait_trace.log` (bounded, `TRACE_WAIT_BOUND` 120s) until a pattern shows N times, otherwise `fail`. Example pattern: `pid=$P3 .*status=working` (the tag is `pid=<pid> project=...`, and `$!` of `( ... exec bash worker-cli wait ) &` equals the `$$` inside cmd_wait). `wait_for_file` replaces `sleep 0.5` after `start_fake_bg_task` (the redirect that creates the .output file holds the handle open, so the file existing means the handle is open).
- Fixtures now chatty where the test needs `working` to persist: wrap_bg prints a tick every second (still keeps the pyright-langserver-dummy grandchild), no-hook wrapper uses the chatty script (`write_chatty_script` shared), t4, t5, t9, t10 create the worker with the chatty flag. A chatty pane keeps `working` fresh, so the edge no longer depends on when the first poll happens. Hook `idle` still wins over pane activity, so chatty fixtures do not disturb the idle assertions.
- Fixed sleeps replaced by trace waits: t1b, t3, t3b, t5, t8b, t9, t10, t11 wait for `status=working` (or N idle polls) instead of `sleep 2/8/10/18/7`. "Still waiting" checks (t4a, t5b, t9a, t11a) check aliveness after the trace shows the polls that would have exited: t4 waits for `empty=1`, t5 for 4x `status=idle bg=yes`, t9 for 2 working polls, t11 for 5x `status=idle bg=no`. Test t7 waits for `working`, then `go_quiet`, then expects `workers idle`; its `9-30s` window is gone.
- Upper bounds are hang guards: `timeout + HANG_GUARD` (90) for pure timeout waits, `<= HANG_GUARD` after an edge. Lower bounds (`>= timeout`) stay, they do not depend on load. Waits that need the trace gates use `--timeout 150` (`WAIT_CEILING`), t4 uses 60.
- test_spawn_flow: the 5s and 10s windows guarded against the viewer blocking spawn. The spawn strand now installs an osascript stub that logs, writes its pid and blocks until a release file exists; the strand asserts the stub is still alive after `spawn_claude_worker` returned (spawn does not wait for the viewer), then releases it. The viewer strand only asserts the call log. `sleep 1` before capture-pane and `sleep 0.5` after the proxy kill became bounded polls (`poll_until`, 60s).

## Verification (2026-09-25)

Alone: test_spawn_flow 3/3, test_worker_wait 15/15 (wall 63s, t4 63s by its 60s timeout).
Five full parallel runs of all 12 files, number fixed before the run (the failure showed up in 5 of 18 strands once; 5 clean runs make a remaining flake of that size very unlikely). Result: 5 of 5 runs, 12 of 12 files rc=0 each. test_worker_wait wall 66, 69, 67, 68, 67s; test_spawn_flow 16, 16, 15, 15, 15s.

## Notes for a successor

- The wait suite got slower (about 65s wall instead of 41s) because gates now wait for real polls and t4 waits for its 60s timeout.
- A remaining load-sensitive spot not touched because never observed: the 15s deadline in `_worker_proxy_wait_ready` (src). The spawn strand took 15s in parallel runs without failing.
- Rule to keep: never assert an upper bound on how fast something happens under load; assert order (event seen, then check) and use a large hang guard.
