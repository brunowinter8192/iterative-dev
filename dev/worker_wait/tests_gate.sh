# --- Test 1 (transition-gate core proof, New Case 1): idle worker FROM THE START, never
# observed "working" in this invocation -> must NOT exit "workers idle"; runs to timeout.
# Was: "idle worker -> exits promptly, reason 'workers idle'" (the pre-gate, level-triggered
# contract) — an idle-at-arm worker no longer looks like a finished transition. ---
test1_idle_from_start() {
    PROJ1="/tmp/${TEST_TAG}-1"
    SID1="${TEST_TAG}-sess-1"
    create_worker w1 "$PROJ1" "$SID1" idle 0 >/dev/null
    TRACE_SIZE_BEFORE1=$([ -f "$TRACE_FILE" ] && wc -c < "$TRACE_FILE" || echo 0)
    T0=$(date +%s)
    OUT1=$(bash "$BIN" wait "$PROJ1" --timeout 25)
    T1=$(date +%s)
    ELAPSED1=$((T1 - T0))
    if [ "$OUT1" = "timeout" ] && [ "$ELAPSED1" -ge 25 ] && [ "$ELAPSED1" -le 32 ]; then
        pass "test1 idle-from-start-never-exits: reason='$OUT1' elapsed=${ELAPSED1}s"
    else
        fail "test1 idle-from-start-never-exits: reason='$OUT1' elapsed=${ELAPSED1}s (expected 'timeout', ~25-32s)"
    fi
}

# --- Test 1c (C1, 2026-08-18, adapted): trace shows the run started, never observed a
# "working" poll (saw_working never reaches 1), and exited on the timeout ceiling. ---
test1c_trace_observability() {
    if [ -f "$TRACE_FILE" ]; then
        # Scoped to THIS test's project tag — the trace file is shared with any concurrently
        # running real `wait` invocation on the machine, whose own lines (different project=)
        # would otherwise pollute a byte-offset-only diff.
        TRACE_NEW1=$(tail -c "+$((TRACE_SIZE_BEFORE1 + 1))" "$TRACE_FILE" | grep "project=$(basename "$PROJ1")")
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

# --- Test 1b (2026-08 incident regression, adapted for the transition gate): worker starts
# genuinely "working" WITH a persistent tooling grandchild (never killed) — observed working
# at least once — then flips to idle -> exits "workers idle" promptly once stable. Preserves
# BOTH the original grandchild-ignored-by-the-bg-probe regression AND proves the gate
# correctly unlocks after a real working poll (window_activity is fresh at t=0, well inside
# the 2s pre-flip window here, so no chatty loop is needed for this brief a working phase). ---
test1b_tooling_child_incident() {
    PROJ1B="/tmp/${TEST_TAG}-1b"
    SID1B="${TEST_TAG}-sess-1b"
    create_worker w1 "$PROJ1B" "$SID1B" working 1 >/dev/null
    OUT1B_FILE="/tmp/${TEST_TAG}-1b.out"
    bash "$BIN" wait "$PROJ1B" --timeout 40 > "$OUT1B_FILE" 2>&1 &
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

# --- Test 2 (transition-gate core proof, New Case 2): no worker EVER registered for this
# project -> the removed "no workers" fast-exit must never fire; `wait` just keeps polling an
# empty roster (a non-exiting state, same as idle-from-start above) until the timeout ceiling.
# Was: "no worker ever registered + long timeout -> fast-exits 'no workers'" (the C3,
# 2026-08-18 contract this supersedes) — that whole exit path is now removed entirely. ---
test2_no_worker_never_exits() {
    T0=$(date +%s)
    OUT2=$(bash "$BIN" wait "/tmp/${TEST_TAG}-nonexistent" --timeout 25)
    T1=$(date +%s)
    ELAPSED2=$((T1 - T0))
    if [ "$OUT2" = "timeout" ] && [ "$ELAPSED2" -ge 25 ] && [ "$ELAPSED2" -le 32 ]; then
        pass "test2 no-worker-never-exits: reason='$OUT2' elapsed=${ELAPSED2}s"
    else
        fail "test2 no-worker-never-exits: reason='$OUT2' elapsed=${ELAPSED2}s (expected 'timeout', ~25-32s, never 'no workers')"
    fi
}

# --- Test 2b: short timeout with zero workers -> ordinary timeout. The old "two exit paths
# don't interfere" rationale no longer applies (there is only ONE exit path for an empty
# roster now: the timeout ceiling) — kept as a minimal short-timeout smoke test. ---
test2b_timeout_short() {
    T0=$(date +%s)
    OUT2B=$(bash "$BIN" wait "/tmp/${TEST_TAG}-nonexistent-2b" --timeout 3)
    T1=$(date +%s)
    ELAPSED2B=$((T1 - T0))
    if [ "$OUT2B" = "timeout" ] && [ "$ELAPSED2B" -ge 3 ] && [ "$ELAPSED2B" -le 10 ]; then
        pass "test2b timeout-short: reason='$OUT2B' elapsed=${ELAPSED2B}s"
    else
        fail "test2b timeout-short: reason='$OUT2B' elapsed=${ELAPSED2B}s (expected 'timeout', 3-10s)"
    fi
}

# --- Test 3 (New Case 3): worker genuinely "working" (chatty, keeps #{window_activity} fresh)
# for ~10s, then goes quiet and edges to idle -> exits "workers idle" within the existing
# 3-sample/5s-poll stability window after the edge. Core positive-path proof of the transition
# gate: a real working phase DOES unlock the exit. ---
test3_working_then_idle_edge() {
    PROJ3="/tmp/${TEST_TAG}-3"
    SID3="${TEST_TAG}-sess-3"
    create_worker w1 "$PROJ3" "$SID3" working 0 1 >/dev/null
    OUT3_FILE="/tmp/${TEST_TAG}-3.out"
    bash "$BIN" wait "$PROJ3" --timeout 40 > "$OUT3_FILE" 2>&1 &
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

# --- Test 3b (New Case 5, was Test 3 "concurrent-wait", adapted): two concurrent `wait`
# processes both armed during a genuine working phase (chatty) -> both must exit "workers
# idle" together on the same edge. ---
test3b_concurrent_wait() {
    PROJ3B="/tmp/${TEST_TAG}-3b"
    SID3B="${TEST_TAG}-sess-3b"
    create_worker w1 "$PROJ3B" "$SID3B" working 0 1 >/dev/null
    OUT3BA_FILE="/tmp/${TEST_TAG}-3ba.out"
    OUT3BB_FILE="/tmp/${TEST_TAG}-3bb.out"
    bash "$BIN" wait "$PROJ3B" --timeout 40 > "$OUT3BA_FILE" 2>&1 &
    P3BA=$!
    bash "$BIN" wait "$PROJ3B" --timeout 40 > "$OUT3BB_FILE" 2>&1 &
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

# --- Test 4 (unchanged — verified compatible with the transition gate): probe target
# vanishes mid-wait (hard failure). The vanished-SESSION path routes entirely through the
# empty-NAMES branch, which has no exit condition of its own regardless of SAW_WORKING ->
# always ends in "timeout", same as before this change. ---
test4_probe_vanishes() {
    PROJ4="/tmp/${TEST_TAG}-4"
    SID4="${TEST_TAG}-sess-4"
    create_worker w1 "$PROJ4" "$SID4" working 0 >/dev/null
    OUT4_FILE="/tmp/${TEST_TAG}-4.out"
    bash "$BIN" wait "$PROJ4" --timeout 12 > "$OUT4_FILE" 2>&1 &
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
