HOOKS_FILE="$HOME/Library/Application Support/com.brunowinter.monitor-cc-menubar/hooks.json"
HOOKS_BACKUP="/tmp/wait-test-hooks-backup-$$.json"
TRACE_FILE="${WORKER_LOGGER_DIR:-$HOME/Documents/ai/Meta/iterative-dev/src/logs}/wait_trace.log"

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

create_worker_no_hook() {
    local name="$1" proj_dir="$2" session_id="$3"
    mkdir -p "$proj_dir"
    local session="worker-$(basename "$proj_dir")-$name"
    tmux kill-session -t "$session" 2>/dev/null || true
    local wrap="$proj_dir/.wrap.sh"
    write_wrap_no_pid "$wrap"
    start_tmux_session "$session" "$proj_dir" "bash $wrap"
    register_jsonl "$proj_dir" "$session_id"
    echo "$session"
}

create_worker_dead() {
    local name="$1" proj_dir="$2"
    mkdir -p "$proj_dir"
    local session="worker-$(basename "$proj_dir")-$name"
    tmux kill-session -t "$session" 2>/dev/null || true
    start_tmux_session "$session" "$proj_dir" "true"
    echo "$session"
}

destroy_worker() {
    local name="$1" proj_dir="$2" session_id="$3"
    local session="worker-$(basename "$proj_dir")-$name"
    tmux kill-session -t "$session" 2>/dev/null || true
    jq --arg sid "$session_id" 'del(.[$sid])' "$HOOKS_FILE" > "$HOOKS_FILE.tmp.$$" 2>/dev/null \
        && mv "$HOOKS_FILE.tmp.$$" "$HOOKS_FILE"
    local real_proj_dir encoded
    real_proj_dir=$([ -d "$proj_dir" ] && (cd "$proj_dir" && pwd -P) || echo "$proj_dir")
    encoded=$(echo "$real_proj_dir" | tr '/_.' '-')
    rm -rf "$HOME/.claude/projects/$encoded"
    rm -rf "$proj_dir"
}

real_tasks_dir() {
    local proj_dir="$1" session_id="$2"
    local encoded real_tmp
    encoded=$(encode_proj_dir "$proj_dir")
    real_tmp=$(cd /tmp && pwd -P)
    echo "${real_tmp}/claude-$(id -u)/${encoded}/${session_id}/tasks"
}

raw_tasks_dir() {
    local proj_dir="$1" session_id="$2"
    local encoded
    encoded=$(encode_proj_dir "$proj_dir")
    echo "/tmp/claude-$(id -u)/${encoded}/${session_id}/tasks"
}

start_fake_bg_task() {
    local tdir="$1" task_id="$2"
    mkdir -p "$tdir"
    ( exec sleep 100000 > "$tdir/$task_id.output" ) &
    disown
    echo $! > "/tmp/${TEST_TAG}-fakebg-${task_id}.pid"
}

kill_fake_bg_task() {
    local task_id="$1"
    local pidfile="/tmp/${TEST_TAG}-fakebg-${task_id}.pid"
    if [ -f "$pidfile" ]; then
        kill "$(cat "$pidfile")" 2>/dev/null || true
        rm -f "$pidfile"
    fi
}
