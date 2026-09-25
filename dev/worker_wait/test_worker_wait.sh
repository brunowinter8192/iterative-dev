#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
BIN="$PLUGIN_ROOT/bin/worker-cli"

export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

source "$SELF_DIR/../strand_runner.sh"
source "$SELF_DIR/fixtures.sh"
source "$SELF_DIR/tests_gate.sh"
source "$SELF_DIR/tests_transitions.sh"

STRANDS=(t1 t1b t2 t2b t3 t3b t4 t5 t6 t7 t8 t8b t9 t10 t11)

strand_t1() { test1_idle_from_start; test1c_trace_observability; }
strand_t1b() { test1b_tooling_child_incident; }
strand_t2() { test2_no_worker_never_exits; }
strand_t2b() { test2b_timeout_short; }
strand_t3() { test3_working_then_idle_edge; }
strand_t3b() { test3b_concurrent_wait; }
strand_t4() { test4_probe_vanishes; }
strand_t5() { test5_open_handle; }
strand_t6() { test6_lsof_unresolvable; }
strand_t7() { test7_no_hook_self_heals; }
strand_t8() { test8_stuck_dead_from_start; }
strand_t8b() { test8b_working_then_child_killed; }
strand_t9() { test9_mixed_dead_and_working; }
strand_t10() { test10_dead_with_open_bg_handle; }
strand_t11() { test11_second_transition_exits; }

strand_main "$@"
