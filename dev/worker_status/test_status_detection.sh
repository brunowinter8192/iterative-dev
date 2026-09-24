#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/../strand_runner.sh"

STRANDS=(h2)

strand_h2() {
    local session="test-spawn-h2"

    tmux new-session -d -s "$session" "sleep 2" \; \
        set-option -p -t "$session" remain-on-exit on
    sleep 0.5

    local dead_before cmd_before
    dead_before=$(tmux display-message -t "$session:^" -p "#{pane_dead}")
    cmd_before=$(tmux display-message -t "$session:^" -p "#{pane_current_command}")
    echo "Before exit: pane_dead=$dead_before, current_command=$cmd_before"
    [ "$dead_before" = "0" ] && pass "pane_dead=0 while running" || fail "pane_dead=$dead_before (expected 0)"

    sleep 3

    local dead_after cmd_after
    dead_after=$(tmux display-message -t "$session:^" -p "#{pane_dead}")
    cmd_after=$(tmux display-message -t "$session:^" -p "#{pane_current_command}")
    echo "After exit: pane_dead=$dead_after, current_command=$cmd_after"
    [ "$dead_after" = "1" ] && pass "pane_dead=1 after exit" || fail "pane_dead=$dead_after (expected 1)"
}

strand_main "$@"
