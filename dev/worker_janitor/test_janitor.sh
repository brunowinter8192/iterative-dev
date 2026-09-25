#!/usr/bin/env bash

# INFRASTRUCTURE

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
WCLI="$PLUGIN_ROOT/bin/worker-cli"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
source "$SELF_DIR/../strand_runner.sh"

STRANDS=(dry_run real_kill fresh_spared orphan)

# ORCHESTRATOR

test_janitor_workflow() {
    strand_main "$@"
}

# FUNCTIONS

init_project() {
    PROJ="$STRAND_DIR/janitorproj"
    mkdir -p "$PROJ"
    git init "$PROJ" -b main -q
    echo "init" > "$PROJ/init.txt"
    git -C "$PROJ" add init.txt
    git -C "$PROJ" commit -m "init" -q
    PROJ_BASENAME=$(basename "$PROJ")
}

start_worker_session() {
    local name="$1"
    git -C "$PROJ" worktree add ".claude/worktrees/$name" -b "$name" -q
    SESSION="worker-${PROJ_BASENAME}-${name}"
    tmux new-session -d -s "$SESSION" -c "$PROJ/.claude/worktrees/$name" 'sleep 300'
    sleep 1
}

strand_dry_run() {
    init_project
    start_worker_session stale1

    local out
    out=$("$WCLI" janitor --max-age-hours 0 --dry-run 2>&1)
    echo "$out" | sed 's/^/  /'

    if echo "$out" | grep -q "DRY-RUN candidate: $SESSION"; then
        check "stale1 listed as dry-run candidate" "ok"
    else
        check "stale1 listed as dry-run candidate" "not found in output"
    fi
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        check "dry-run did not kill the session" "ok"
    else
        check "dry-run did not kill the session" "session gone after dry-run!"
    fi
}

strand_real_kill() {
    init_project
    start_worker_session stale1

    local out
    out=$("$WCLI" janitor --max-age-hours 0 2>&1)
    echo "$out" | sed 's/^/  /'

    if tmux has-session -t "$SESSION" 2>/dev/null; then
        check "stale1 tmux session gone" "still exists"
    else
        check "stale1 tmux session gone" "ok"
    fi
    if [ -d "$PROJ/.claude/worktrees/stale1" ]; then
        check "stale1 worktree removed" "still exists"
    else
        check "stale1 worktree removed" "ok"
    fi
    if git -C "$PROJ" rev-parse --verify stale1 >/dev/null 2>&1; then
        check "stale1 branch deleted" "still exists"
    else
        check "stale1 branch deleted" "ok"
    fi
    if [ -f "$WORKER_LOGGER_DIR/janitor.log" ] && grep -q "action=kill.*name=stale1" "$WORKER_LOGGER_DIR/janitor.log"; then
        check "janitor.log has kill line for stale1" "ok"
    else
        check "janitor.log has kill line for stale1" "not found"
    fi
}

strand_fresh_spared() {
    init_project
    start_worker_session fresh1

    local out
    out=$("$WCLI" janitor 2>&1)
    echo "$out" | sed 's/^/  /'

    if tmux has-session -t "$SESSION" 2>/dev/null; then
        check "fresh1 session spared (not killed)" "ok"
    else
        check "fresh1 session spared (not killed)" "was killed!"
    fi
    if echo "$out" | grep -q "$SESSION"; then
        check "fresh1 not mentioned in real-run output (below age threshold)" "mentioned — $(echo "$out" | grep "$SESSION")"
    else
        check "fresh1 not mentioned in real-run output (below age threshold)" "ok"
    fi
}

strand_orphan() {
    init_project
    git -C "$PROJ" worktree add ".claude/worktrees/orphan1" -b orphan1 -q
    echo "$PROJ" > "$WORKER_REGISTRY_DIR/orphan1"
    touch -t "$(date -v-1H +%Y%m%d%H%M.%S 2>/dev/null || date -d '-1 hour' +%Y%m%d%H%M.%S)" "$WORKER_REGISTRY_DIR/orphan1"

    local out
    out=$("$WCLI" janitor --max-age-hours 0 2>&1)
    echo "$out" | sed 's/^/  /'

    if [ -f "$WORKER_REGISTRY_DIR/orphan1" ]; then
        check "orphan1 registry entry removed" "still exists"
    else
        check "orphan1 registry entry removed" "ok"
    fi
    if [ -d "$PROJ/.claude/worktrees/orphan1" ]; then
        check "orphan1 worktree removed" "still exists"
    else
        check "orphan1 worktree removed" "ok"
    fi
    if grep -q "action=orphan-clean.*name=orphan1" "$WORKER_LOGGER_DIR/janitor.log"; then
        check "janitor.log has orphan-clean line" "ok"
    else
        check "janitor.log has orphan-clean line" "not found"
    fi
}

test_janitor_workflow "$@"
