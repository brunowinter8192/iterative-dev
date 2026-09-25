#!/usr/bin/env bash

# INFRASTRUCTURE

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
WCLI="$PLUGIN_ROOT/bin/worker-cli"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
source "$SELF_DIR/../strand_runner.sh"

STRANDS=(merge_then_rerun conflict cross_project cross_project_conflict)

# ORCHESTRATOR

test_merge_verify_workflow() {
    strand_main "$@"
}

# FUNCTIONS

init_project() {
    TMPPROJ="$STRAND_DIR/mergeproj"
    mkdir -p "$TMPPROJ"
    git init "$TMPPROJ" -b main -q
    echo "a" > "$TMPPROJ/a.txt"
    git -C "$TMPPROJ" add a.txt
    git -C "$TMPPROJ" commit -q -m init
}

init_repo() {
    mkdir -p "$1"
    git init "$1" -b main -q
    echo "a" > "$1/a.txt"
    git -C "$1" add a.txt
    git -C "$1" commit -q -m init
}

strand_merge_then_rerun() {
    init_project
    _case_merge_with_commit
    _case_merge_again
}

_case_merge_with_commit() {
    echo "=== Case 1: merge a branch that carries a commit ==="

    echo "$TMPPROJ" > "$WORKER_REGISTRY_DIR/feat1"
    git -C "$TMPPROJ" checkout -q -b feat1
    echo "b" > "$TMPPROJ/b.txt"
    git -C "$TMPPROJ" add b.txt
    git -C "$TMPPROJ" commit -q -m "feat1 commit"
    git -C "$TMPPROJ" checkout -q main

    OUT=$("$WCLI" merge feat1 2>"$STRAND_DIR/err1.txt")
    RC=$?
    ERR=$(cat "$STRAND_DIR/err1.txt")
    echo "  stdout:"
    echo "$OUT" | sed 's/^/    /'
    echo "  stderr: $ERR"
    echo "  rc: $RC"

    [ "$RC" -eq 0 ] && check "exit code 0" "ok" || check "exit code 0" "rc=$RC"

    if echo "$OUT" | grep -qF "=== Files merged ==="; then
        check "'=== Files merged ===' header present" "ok"
    else
        check "'=== Files merged ===' header present" "missing from stdout"
    fi

    if echo "$OUT" | grep -qxF "b.txt"; then
        check "b.txt listed as merged file" "ok"
    else
        check "b.txt listed as merged file" "not found in stdout"
    fi

    if git -C "$TMPPROJ" rev-parse --verify main >/dev/null 2>&1 && \
       [ "$(git -C "$TMPPROJ" log -1 --pretty=%s)" = "merge: worker feat1" ]; then
        check "merge commit landed on main" "ok"
    else
        check "merge commit landed on main" "not found"
    fi
}

_case_merge_again() {
    echo ""
    echo "=== Case 2: merge again — branch already fully merged (Already up to date) ==="

    OUT2=$("$WCLI" merge feat1 2>"$STRAND_DIR/err2.txt")
    RC2=$?
    ERR2=$(cat "$STRAND_DIR/err2.txt")
    echo "  stdout:"
    echo "$OUT2" | sed 's/^/    /'
    echo "  stderr: $ERR2"
    echo "  rc: $RC2"

    [ "$RC2" -ne 0 ] && check "exit code non-zero" "ok" || check "exit code non-zero" "rc=$RC2"

    if echo "$ERR2" | grep -qF "carried no commits"; then
        check "stderr names the no-op" "ok"
    else
        check "stderr names the no-op" "missing from stderr"
    fi

    if echo "$ERR2" | grep -qF "never committed" && ! echo "$ERR2" | grep -qF "project_path"; then
        check "stderr names the cause and no longer points at project_path" "ok"
    else
        check "stderr names the cause and no longer points at project_path" "unexpected stderr"
    fi
}

strand_conflict() {
    init_project

    echo ""
    echo "=== Case 3: merge a branch that conflicts with main ==="

    echo "$TMPPROJ" > "$WORKER_REGISTRY_DIR/conflict1"
    git -C "$TMPPROJ" checkout -q -b conflict1
    echo "conflict-from-branch" > "$TMPPROJ/a.txt"
    git -C "$TMPPROJ" add a.txt
    git -C "$TMPPROJ" commit -q -m "conflict1 commit"
    git -C "$TMPPROJ" checkout -q main
    echo "conflict-from-main" > "$TMPPROJ/a.txt"
    git -C "$TMPPROJ" add a.txt
    git -C "$TMPPROJ" commit -q -m "main-side conflicting change"

    OUT3=$("$WCLI" merge conflict1 2>"$STRAND_DIR/err3.txt")
    RC3=$?
    ERR3=$(cat "$STRAND_DIR/err3.txt")
    echo "  stdout:"
    echo "$OUT3" | sed 's/^/    /'
    echo "  stderr: $ERR3"
    echo "  rc: $RC3"
    git -C "$TMPPROJ" merge --abort 2>/dev/null || true

    [ "$RC3" -ne 0 ] && check "exit code non-zero" "ok" || check "exit code non-zero" "rc=$RC3"

    if echo "$OUT3" | grep -qF "CONFLICT"; then
        check "git's conflict text reaches stdout" "ok"
    else
        check "git's conflict text reaches stdout" "missing from stdout"
    fi

    if echo "$OUT3" | grep -qF "=== Files merged ==="; then
        check "'=== Files merged ===' NOT printed on conflict" "printed despite conflict"
    else
        check "'=== Files merged ===' NOT printed on conflict" "ok"
    fi
}

_init_cross_project_repos() {
    XSPAWN="$STRAND_DIR/xspawn"
    XTARGET="$STRAND_DIR/xtarget"
    init_repo "$XSPAWN"
    init_repo "$XTARGET"
    echo "$XSPAWN" > "$WORKER_REGISTRY_DIR/xw"
    git -C "$XSPAWN" worktree add "$XSPAWN/.claude/worktrees/xw" -b xw -q
    ( cd "$XSPAWN" && "$WCLI" worktree xw "$XTARGET" >/dev/null )
}

_commit_in_target_worktree() {
    echo "$1" > "$XTARGET/.claude/worktrees/xw/$2"
    git -C "$XTARGET/.claude/worktrees/xw" add "$2"
    git -C "$XTARGET/.claude/worktrees/xw" commit -q -m "xw commit $2"
}

strand_cross_project() {
    _init_cross_project_repos
    echo "=== Case 4: worker spawned in repo A, committed only in repo B; merge without any path ==="
    _commit_in_target_worktree "x" "x.txt"

    OUT4=$(cd "$XSPAWN" && "$WCLI" merge xw 2>"$STRAND_DIR/err4.txt")
    RC4=$?
    echo "$OUT4" | sed 's/^/    /'
    echo "  stderr: $(cat "$STRAND_DIR/err4.txt")"

    [ "$RC4" -eq 0 ] && check "exit code 0" "ok" || check "exit code 0" "rc=$RC4"
    [ "$(git -C "$XTARGET" log -1 --pretty=%s)" = "merge: worker xw" ] \
        && check "merge commit landed in the target repo" "ok" || check "merge commit landed in the target repo" "not found"
    [ -f "$XTARGET/x.txt" ] && check "x.txt present in target main" "ok" || check "x.txt present in target main" "missing"
    [ "$(git -C "$XSPAWN" log -1 --pretty=%s)" = "init" ] \
        && check "spawn repo untouched" "ok" || check "spawn repo untouched" "spawn repo history changed"
    echo "$OUT4" | grep -qF "skipped: branch xw carries no commits" \
        && check "spawn repo reported as skipped" "ok" || check "spawn repo reported as skipped" "no skip line"
    echo "$OUT4" | grep -qxF "x.txt" \
        && check "x.txt listed as merged file" "ok" || check "x.txt listed as merged file" "not listed"
}

strand_cross_project_conflict() {
    _init_cross_project_repos
    echo "=== Case 5: cross-project merge conflicts in the target repo ==="
    _commit_in_target_worktree "from-branch" "a.txt"
    echo "from-main" > "$XTARGET/a.txt"
    git -C "$XTARGET" add a.txt
    git -C "$XTARGET" commit -q -m "main-side change"

    OUT5=$(cd "$XSPAWN" && "$WCLI" merge xw 2>"$STRAND_DIR/err5.txt")
    RC5=$?
    ERR5=$(cat "$STRAND_DIR/err5.txt")
    git -C "$XTARGET" merge --abort 2>/dev/null || true

    [ "$RC5" -ne 0 ] && check "exit code non-zero" "ok" || check "exit code non-zero" "rc=$RC5"
    echo "$ERR5" | grep -qF "merge failed in $XTARGET" \
        && check "stderr names the failing repo" "ok" || check "stderr names the failing repo" "stderr: $ERR5"
}

test_merge_verify_workflow "$@"
