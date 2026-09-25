# FUNCTIONS

test1_idle_from_start() {
    PROJ1="/tmp/${TEST_TAG}-1"
    SID1="${TEST_TAG}-sess-1"
    create_worker w1 "$PROJ1" "$SID1" idle 0 >/dev/null
    T0=$(date +%s)
    OUT1=$(cd "$PROJ1" && bash "$BIN" wait --timeout 25)
    T1=$(date +%s)
    ELAPSED1=$((T1 - T0))
    if [ "$OUT1" = "timeout" ] && [ "$ELAPSED1" -ge 25 ] && [ "$ELAPSED1" -le 32 ]; then
        pass "test1 idle-from-start-never-exits: reason='$OUT1' elapsed=${ELAPSED1}s"
    else
        fail "test1 idle-from-start-never-exits: reason='$OUT1' elapsed=${ELAPSED1}s (expected 'timeout', ~25-32s)"
    fi
}

test1c_trace_observability() {
    if [ -f "$TRACE_FILE" ]; then
        TRACE_NEW1=$(grep "project=$(basename "$PROJ1")" "$TRACE_FILE")
        if [[ "$TRACE_NEW1" == *"event=start"* ]] && [[ "$TRACE_NEW1" == *"event=exit reason=timeout"* ]] \
            && [[ "$TRACE_NEW1" != *"saw_working=1"* ]]; then
            pass "test1c trace-observability: event=start + event=exit reason=timeout, saw_working never 1"
        else
            fail "test1c trace-observability: got: $TRACE_NEW1"
        fi
    else
        fail "test1c trace-observability: $TRACE_FILE does not exist after a wait run"
    fi
    destroy_worker w1 "$PROJ1" "$SID1"
}

test1b_tooling_child_incident() {
    PROJ1B="/tmp/${TEST_TAG}-1b"
    SID1B="${TEST_TAG}-sess-1b"
    create_worker w1 "$PROJ1B" "$SID1B" working 1 >/dev/null
    OUT1B_FILE="/tmp/${TEST_TAG}-1b.out"
    ( cd "$PROJ1B" && exec bash "$BIN" wait --timeout 40 > "$OUT1B_FILE" 2>&1 ) &
    P1B=$!
    sleep 2
    set_hook_status "$SID1B" idle "$PROJ1B"
    T0=$(date +%s)
    wait "$P1B"; RC1B=$?
    T1=$(date +%s)
    OUT1B=$(cat "$OUT1B_FILE")
    ELAPSED1B=$((T1 - T0))
    if [ "$OUT1B" = "workers idle" ] && [ "$RC1B" = 0 ] && [ "$ELAPSED1B" -le 25 ]; then
        pass "test1b tooling-child-incident: reason='$OUT1B' ${ELAPSED1B}s after the idle edge (persistent grandchild correctly ignored)"
    else
        fail "test1b tooling-child-incident: rc=$RC1B reason='$OUT1B' elapsed=${ELAPSED1B}s (expected 'workers idle', <=25s after edge)"
    fi
    rm -f "$OUT1B_FILE"
    destroy_worker w1 "$PROJ1B" "$SID1B"
}

test2_no_worker_never_exits() {
    T0=$(date +%s)
    mkdir -p "/tmp/${TEST_TAG}-nonexistent"
    OUT2=$(cd "/tmp/${TEST_TAG}-nonexistent" && bash "$BIN" wait --timeout 25)
    T1=$(date +%s)
    ELAPSED2=$((T1 - T0))
    if [ "$OUT2" = "timeout" ] && [ "$ELAPSED2" -ge 25 ] && [ "$ELAPSED2" -le 32 ]; then
        pass "test2 no-worker-never-exits: reason='$OUT2' elapsed=${ELAPSED2}s"
    else
        fail "test2 no-worker-never-exits: reason='$OUT2' elapsed=${ELAPSED2}s (expected 'timeout', ~25-32s, never 'no workers')"
    fi
}

test2b_timeout_short() {
    T0=$(date +%s)
    mkdir -p "/tmp/${TEST_TAG}-nonexistent-2b"
    OUT2B=$(cd "/tmp/${TEST_TAG}-nonexistent-2b" && bash "$BIN" wait --timeout 3)
    T1=$(date +%s)
    ELAPSED2B=$((T1 - T0))
    if [ "$OUT2B" = "timeout" ] && [ "$ELAPSED2B" -ge 3 ] && [ "$ELAPSED2B" -le 10 ]; then
        pass "test2b timeout-short: reason='$OUT2B' elapsed=${ELAPSED2B}s"
    else
        fail "test2b timeout-short: reason='$OUT2B' elapsed=${ELAPSED2B}s (expected 'timeout', 3-10s)"
    fi
}

test3_working_then_idle_edge() {
    PROJ3="/tmp/${TEST_TAG}-3"
    SID3="${TEST_TAG}-sess-3"
    create_worker w1 "$PROJ3" "$SID3" working 0 1 >/dev/null
    OUT3_FILE="/tmp/${TEST_TAG}-3.out"
    ( cd "$PROJ3" && exec bash "$BIN" wait --timeout 40 > "$OUT3_FILE" 2>&1 ) &
    P3=$!
    sleep 10
    go_quiet "$PROJ3"
    set_hook_status "$SID3" idle "$PROJ3"
    T0=$(date +%s)
    wait "$P3"; RC3=$?
    T1=$(date +%s)
    OUT3=$(cat "$OUT3_FILE")
    ELAPSED3=$((T1 - T0))
    if [ "$OUT3" = "workers idle" ] && [ "$RC3" = 0 ] && [ "$ELAPSED3" -le 20 ]; then
        pass "test3 working-then-idle-edge: reason='$OUT3' ${ELAPSED3}s after the edge"
    else
        fail "test3 working-then-idle-edge: rc=$RC3 reason='$OUT3' elapsed=${ELAPSED3}s (expected 'workers idle', <=20s after edge)"
    fi
    rm -f "$OUT3_FILE"
    destroy_worker w1 "$PROJ3" "$SID3"
}

test3b_concurrent_wait() {
    PROJ3B="/tmp/${TEST_TAG}-3b"
    SID3B="${TEST_TAG}-sess-3b"
    create_worker w1 "$PROJ3B" "$SID3B" working 0 1 >/dev/null
    OUT3BA_FILE="/tmp/${TEST_TAG}-3ba.out"
    OUT3BB_FILE="/tmp/${TEST_TAG}-3bb.out"
    ( cd "$PROJ3B" && exec bash "$BIN" wait --timeout 40 > "$OUT3BA_FILE" 2>&1 ) &
    P3BA=$!
    ( cd "$PROJ3B" && exec bash "$BIN" wait --timeout 40 > "$OUT3BB_FILE" 2>&1 ) &
    P3BB=$!
    sleep 8
    go_quiet "$PROJ3B"
    set_hook_status "$SID3B" idle "$PROJ3B"
    wait "$P3BA"; RC3BA=$?
    wait "$P3BB"; RC3BB=$?
    OUT3BA=$(cat "$OUT3BA_FILE"); OUT3BB=$(cat "$OUT3BB_FILE")
    if [ "$RC3BA" = 0 ] && [ "$RC3BB" = 0 ] && [ "$OUT3BA" = "workers idle" ] && [ "$OUT3BB" = "workers idle" ]; then
        pass "test3b concurrent-wait-during-working: both exited 0 with 'workers idle'"
    else
        fail "test3b concurrent-wait-during-working: rc=($RC3BA,$RC3BB) out=('$OUT3BA','$OUT3BB')"
    fi
    rm -f "$OUT3BA_FILE" "$OUT3BB_FILE"
    destroy_worker w1 "$PROJ3B" "$SID3B"
}

test4_probe_vanishes() {
    PROJ4="/tmp/${TEST_TAG}-4"
    SID4="${TEST_TAG}-sess-4"
    create_worker w1 "$PROJ4" "$SID4" working 0 >/dev/null
    OUT4_FILE="/tmp/${TEST_TAG}-4.out"
    ( cd "$PROJ4" && exec bash "$BIN" wait --timeout 12 > "$OUT4_FILE" 2>&1 ) &
    P4=$!
    sleep 3
    SESSION4="worker-$(basename "$PROJ4")-w1"
    tmux kill-session -t "$SESSION4" 2>/dev/null || true
    sleep 1
    if kill -0 "$P4" 2>/dev/null; then
        pass "test4a probe-vanishes: wait process still alive immediately after target killed"
    else
        fail "test4a probe-vanishes: wait process already exited (early exit!) right after target killed"
    fi
    wait "$P4"; RC4=$?
    OUT4=$(cat "$OUT4_FILE")
    if [ "$OUT4" = "timeout" ] && [ "$RC4" = 0 ]; then
        pass "test4b probe-vanishes: final reason='$OUT4' (never 'workers idle')"
    else
        fail "test4b probe-vanishes: rc=$RC4 reason='$OUT4' (expected 'timeout', never 'workers idle')"
    fi
    rm -f "$OUT4_FILE"
    destroy_worker w1 "$PROJ4" "$SID4"
}
