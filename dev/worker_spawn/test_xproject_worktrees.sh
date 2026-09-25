#!/usr/bin/env bash

# INFRASTRUCTURE

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
WCLI="$PLUGIN_ROOT/bin/worker-cli"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
source "$SELF_DIR/../strand_runner.sh"

STRANDS=(worktree_then_kill list_skips_sidecars worktree_rm)

# ORCHESTRATOR

test_xproject_worktrees_workflow() {
    strand_main "$@"
}

# FUNCTIONS

commit_init() {
    echo "init" > "$1/init.txt"
    git -C "$1" add init.txt
    git -C "$1" commit -m "init" -q
}

strand_worktree_then_kill() {
    _init_target_and_spawn_repos
    _case_worktree_created
    _case_kill_cleans_both
}

_init_target_and_spawn_repos() {
    TMPTARGET="$STRAND_DIR/target"
    TMPSPAWN="$STRAND_DIR/spawn"
    mkdir -p "$TMPTARGET" "$TMPSPAWN"
    git init "$TMPTARGET" -b main -q
    commit_init "$TMPTARGET"
    git init "$TMPSPAWN" -b main -q
    commit_init "$TMPSPAWN"
}

_case_worktree_created() {
    echo "=== Case 1: worker-cli worktree tw1 <target> ==="

    OUTPUT=$("$WCLI" worktree tw1 "$TMPTARGET" 2>&1)
    echo "  output: $OUTPUT"

    if [ -d "$TMPTARGET/.claude/worktrees/tw1" ]; then
        check "worktree dir exists in target" "ok"
    else
        check "worktree dir exists in target" "not found at $TMPTARGET/.claude/worktrees/tw1"
    fi

    if git -C "$TMPTARGET" rev-parse --verify tw1 >/dev/null 2>&1; then
        check "branch tw1 exists in target" "ok"
    else
        check "branch tw1 exists in target" "branch not found"
    fi

    if [ -f "$WORKER_REGISTRY_DIR/tw1.worktrees" ]; then
        SIDECAR_CONTENT=$(cat "$WORKER_REGISTRY_DIR/tw1.worktrees")
        if printf '%s' "$SIDECAR_CONTENT" | grep -qF "$TMPTARGET"; then
            check "sidecar contains target path" "ok"
        else
            check "sidecar contains target path" "content was: $SIDECAR_CONTENT"
        fi
    else
        check "sidecar file exists" "not found at $WORKER_REGISTRY_DIR/tw1.worktrees"
    fi
}

_case_kill_cleans_both() {
    echo "=== Case 2: worker-cli kill tw1 cleans both spawn + cross-project ==="

    git -C "$TMPSPAWN" worktree add "$TMPSPAWN/.claude/worktrees/tw1" -b tw1 -q
    echo "$TMPSPAWN" > "$WORKER_REGISTRY_DIR/tw1"

    "$WCLI" kill tw1 2>&1 | sed 's/^/  /'

    if [ ! -d "$TMPSPAWN/.claude/worktrees/tw1" ]; then
        check "spawn worktree removed" "ok"
    else
        check "spawn worktree removed" "still exists at $TMPSPAWN/.claude/worktrees/tw1"
    fi

    if ! git -C "$TMPSPAWN" rev-parse --verify tw1 >/dev/null 2>&1; then
        check "spawn branch deleted" "ok"
    else
        check "spawn branch deleted" "still exists"
    fi

    if [ ! -d "$TMPTARGET/.claude/worktrees/tw1" ]; then
        check "cross-project worktree removed" "ok"
    else
        check "cross-project worktree removed" "still exists at $TMPTARGET/.claude/worktrees/tw1"
    fi

    if ! git -C "$TMPTARGET" rev-parse --verify tw1 >/dev/null 2>&1; then
        check "cross-project branch deleted" "ok"
    else
        check "cross-project branch deleted" "still exists"
    fi

    if [ ! -f "$WORKER_REGISTRY_DIR/tw1.worktrees" ]; then
        check "sidecar removed" "ok"
    else
        check "sidecar removed" "still exists"
    fi

    if [ ! -f "$WORKER_REGISTRY_DIR/tw1" ]; then
        check "registry entry removed" "ok"
    else
        check "registry entry removed" "still exists"
    fi
}

strand_list_skips_sidecars() {
    echo "=== Case 3: list / status --all skip sidecar files ==="

    TMPSPAWN2="$STRAND_DIR/spawn2"; mkdir -p "$TMPSPAWN2"
    git init "$TMPSPAWN2" -b main -q
    commit_init "$TMPSPAWN2"

    echo "$TMPSPAWN2" > "$WORKER_REGISTRY_DIR/realworker"
    touch "$WORKER_REGISTRY_DIR/realworker.worktrees"

    LIST_OUT=$("$WCLI" list 2>&1)
    echo "  list output:"
    echo "$LIST_OUT" | sed 's/^/    /'

    if echo "$LIST_OUT" | grep -qE "^realworker:"; then
        check "list shows realworker" "ok"
    else
        check "list shows realworker" "not found in list output"
    fi

    if echo "$LIST_OUT" | grep -qE "^realworker\.worktrees:"; then
        check "list does NOT show sidecar as worker" "sidecar appeared as worker"
    else
        check "list does NOT show sidecar as worker" "ok"
    fi

    STATUS_OUT=$("$WCLI" status --all 2>&1)
    echo "  status --all output:"
    echo "$STATUS_OUT" | sed 's/^/    /'

    if echo "$STATUS_OUT" | grep -qE "^realworker\.worktrees:"; then
        check "status --all does NOT show sidecar as worker" "sidecar appeared as worker"
    else
        check "status --all does NOT show sidecar as worker" "ok"
    fi
}

strand_worktree_rm() {
    echo "=== Case 4: worktree-rm removes orphaned worktree + branch ==="

    TMPTARGET2="$STRAND_DIR/target2"; mkdir -p "$TMPTARGET2"
    git init "$TMPTARGET2" -b main -q
    commit_init "$TMPTARGET2"
    git -C "$TMPTARGET2" worktree add "$TMPTARGET2/.claude/worktrees/orphan" -b orphan -q

    "$WCLI" worktree-rm "$TMPTARGET2" orphan 2>&1 | sed 's/^/  /'

    if [ ! -d "$TMPTARGET2/.claude/worktrees/orphan" ]; then
        check "worktree-rm: worktree removed" "ok"
    else
        check "worktree-rm: worktree removed" "still exists"
    fi

    if ! git -C "$TMPTARGET2" rev-parse --verify orphan >/dev/null 2>&1; then
        check "worktree-rm: branch deleted" "ok"
    else
        check "worktree-rm: branch deleted" "still exists"
    fi
}

test_xproject_worktrees_workflow "$@"
