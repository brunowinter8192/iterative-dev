# --- Test 5 (adapted for the transition gate; preserves the original idle+bg hold intent):
# worker observed "working" once first (brief — the pre-flip window here is short enough that
# window_activity stays fresh without chatty), THEN flips to idle WITH a genuinely open
# *.output write handle -> holds until the handle closes, exits "workers idle" only once BOTH
# the working phase and the bg-task have completed. Also covers the /tmp vs /private/tmp
# resolution gotcha unchanged: the handle is opened via the UNRESOLVED raw_tasks_dir path
# while the hook internally resolves to /private/tmp/... ---
test5_open_handle() {
    PROJ5="/tmp/${TEST_TAG}-5"
    SID5="${TEST_TAG}-sess-5"
    create_worker w1 "$PROJ5" "$SID5" working 0 >/dev/null
    TDIR_RAW=$(raw_tasks_dir "$PROJ5" "$SID5")
    TDIR_REAL=$(real_tasks_dir "$PROJ5" "$SID5")
    TASK_ID="${TEST_TAG}task5"

    case "$TDIR_REAL" in
        /private/tmp/*)
            pass "test5a tmp-resolution: real tasks dir resolves under /private/tmp ($TDIR_REAL)" ;;
        *)
            fail "test5a tmp-resolution: real tasks dir did NOT resolve under /private/tmp ($TDIR_REAL)" ;;
    esac

    start_fake_bg_task "$TDIR_RAW" "$TASK_ID"
    sleep 0.5
    OUT5_FILE="/tmp/${TEST_TAG}-5.out"
    bash "$BIN" wait "$PROJ5" --timeout 40 > "$OUT5_FILE" 2>&1 &
    P5=$!
    sleep 2
    set_hook_status "$SID5" idle "$PROJ5"
    sleep 10
    if kill -0 "$P5" 2>/dev/null; then
        pass "test5b open-handle: still waiting while .output handle open (opened via unresolved /tmp path, must be detected via the resolved /private/tmp path)"
    else
        fail "test5b open-handle: exited early while handle was still open — $(cat "$OUT5_FILE")"
    fi
    kill_fake_bg_task "$TASK_ID"
    T0=$(date +%s)
    wait "$P5"; RC5=$?
    T1=$(date +%s)
    OUT5=$(cat "$OUT5_FILE")
    ELAPSED5=$((T1 - T0))
    if [ "$OUT5" = "workers idle" ] && [ "$RC5" = 0 ] && [ "$ELAPSED5" -le 20 ]; then
        pass "test5c open-handle: exited 'workers idle' ${ELAPSED5}s after handle closed"
    else
        fail "test5c open-handle: rc=$RC5 reason='$OUT5' elapsed=${ELAPSED5}s"
    fi
    rm -f "$OUT5_FILE"
    destroy_worker w1 "$PROJ5" "$SID5"
}

# --- Test 6 (unchanged — verified compatible with the transition gate): lsof unresolvable
# mid-check (PATH stripped of /usr/sbin) -> bg-check probe error -> the idle worker's ALL_
# NONBLOCKING never reaches 1 regardless of SAW_WORKING (the probe error itself keeps it
# classified busy every poll), so this always ends in "timeout", same as before this change.
# Isolates the bg-check's OWN error path (distinct from Test 4's status-check target-vanishes
# case). ---
test6_lsof_unresolvable() {
    PROJ6="/tmp/${TEST_TAG}-6"
    SID6="${TEST_TAG}-sess-6"
    create_worker w1 "$PROJ6" "$SID6" idle 0 >/dev/null
    OUT6_FILE="/tmp/${TEST_TAG}-6.out"
    env PATH="/opt/homebrew/bin:/usr/bin:/bin" bash "$BIN" wait "$PROJ6" --timeout 12 > "$OUT6_FILE" 2>&1
    RC6=$?
    OUT6=$(cat "$OUT6_FILE")
    if [ "$OUT6" = "timeout" ] && [ "$RC6" = 0 ]; then
        pass "test6 lsof-unresolvable: final reason='$OUT6' (never 'workers idle' despite a genuinely idle, bg-task-free worker)"
    else
        fail "test6 lsof-unresolvable: rc=$RC6 reason='$OUT6' (expected 'timeout', never 'workers idle')"
    fi
    rm -f "$OUT6_FILE"
    destroy_worker w1 "$PROJ6" "$SID6"
}

# --- Test 7 (2026-08-19 incident regression, RE-PURPOSED for the working/idle/dead
# vocabulary, 2026-09-02 — verified by an actual run, not assumed): session ALIVE, no
# hooks.json entry ever populated. Under the OLD vocabulary this got stuck on a distinct
# "unknown" placeholder forever — the original incident. Under the NEW vocabulary there is
# no such stuck state: a freshly created pane with no hook data legitimately reads as
# "working" for its first ~10s (we cannot prove otherwise for a just-created pane — a
# correct default, not a misclassification), then self-heals to "idle" once quiet > 10s,
# with no orchestrator/hook data ever needed. This IS the fix for the original incident
# (self-healing beats a stuck-forever placeholder): `wait` correctly arms the gate on the
# real initial working reading and exits "workers idle" once the worker settles — it never
# needs a special terminal carve-out, and it never grinds to the timeout ceiling either.
# (The "never observed working, gate holds" proof lives in Tests 1/2/11a instead, which use
# an explicit idle hook status or no worker at all — neither goes through this shared
# fresh-pane window.) ---
test7_no_hook_self_heals() {
    PROJ7="/tmp/${TEST_TAG}-7"
    SID7="${TEST_TAG}-sess-7"
    create_worker_no_hook w1 "$PROJ7" "$SID7" >/dev/null
    TRACE_SIZE_BEFORE7=$([ -f "$TRACE_FILE" ] && wc -c < "$TRACE_FILE" || echo 0)
    T0=$(date +%s)
    OUT7=$(bash "$BIN" wait "$PROJ7" --timeout 40)
    T1=$(date +%s)
    ELAPSED7=$((T1 - T0))
    if [ "$OUT7" = "workers idle" ] && [ "$ELAPSED7" -ge 9 ] && [ "$ELAPSED7" -le 30 ]; then
        pass "test7a no-hook-entry-self-heals: reason='$OUT7' elapsed=${ELAPSED7}s"
    else
        fail "test7a no-hook-entry-self-heals: reason='$OUT7' elapsed=${ELAPSED7}s (expected 'workers idle', ~9-30s)"
    fi
    if [ -f "$TRACE_FILE" ]; then
        TRACE_NEW7=$(tail -c "+$((TRACE_SIZE_BEFORE7 + 1))" "$TRACE_FILE" | grep "project=$(basename "$PROJ7")")
        if [[ "$TRACE_NEW7" == *"status=working"* ]] && [[ "$TRACE_NEW7" == *"status=idle"* ]] \
            && [[ "$TRACE_NEW7" == *"event=exit reason=workers_idle"* ]]; then
            pass "test7b trace-self-heal: shows working polls settling to idle polls, exit reason=workers_idle"
        else
            fail "test7b trace-self-heal: got: $TRACE_NEW7"
        fi
    else
        fail "test7b trace-self-heal: $TRACE_FILE does not exist after a wait run"
    fi
    destroy_worker w1 "$PROJ7" "$SID7"
}

# --- Test 8 (adapted for the transition gate): session ALIVE, status stuck "dead"
# (#{pane_dead}=1) from the start (never observed working) -> gate holds, runs to timeout.
# The genuine "working -> killed -> dead" proof is Test 8b below. ---
test8_stuck_dead_from_start() {
    PROJ8="/tmp/${TEST_TAG}-8"
    create_worker_dead w1 "$PROJ8" >/dev/null
    T0=$(date +%s)
    OUT8=$(bash "$BIN" wait "$PROJ8" --timeout 25)
    T1=$(date +%s)
    ELAPSED8=$((T1 - T0))
    if [ "$OUT8" = "timeout" ] && [ "$ELAPSED8" -ge 25 ] && [ "$ELAPSED8" -le 32 ]; then
        pass "test8 stuck-dead-from-start: reason='$OUT8' elapsed=${ELAPSED8}s"
    else
        fail "test8 stuck-dead-from-start: reason='$OUT8' elapsed=${ELAPSED8}s (expected 'timeout', ~25-32s)"
    fi
    destroy_worker w1 "$PROJ8" "${TEST_TAG}-sess-8"
}

# --- Test 8b: worker genuinely "working" (chatty), then the claude child is killed while
# the tmux SESSION stays alive (remain-on-exit marks the pane dead once the wrapper's own
# `wait $CLAUDE_PID` returns) -> _worker_detect_status reports "dead" thereafter -> `wait`
# exits "worker dead" once stable, because a real working poll preceded the edge. Distinct
# from Test 4's session-GONE case (empty-NAMES path, never exits early, unchanged above). ---
test8b_working_then_child_killed() {
    PROJ8B="/tmp/${TEST_TAG}-8b"
    SID8B="${TEST_TAG}-sess-8b"
    create_worker w1 "$PROJ8B" "$SID8B" working 0 1 >/dev/null
    OUT8B_FILE="/tmp/${TEST_TAG}-8b.out"
    bash "$BIN" wait "$PROJ8B" --timeout 40 > "$OUT8B_FILE" 2>&1 &
    P8B=$!
    sleep 8
    T0=$(date +%s)
    kill_claude_child "$PROJ8B"
    wait "$P8B"; RC8B=$?
    T1=$(date +%s)
    OUT8B=$(cat "$OUT8B_FILE")
    ELAPSED8B=$((T1 - T0))
    if [ "$OUT8B" = "worker dead" ] && [ "$RC8B" = 0 ] && [ "$ELAPSED8B" -le 25 ]; then
        pass "test8b working-then-child-killed: reason='$OUT8B' ${ELAPSED8B}s after the edge"
    else
        fail "test8b working-then-child-killed: rc=$RC8B reason='$OUT8B' elapsed=${ELAPSED8B}s (expected 'worker dead', <=25s after edge)"
    fi
    rm -f "$OUT8B_FILE"
    destroy_worker w1 "$PROJ8B" "$SID8B"
}

# --- Test 9 (unchanged — verified compatible with the transition gate and the
# working/idle/dead vocabulary): mixed project — one worker dead (#{pane_dead}=1) from the
# start, one worker genuinely "working" (fresh window_activity at creation covers this
# test's short 5s pre-flip window without chatty) -> `wait` must NOT exit early (dead folds
# into "non-blocking" but a real busy worker still blocks; SAW_WORKING is set from wB's very
# first poll). Once the working worker finishes (flipped to idle), `wait` exits "worker
# dead" (not "workers idle") because the dead worker is still there — validates fold-in +
# exit-line precedence together, now with the gate already satisfied from wB's early
# working poll. ---
test9_mixed_dead_and_working() {
    PROJ9="/tmp/${TEST_TAG}-9"
    SID9B="${TEST_TAG}-sess-9b"
    create_worker_dead wA "$PROJ9" >/dev/null
    create_worker wB "$PROJ9" "$SID9B" working 0 >/dev/null
    OUT9_FILE="/tmp/${TEST_TAG}-9.out"
    bash "$BIN" wait "$PROJ9" --timeout 40 > "$OUT9_FILE" 2>&1 &
    P9=$!
    sleep 5
    if kill -0 "$P9" 2>/dev/null; then
        pass "test9a mixed-still-blocks: wait process still alive after 5s (dead worker did not short-circuit the still-busy worker)"
    else
        fail "test9a mixed-still-blocks: wait process already exited early — $(cat "$OUT9_FILE")"
    fi
    set_hook_status "$SID9B" idle "$PROJ9"
    T0=$(date +%s)
    wait "$P9"; RC9=$?
    T1=$(date +%s)
    OUT9=$(cat "$OUT9_FILE")
    ELAPSED9=$((T1 - T0))
    if [ "$OUT9" = "worker dead" ] && [ "$RC9" = 0 ] && [ "$ELAPSED9" -le 25 ]; then
        pass "test9b mixed-exit-precedence: exited 'worker dead' ${ELAPSED9}s after the busy worker went idle (not 'workers idle')"
    else
        fail "test9b mixed-exit-precedence: rc=$RC9 reason='$OUT9' elapsed=${ELAPSED9}s (expected 'worker dead')"
    fi
    rm -f "$OUT9_FILE"
    destroy_worker wA "$PROJ9" "${TEST_TAG}-sess-9a"
    destroy_worker wB "$PROJ9" "$SID9B"
}

# --- Test 10 (adapted for the transition gate AND the working/idle/dead vocabulary;
# preserves the original bg-skipped-for-dead intent): worker observed "working" once
# first, THEN the claude child is killed (pane goes dead via remain-on-exit — the SAME real
# dead signal Test 8b uses) AND the hooks.json entry is separately deleted (session/process
# alike show no live hook data — a realistic dead-and-orphaned shape) WHILE a genuinely open
# *.output write handle stays open throughout -> still exits "worker dead" promptly once
# stable, NOT held open until the handle closes — regression-guards the deliberate design
# decision to skip the bg-task probe for dead statuses (unlike Test 5's idle+bg case, which
# DOES hold). NOTE: a deleted hook entry ALONE is no longer a dead signal under the new
# vocabulary (see delete_hook_entry's doc comment) — kill_claude_child is what actually
# produces "dead" here. ---
test10_dead_with_open_bg_handle() {
    PROJ10="/tmp/${TEST_TAG}-10"
    SID10="${TEST_TAG}-sess-10"
    create_worker w1 "$PROJ10" "$SID10" working 0 >/dev/null
    TDIR_RAW10=$(raw_tasks_dir "$PROJ10" "$SID10")
    TASK_ID10="${TEST_TAG}task10"
    start_fake_bg_task "$TDIR_RAW10" "$TASK_ID10"
    sleep 0.5
    OUT10_FILE="/tmp/${TEST_TAG}-10.out"
    bash "$BIN" wait "$PROJ10" --timeout 40 > "$OUT10_FILE" 2>&1 &
    P10=$!
    sleep 2
    delete_hook_entry "$SID10"
    kill_claude_child "$PROJ10"
    T0=$(date +%s)
    wait "$P10"; RC10=$?
    T1=$(date +%s)
    OUT10=$(cat "$OUT10_FILE")
    ELAPSED10=$((T1 - T0))
    if [ "$OUT10" = "worker dead" ] && [ "$RC10" = 0 ] && [ "$ELAPSED10" -le 25 ]; then
        pass "test10 working-then-dead-bg-open: reason='$OUT10' ${ELAPSED10}s after the edge (open handle correctly ignored for a dead worker)"
    else
        fail "test10 working-then-dead-bg-open: rc=$RC10 reason='$OUT10' elapsed=${ELAPSED10}s (expected 'worker dead', <=25s after edge)"
    fi
    kill_fake_bg_task "$TASK_ID10"
    rm -f "$OUT10_FILE"
    destroy_worker w1 "$PROJ10" "$SID10"
}

# --- Test 11 (New Case 6): `wait` armed while the worker is already idle (no prior working)
# -> keeps running through the idle-from-arm phase (proven via a mid-run liveness check well
# past the old 15s early-exit threshold), THEN the worker becomes genuinely "working" (chatty,
# so window_activity stays fresh despite the flip happening long after creation), THEN idle
# again -> exits "workers idle" only after that SECOND transition, never on the first idle
# phase. ---
test11_second_transition_exits() {
    PROJ11="/tmp/${TEST_TAG}-11"
    SID11="${TEST_TAG}-sess-11"
    create_worker w1 "$PROJ11" "$SID11" idle 0 1 >/dev/null
    OUT11_FILE="/tmp/${TEST_TAG}-11.out"
    bash "$BIN" wait "$PROJ11" --timeout 60 > "$OUT11_FILE" 2>&1 &
    P11=$!
    sleep 18
    if kill -0 "$P11" 2>/dev/null; then
        pass "test11a armed-while-idle: still waiting after 18s of idle-from-arm (no prior working, gate correctly holds)"
    else
        fail "test11a armed-while-idle: exited early during the idle-from-arm phase — $(cat "$OUT11_FILE")"
    fi
    set_hook_status "$SID11" working "$PROJ11"
    sleep 7
    set_hook_status "$SID11" idle "$PROJ11"
    go_quiet "$PROJ11"
    T0=$(date +%s)
    wait "$P11"; RC11=$?
    T1=$(date +%s)
    OUT11=$(cat "$OUT11_FILE")
    ELAPSED11=$((T1 - T0))
    if [ "$OUT11" = "workers idle" ] && [ "$RC11" = 0 ] && [ "$ELAPSED11" -le 25 ]; then
        pass "test11b second-transition-exits: reason='$OUT11' ${ELAPSED11}s after the working->idle edge (not the first idle phase)"
    else
        fail "test11b second-transition-exits: rc=$RC11 reason='$OUT11' elapsed=${ELAPSED11}s (expected 'workers idle', <=25s after the SECOND edge)"
    fi
    rm -f "$OUT11_FILE"
    destroy_worker w1 "$PROJ11" "$SID11"
}
