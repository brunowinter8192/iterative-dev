#!/usr/bin/env bash

# INFRASTRUCTURE

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
WCLI="$PLUGIN_ROOT/bin/worker-cli"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
source "$SELF_DIR/../strand_runner.sh"

STRANDS=(removed_project_path wait_path spawn_old_form merge_old_form missing_args)

# ORCHESTRATOR

test_arg_tripwire_workflow() {
    strand_main "$@"
}

# FUNCTIONS

_expect_tripwire() {
    local desc="$1" expected_form="$2" note="$3"
    shift 3
    local err rc=0
    err=$("$WCLI" "$@" 2>&1 >/dev/null) || rc=$?
    check "$desc -> exit 2" "$([ "$rc" -eq 2 ] && echo ok || echo "rc=$rc, stderr: $err")"
    check "$desc -> stderr names the unexpected argument" \
        "$(echo "$err" | grep -qF "unexpected argument" && echo ok || echo "stderr: $err")"
    check "$desc -> stderr shows the correct form" \
        "$(echo "$err" | grep -qF "Correct form: worker-cli $expected_form" && echo ok || echo "stderr: $err")"
    if [ -n "$note" ]; then
        check "$desc -> stderr carries the note" \
            "$(echo "$err" | grep -qF "$note" && echo ok || echo "stderr: $err")"
    fi
}

strand_removed_project_path() {
    local p="/some/project"
    _expect_tripwire "status <name> <path>" "status <name> | worker-cli status --all" "project_path argument was removed" status w1 "$p"
    _expect_tripwire "status --all <path>" "status --all" "project_path argument was removed" status --all "$p"
    _expect_tripwire "capture <name> <path>" "capture <name> [--raw]" "project_path argument was removed" capture w1 "$p"
    _expect_tripwire "capture <name> --raw <path>" "capture <name> [--raw]" "project_path argument was removed" capture w1 --raw "$p"
    _expect_tripwire "response <name> <path>" "response <name> [count]" "" response w1 "$p"
    _expect_tripwire "response <name> 2 <path>" "response <name> [count]" "project_path argument was removed" response w1 2 "$p"
    _expect_tripwire "send <name> <msg> <path>" "send <name> <message>" "project_path argument was removed" send w1 "hello" "$p"
    _expect_tripwire "kill <name> <path>" "kill <name>" "project_path argument was removed" kill w1 "$p"
    _expect_tripwire "revive <name> <path>" "revive <name>" "project_path argument was removed" revive w1 "$p"
    _expect_tripwire "list <path>" "list" "project_path argument was removed" list "$p"
}

strand_wait_path() {
    _expect_tripwire "wait <path>" "wait [--timeout SEC]" "wait takes no path and uses the current project" wait "$STRAND_DIR"
    _expect_tripwire "wait <path> --timeout" "wait [--timeout SEC]" "wait takes no path and uses the current project" wait "$STRAND_DIR" --timeout 5
}

strand_spawn_old_form() {
    local note="spawn takes no project_path and no model"
    echo "# p" > "$STRAND_DIR/prompt.txt"
    _expect_tripwire "spawn <name> <prompt> <path>" "spawn <name> <prompt_file> [--no-worktree]" "$note" spawn w1 "$STRAND_DIR/prompt.txt" "$STRAND_DIR"
    _expect_tripwire "spawn <name> <prompt> <path> <model>" "spawn <name> <prompt_file> [--no-worktree]" "$note" spawn w1 "$STRAND_DIR/prompt.txt" "$STRAND_DIR" claude-x
    _expect_tripwire "spawn <name> <prompt> <model> --no-worktree" "spawn <name> <prompt_file> [--no-worktree]" "$note" spawn w1 "$STRAND_DIR/prompt.txt" claude-x --no-worktree
}

strand_merge_old_form() {
    _expect_tripwire "merge <name> <path>" "merge <name>" "project_path argument was removed" merge w1 "/some/project"
}

strand_missing_args() {
    local cmd err rc
    for cmd in status capture response send kill revive merge spawn worktree worktree-rm; do
        rc=0
        err=$("$WCLI" "$cmd" 2>&1 >/dev/null) || rc=$?
        check "$cmd without arguments -> exit 2" "$([ "$rc" -eq 2 ] && echo ok || echo "rc=$rc")"
        check "$cmd without arguments -> stderr shows the correct form" \
            "$(echo "$err" | grep -qF "Correct form: worker-cli $cmd" && echo ok || echo "stderr: $err")"
    done
    rc=0
    err=$(cd "$STRAND_DIR" && echo "# p" > p.txt && "$WCLI" spawn w1 p.txt 2>&1 >/dev/null) || rc=$?
    check "spawn outside a git repo -> exit 1" "$([ "$rc" -eq 1 ] && echo ok || echo "rc=$rc, stderr: $err")"
    check "spawn outside a git repo -> stderr says why" \
        "$(echo "$err" | grep -qF "not inside a git repo" && echo ok || echo "stderr: $err")"
}

test_arg_tripwire_workflow "$@"
