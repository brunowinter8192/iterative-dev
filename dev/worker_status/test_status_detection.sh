#!/bin/bash
set -euo pipefail

SESSION="test-spawn-h2"
RESULT=0

tmux kill-session -t "$SESSION" 2>/dev/null || true

echo "=== H2: Status Detection ==="

tmux new-session -d -s "$SESSION" "sleep 2" \; \
    set-option -p -t "$SESSION" remain-on-exit on

sleep 0.5
DEAD_BEFORE=$(tmux display-message -t "$SESSION:^" -p "#{pane_dead}")
CMD_BEFORE=$(tmux display-message -t "$SESSION:^" -p "#{pane_current_command}")

echo "Before exit: pane_dead=$DEAD_BEFORE, current_command=$CMD_BEFORE"

if [ "$DEAD_BEFORE" = "0" ]; then
    echo "PASS: pane_dead=0 while running"
else
    echo "FAIL: pane_dead=$DEAD_BEFORE (expected 0)"
    RESULT=1
fi

sleep 3

DEAD_AFTER=$(tmux display-message -t "$SESSION:^" -p "#{pane_dead}")
CMD_AFTER=$(tmux display-message -t "$SESSION:^" -p "#{pane_current_command}")

echo "After exit: pane_dead=$DEAD_AFTER, current_command=$CMD_AFTER"

if [ "$DEAD_AFTER" = "1" ]; then
    echo "PASS: pane_dead=1 after exit"
else
    echo "FAIL: pane_dead=$DEAD_AFTER (expected 1)"
    RESULT=1
fi

tmux kill-session -t "$SESSION" 2>/dev/null || true

if [ $RESULT -eq 0 ]; then
    echo "=== H2 CONFIRMED ==="
else
    echo "=== H2 FAILED ==="
fi

exit $RESULT
