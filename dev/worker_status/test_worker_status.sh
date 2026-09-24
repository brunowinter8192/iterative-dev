#!/bin/bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SPAWN="$PLUGIN_ROOT/src/spawn/tmux_spawn.sh"
HOOKS_FILE="$HOME/Library/Application Support/com.brunowinter.monitor-cc-menubar/hooks.json"
HOOKS_BACKUP="/tmp/status-test-hooks-backup-$$.json"
RESULT=0
TEST_TAG="statustest$$"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; RESULT=1; }

backup_hooks() {
    if [ -f "$HOOKS_FILE" ]; then
        cp "$HOOKS_FILE" "$HOOKS_BACKUP"
    else
        : > "$HOOKS_BACKUP.missing"
        mkdir -p "$(dirname "$HOOKS_FILE")"
        echo '{}' > "$HOOKS_FILE"
    fi
}

restore_hooks() {
    if [ -f "$HOOKS_BACKUP" ]; then
        mv "$HOOKS_BACKUP" "$HOOKS_FILE"
    elif [ -f "$HOOKS_BACKUP.missing" ]; then
        rm -f "$HOOKS_FILE" "$HOOKS_BACKUP.missing"
    fi
}

set_hook_status() {
    local session_id="$1" status="$2" cwd="$3"
    local tmp="$HOOKS_FILE.tmp.$$"
    jq --arg sid "$session_id" --arg st "$status" --arg cwd "$cwd" \
        '.[$sid] = {status: $st, cwd: $cwd, updated_ts: now}' "$HOOKS_FILE" > "$tmp" \
        && mv "$tmp" "$HOOKS_FILE"
}

encode_proj_dir() {
    local real_proj_dir
    real_proj_dir=$(cd "$1" && pwd -P)
    echo "$real_proj_dir" | tr '/_.' '-'
}

start_tmux_session() {
    local session="$1" proj_dir="$2" command="$3"
    tmux new-session -d -s "$session" -c "$proj_dir" "$command" \; \
        set-option -p -t "$session" remain-on-exit on
    tmux set-environment -t "$session" WORKER_SPAWNED "$(date +%H:%M)"
    tmux set-environment -t "$session" WORKER_PURPOSE "test fixture"
    sleep 0.5
}

register_jsonl() {
    local proj_dir="$1" session_id="$2"
    local encoded
    encoded=$(encode_proj_dir "$proj_dir")
    mkdir -p "$HOME/.claude/projects/$encoded"
    touch "$HOME/.claude/projects/$encoded/$session_id.jsonl"
}

write_wrap_bg() {
    local wrap="$1"
    cat > "$wrap" <<'INNER'
#!/bin/bash
( exec -a claude-dummy bash -c '(exec -a pyright-langserver-dummy sleep 100000) & wait' ) &
CLAUDE_PID=$!
echo "$CLAUDE_PID" > "$(dirname "$0")/.claude.pid"
wait $CLAUDE_PID
INNER
    chmod +x "$wrap"
}

write_wrap_chatty() {
    local proj_dir="$1" wrap="$2"
    cat > "$proj_dir/.chatty.sh" <<'INNER'
#!/bin/bash
QUIET_FILE="$1"
while [ ! -f "$QUIET_FILE" ]; do
    echo "tick $(date +%s)"
    sleep $(( (RANDOM % 2) + 1 ))
done
sleep 100000
INNER
    chmod +x "$proj_dir/.chatty.sh"
    cat > "$wrap" <<'INNER'
#!/bin/bash
( exec -a claude-dummy bash "$(dirname "$0")/.chatty.sh" "$(dirname "$0")/.chatty-quiet" ) &
CLAUDE_PID=$!
echo "$CLAUDE_PID" > "$(dirname "$0")/.claude.pid"
wait $CLAUDE_PID
INNER
    chmod +x "$wrap"
}

write_wrap_plain() {
    local wrap="$1"
    cat > "$wrap" <<'INNER'
#!/bin/bash
( exec -a claude-dummy sleep 100000 ) &
CLAUDE_PID=$!
echo "$CLAUDE_PID" > "$(dirname "$0")/.claude.pid"
wait $CLAUDE_PID
INNER
    chmod +x "$wrap"
}

write_wrap_no_pid() {
    local wrap="$1"
    cat > "$wrap" <<'INNER'
#!/bin/bash
( exec -a claude-dummy sleep 100000 ) &
CLAUDE_PID=$!
wait $CLAUDE_PID
INNER
    chmod +x "$wrap"
}

write_worker_wrapper() {
    local proj_dir="$1" wrap="$2" bg="$3" chatty="$4"
    if [ "$bg" = "1" ]; then
        write_wrap_bg "$wrap"
    elif [ "$chatty" = "1" ]; then
        write_wrap_chatty "$proj_dir" "$wrap"
    else
        write_wrap_plain "$wrap"
    fi
}

create_worker() {
    local name="$1" proj_dir="$2" session_id="$3" status="$4" bg="$5" chatty="${6:-0}"
    mkdir -p "$proj_dir"
    local session="worker-$(basename "$proj_dir")-$name"
    tmux kill-session -t "$session" 2>/dev/null || true
    rm -f "$proj_dir/.claude.pid" "$proj_dir/.chatty-quiet"
    local wrap="$proj_dir/.wrap.sh"
    write_worker_wrapper "$proj_dir" "$wrap" "$bg" "$chatty"
    start_tmux_session "$session" "$proj_dir" "bash $wrap"
    register_jsonl "$proj_dir" "$session_id"
    set_hook_status "$session_id" "$status" "$proj_dir"
    echo "$session"
}

go_quiet() {
    local proj_dir="$1"
    touch "$proj_dir/.chatty-quiet"
}

kill_claude_child() {
    local proj_dir="$1"
    local pf="$proj_dir/.claude.pid"
    [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null
    return 0
}

delete_hook_entry() {
    local sid="$1"
    jq --arg sid "$sid" 'del(.[$sid])' "$HOOKS_FILE" > "$HOOKS_FILE.tmp.$$" 2>/dev/null \
        && mv "$HOOKS_FILE.tmp.$$" "$HOOKS_FILE"
}

create_worker_limit_reached() {
    local name="$1" proj_dir="$2"
    mkdir -p "$proj_dir"
    local session="worker-$(basename "$proj_dir")-$name"
    tmux kill-session -t "$session" 2>/dev/null || true
    start_tmux_session "$session" "$proj_dir" "true"
    echo "$session"
}

create_worker_no_jsonl() {
    local name="$1" proj_dir="$2"
    mkdir -p "$proj_dir"
    local session="worker-$(basename "$proj_dir")-$name"
    tmux kill-session -t "$session" 2>/dev/null || true
    local wrap="$proj_dir/.wrap.sh"
    write_wrap_no_pid "$wrap"
    start_tmux_session "$session" "$proj_dir" "bash $wrap"
    echo "$session"
}

destroy_worker() {
    local name="$1" proj_dir="$2" session_id="$3"
    local session="worker-$(basename "$proj_dir")-$name"
    tmux kill-session -t "$session" 2>/dev/null || true
    if [ -n "$session_id" ]; then
        jq --arg sid "$session_id" 'del(.[$sid])' "$HOOKS_FILE" > "$HOOKS_FILE.tmp.$$" 2>/dev/null \
            && mv "$HOOKS_FILE.tmp.$$" "$HOOKS_FILE"
    fi
    local real_proj_dir encoded
    real_proj_dir=$([ -d "$proj_dir" ] && (cd "$proj_dir" && pwd -P) || echo "$proj_dir")
    encoded=$(echo "$real_proj_dir" | tr '/_.' '-')
    rm -rf "$HOME/.claude/projects/$encoded"
    rm -rf "$proj_dir"
}

jsonl_path() {
    local proj_dir="$1" session_id="$2"
    local encoded
    encoded=$(encode_proj_dir "$proj_dir")
    echo "$HOME/.claude/projects/$encoded/$session_id.jsonl"
}

write_synthetic_marker_jsonl() {
    local proj_dir="$1" session_id="$2"
    local jsonl
    jsonl=$(jsonl_path "$proj_dir" "$session_id")
    jq -n -c \
        '{type:"assistant", isApiErrorMessage:true, error:"invalid_request",
          message:{model:"<synthetic>", role:"assistant",
                   content:[{type:"text", text:"Prompt is too long"}],
                   usage:{input_tokens:0, output_tokens:0,
                          cache_creation_input_tokens:0, cache_read_input_tokens:0}}}' \
        > "$jsonl"
}

write_normal_assistant_jsonl() {
    local proj_dir="$1" session_id="$2"
    local jsonl
    jsonl=$(jsonl_path "$proj_dir" "$session_id")
    jq -n -c \
        '{type:"assistant",
          message:{model:"claude-sonnet-5", role:"assistant",
                   content:[{type:"text", text:"Let me look at that file"}],
                   usage:{input_tokens:120, output_tokens:40,
                          cache_creation_input_tokens:0, cache_read_input_tokens:0}}}' \
        > "$jsonl"
}

check_status() {
    local label="$1" session="$2" expected="$3"
    local got
    got=$(bash -c "source \"$SPAWN\" && _worker_detect_status \"\$1\"" _ "$session" 2>/dev/null || echo "ERROR")
    if [ "$got" = "$expected" ]; then
        pass "$label: got '$got'"
    else
        fail "$label: got '$got' (expected '$expected')"
    fi
}

cleanup_all() {
    destroy_worker w1 "/tmp/${TEST_TAG}-1" "${TEST_TAG}-sess-1" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-2" "${TEST_TAG}-sess-2" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-3" "${TEST_TAG}-sess-3" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-4" "${TEST_TAG}-sess-4" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-5" "${TEST_TAG}-sess-5" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-6" "" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-7" "${TEST_TAG}-sess-7" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-8" "" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-9" "${TEST_TAG}-sess-9" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-10" "${TEST_TAG}-sess-10" 2>/dev/null || true
    destroy_worker w1 "/tmp/${TEST_TAG}-11" "${TEST_TAG}-sess-11" 2>/dev/null || true
    restore_hooks
}
trap cleanup_all EXIT

backup_hooks

echo "=== _worker_detect_status — integration tests (working/idle/dead vocabulary) ==="

PROJ1="/tmp/${TEST_TAG}-1"
SID1="${TEST_TAG}-sess-1"
SESSION1=$(create_worker w1 "$PROJ1" "$SID1" idle 0)
check_status "test1 hook-idle-quiet" "$SESSION1" "idle"
destroy_worker w1 "$PROJ1" "$SID1"

PROJ2="/tmp/${TEST_TAG}-2"
SID2="${TEST_TAG}-sess-2"
SESSION2=$(create_worker w1 "$PROJ2" "$SID2" working 0 1)
check_status "test2 hook-working-chatty" "$SESSION2" "working"
go_quiet "$PROJ2"
destroy_worker w1 "$PROJ2" "$SID2"

PROJ3="/tmp/${TEST_TAG}-3"
SID3="${TEST_TAG}-sess-3"
SESSION3=$(create_worker w1 "$PROJ3" "$SID3" working 0)
sleep 11
check_status "test3 esc-interrupt-quiet-over-10s" "$SESSION3" "idle"
destroy_worker w1 "$PROJ3" "$SID3"

PROJ4="/tmp/${TEST_TAG}-4"
SID4="${TEST_TAG}-sess-4"
SESSION4=$(create_worker w1 "$PROJ4" "$SID4" idle 0 1)
delete_hook_entry "$SID4"
check_status "test4 no-hook-entry-chatty" "$SESSION4" "working"
go_quiet "$PROJ4"
destroy_worker w1 "$PROJ4" "$SID4"

PROJ5="/tmp/${TEST_TAG}-5"
SID5="${TEST_TAG}-sess-5"
SESSION5=$(create_worker w1 "$PROJ5" "$SID5" idle 0)
delete_hook_entry "$SID5"
sleep 11
check_status "test5 no-hook-entry-quiet" "$SESSION5" "idle"
destroy_worker w1 "$PROJ5" "$SID5"

PROJ6="/tmp/${TEST_TAG}-6"
SESSION6=$(create_worker_no_jsonl w1 "$PROJ6")
check_status "test6 no-jsonl-fresh-spawn" "$SESSION6" "working"
destroy_worker w1 "$PROJ6" ""

PROJ7="/tmp/${TEST_TAG}-7"
SID7="${TEST_TAG}-sess-7"
SESSION7=$(create_worker w1 "$PROJ7" "$SID7" working 0)
kill_claude_child "$PROJ7"
sleep 1
check_status "test7 claude-child-killed" "$SESSION7" "dead"
destroy_worker w1 "$PROJ7" "$SID7"

PROJ8="/tmp/${TEST_TAG}-8"
SESSION8=$(create_worker_limit_reached w1 "$PROJ8")
check_status "test8 pane-dead" "$SESSION8" "dead"
destroy_worker w1 "$PROJ8" ""

PROJ9="/tmp/${TEST_TAG}-9"
SID9="${TEST_TAG}-sess-9"
create_worker w1 "$PROJ9" "$SID9" working 0 >/dev/null
tmux kill-session -t "worker-$(basename "$PROJ9")-w1" 2>/dev/null || true
STATUS9=$(bash -c "source \"$SPAWN\" && worker_status \"\$1\" \"\$2\"" _ w1 "$PROJ9" 2>/dev/null || echo "ERROR")
if [ "$STATUS9" = "dead" ]; then
    pass "test9 session-killed-via-worker-status: got '$STATUS9'"
else
    fail "test9 session-killed-via-worker-status: got '$STATUS9' (expected 'dead')"
fi
destroy_worker w1 "$PROJ9" "$SID9"

PROJ10="/tmp/${TEST_TAG}-10"
SID10="${TEST_TAG}-sess-10"
SESSION10=$(create_worker w1 "$PROJ10" "$SID10" idle 0)
write_synthetic_marker_jsonl "$PROJ10" "$SID10"
check_status "test10 synthetic-context-limit-marker" "$SESSION10" "dead"
destroy_worker w1 "$PROJ10" "$SID10"

PROJ11="/tmp/${TEST_TAG}-11"
SID11="${TEST_TAG}-sess-11"
SESSION11=$(create_worker w1 "$PROJ11" "$SID11" working 0)
write_normal_assistant_jsonl "$PROJ11" "$SID11"
sleep 11
check_status "test11 normal-aborted-message-not-dead" "$SESSION11" "idle"
destroy_worker w1 "$PROJ11" "$SID11"

STATUS_FILE="$PLUGIN_ROOT/src/spawn/worker_status.sh"
if grep -q '^_worker_detect_status()' "$STATUS_FILE" 2>/dev/null; then
    pass "grep: _worker_detect_status is defined in worker_status.sh (retired-string checks scan real code)"
else
    fail "grep: _worker_detect_status not found in worker_status.sh"
fi
if grep -q "limit reached" "$STATUS_FILE" 2>/dev/null; then
    fail "grep: 'limit reached' still present in worker_status.sh"
else
    pass "grep: 'limit reached' no longer present in worker_status.sh"
fi
if grep -qF 'echo "unknown"' "$STATUS_FILE" 2>/dev/null; then
    fail 'grep: echo "unknown" still present in worker_status.sh'
else
    pass 'grep: echo "unknown" no longer present in worker_status.sh'
fi

echo "=== $([ $RESULT -eq 0 ] && echo ALL PASSED || echo SOME FAILED) ==="
exit $RESULT
