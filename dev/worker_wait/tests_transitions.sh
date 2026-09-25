# FUNCTIONS

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
    ( cd "$PROJ5" && exec bash "$BIN" wait --timeout 40 > "$OUT5_FILE" 2>&1 ) &
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

test6_lsof_unresolvable() {
    PROJ6="/tmp/${TEST_TAG}-6"
    SID6="${TEST_TAG}-sess-6"
    create_worker w1 "$PROJ6" "$SID6" idle 0 >/dev/null
    OUT6_FILE="/tmp/${TEST_TAG}-6.out"
    ( cd "$PROJ6" && exec env PATH="$STRAND_DIR/bin:/opt/homebrew/bin:/usr/bin:/bin" bash "$BIN" wait --timeout 12 > "$OUT6_FILE" 2>&1 )
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

test7_no_hook_self_heals() {
    PROJ7="/tmp/${TEST_TAG}-7"
    SID7="${TEST_TAG}-sess-7"
    create_worker_no_hook w1 "$PROJ7" "$SID7" >/dev/null
    T0=$(date +%s)
    OUT7=$(cd "$PROJ7" && bash "$BIN" wait --timeout 40)
    T1=$(date +%s)
    ELAPSED7=$((T1 - T0))
    if [ "$OUT7" = "workers idle" ] && [ "$ELAPSED7" -ge 9 ] && [ "$ELAPSED7" -le 30 ]; then
        pass "test7a no-hook-entry-self-heals: reason='$OUT7' elapsed=${ELAPSED7}s"
    else
        fail "test7a no-hook-entry-self-heals: reason='$OUT7' elapsed=${ELAPSED7}s (expected 'workers idle', ~9-30s)"
    fi
    if [ -f "$TRACE_FILE" ]; then
        TRACE_NEW7=$(grep "project=$(basename "$PROJ7")" "$TRACE_FILE")
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

test8_stuck_dead_from_start() {
    PROJ8="/tmp/${TEST_TAG}-8"
    create_worker_dead w1 "$PROJ8" >/dev/null
    T0=$(date +%s)
    OUT8=$(cd "$PROJ8" && bash "$BIN" wait --timeout 25)
    T1=$(date +%s)
    ELAPSED8=$((T1 - T0))
    if [ "$OUT8" = "timeout" ] && [ "$ELAPSED8" -ge 25 ] && [ "$ELAPSED8" -le 32 ]; then
        pass "test8 stuck-dead-from-start: reason='$OUT8' elapsed=${ELAPSED8}s"
    else
        fail "test8 stuck-dead-from-start: reason='$OUT8' elapsed=${ELAPSED8}s (expected 'timeout', ~25-32s)"
    fi
    destroy_worker w1 "$PROJ8" "${TEST_TAG}-sess-8"
}

test8b_working_then_child_killed() {
    PROJ8B="/tmp/${TEST_TAG}-8b"
    SID8B="${TEST_TAG}-sess-8b"
    create_worker w1 "$PROJ8B" "$SID8B" working 0 1 >/dev/null
    OUT8B_FILE="/tmp/${TEST_TAG}-8b.out"
    ( cd "$PROJ8B" && exec bash "$BIN" wait --timeout 40 > "$OUT8B_FILE" 2>&1 ) &
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

test9_mixed_dead_and_working() {
    PROJ9="/tmp/${TEST_TAG}-9"
    SID9B="${TEST_TAG}-sess-9b"
    create_worker_dead wA "$PROJ9" >/dev/null
    create_worker wB "$PROJ9" "$SID9B" working 0 >/dev/null
    OUT9_FILE="/tmp/${TEST_TAG}-9.out"
    ( cd "$PROJ9" && exec bash "$BIN" wait --timeout 40 > "$OUT9_FILE" 2>&1 ) &
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

test10_dead_with_open_bg_handle() {
    PROJ10="/tmp/${TEST_TAG}-10"
    SID10="${TEST_TAG}-sess-10"
    create_worker w1 "$PROJ10" "$SID10" working 0 >/dev/null
    TDIR_RAW10=$(raw_tasks_dir "$PROJ10" "$SID10")
    TASK_ID10="${TEST_TAG}task10"
    start_fake_bg_task "$TDIR_RAW10" "$TASK_ID10"
    sleep 0.5
    OUT10_FILE="/tmp/${TEST_TAG}-10.out"
    ( cd "$PROJ10" && exec bash "$BIN" wait --timeout 40 > "$OUT10_FILE" 2>&1 ) &
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

test11_second_transition_exits() {
    PROJ11="/tmp/${TEST_TAG}-11"
    SID11="${TEST_TAG}-sess-11"
    create_worker w1 "$PROJ11" "$SID11" idle 0 1 >/dev/null
    OUT11_FILE="/tmp/${TEST_TAG}-11.out"
    ( cd "$PROJ11" && exec bash "$BIN" wait --timeout 60 > "$OUT11_FILE" 2>&1 ) &
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
