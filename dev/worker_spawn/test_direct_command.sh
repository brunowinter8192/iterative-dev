#!/usr/bin/env bash

# INFRASTRUCTURE

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/../strand_runner.sh"

STRANDS=(h1)

# ORCHESTRATOR

test_direct_command_workflow() {
    strand_main "$@"
}

# FUNCTIONS

strand_h1() {
    export STRAND_H1_TOKEN="inherit-probe-$$"
    local session="test-spawn-h1"

    tmux new-session -d -s "$session" -c /tmp \
        "echo TOKEN=\$STRAND_H1_TOKEN && echo PATH=\$PATH && sleep 10" \; \
        set-option -p -t "$session" remain-on-exit on
    sleep 1

    local output
    output=$(tmux capture-pane -p -t "$session")
    echo "--- Captured output ---"
    echo "$output"
    echo "--- End ---"

    echo "$output" | grep -q "TOKEN=inherit-probe-$$" && pass "env var inherited" || fail "env var not found or empty"
    echo "$output" | grep -q "PATH=/" && pass "PATH inherited" || fail "PATH not found"
}

test_direct_command_workflow "$@"
