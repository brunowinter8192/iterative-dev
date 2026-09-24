#!/bin/bash
# Integration tests for `worker-cli wait` (bin/worker-cli, wait case).
# Exercises the REAL worker-cli binary + REAL tmux_spawn.sh status detection against
# throwaway tmux sessions + a scoped hooks.json entry (backed up/restored, never left
# dirty). Run: bash dev/worker_wait/test_worker_wait.sh
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
BIN="$PLUGIN_ROOT/bin/worker-cli"
RESULT=0
TEST_TAG="waittest$$"

export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

source "$SELF_DIR/fixtures.sh"
source "$SELF_DIR/tests_gate.sh"
source "$SELF_DIR/tests_transitions.sh"

cleanup_all() {
    destroy_worker w1 "/tmp/${TEST_TAG}-1" "${TEST_TAG}-sess-1" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-1b" "${TEST_TAG}-sess-1b" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-3" "${TEST_TAG}-sess-3" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-3b" "${TEST_TAG}-sess-3b" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-4" "${TEST_TAG}-sess-4" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-5" "${TEST_TAG}-sess-5" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-6" "${TEST_TAG}-sess-6" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-7" "${TEST_TAG}-sess-7" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-8" "${TEST_TAG}-sess-8" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-8b" "${TEST_TAG}-sess-8b" 2>/dev/null || true
    destroy_worker wA "/tmp/${TEST_TAG}-9" "${TEST_TAG}-sess-9a" 2>/dev/null || true
    destroy_worker wB "/tmp/${TEST_TAG}-9" "${TEST_TAG}-sess-9b" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-10" "${TEST_TAG}-sess-10" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-11" "${TEST_TAG}-sess-11" 2>/dev/null || true
    kill_fake_bg_task "${TEST_TAG}task5" 2>/dev/null || true
    kill_fake_bg_task "${TEST_TAG}task10" 2>/dev/null || true
    restore_hooks
}
trap cleanup_all EXIT

backup_hooks

echo "=== worker-cli wait — integration tests ==="
echo "(2026-09-02 transition-gate change: 'wait' may only exit idle/dead after observing a"
echo " real 'working' poll in THIS invocation — see bin/worker-cli wait case + SAW_WORKING)"

test1_idle_from_start
test1c_trace_observability
test1b_tooling_child_incident
test2_no_worker_never_exits
test2b_timeout_short
test3_working_then_idle_edge
test3b_concurrent_wait
test4_probe_vanishes
test5_open_handle
test6_lsof_unresolvable
test7_no_hook_self_heals
test8_stuck_dead_from_start
test8b_working_then_child_killed
test9_mixed_dead_and_working
test10_dead_with_open_bg_handle
test11_second_transition_exits

echo "=== $([ $RESULT -eq 0 ] && echo ALL PASSED || echo SOME FAILED) ==="
exit $RESULT
