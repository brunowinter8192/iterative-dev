#!/usr/bin/env bash

# INFRASTRUCTURE

_WAIT_POLL_INTERVAL=5
_WAIT_STABLE_SAMPLES=3

_WAIT_TRACE_ENABLED="${WORKER_CLI_WAIT_TRACE:-1}"
_WAIT_TRACE_FILE="${WORKER_LOGGER_DIR:-$HOME/Documents/ai/Meta/iterative-dev/src/logs}/wait_trace.log"
_WAIT_TRACE_MAX_LINES=20000
_WAIT_TRACE_KEEP_LINES=10000

# FUNCTIONS

_wait_trace() {
    [ "$_WAIT_TRACE_ENABLED" = "1" ] || return 0
    echo "$(date -Iseconds) $1" >> "$_WAIT_TRACE_FILE"
}

_wait_trace_init() {
    [ "$_WAIT_TRACE_ENABLED" = "1" ] || return 0
    mkdir -p "$(dirname "$_WAIT_TRACE_FILE")"
    if [ -f "$_WAIT_TRACE_FILE" ]; then
        local lines
        lines=$(wc -l < "$_WAIT_TRACE_FILE")
        lines="${lines// /}"
        if [ "$lines" -gt "$_WAIT_TRACE_MAX_LINES" ]; then
            tail -n "$_WAIT_TRACE_KEEP_LINES" "$_WAIT_TRACE_FILE" > "${_WAIT_TRACE_FILE}.tmp.$$"
            mv "${_WAIT_TRACE_FILE}.tmp.$$" "$_WAIT_TRACE_FILE"
        fi
    fi
}

_wait_has_live_bg_task() {
    local name="$1" project="$2"
    bash -c '
        source "$1"
        session=$(_worker_session_name "$2" "$3")
        worktree=$(tmux display-message -t "${session}:^" -p "#{pane_current_path}" 2>/dev/null) || { echo error; exit 0; }
        [ -z "$worktree" ] && { echo error; exit 0; }
        encoded=$(encode_worktree_path "$worktree")
        jsonl=$(ls -t "$HOME/.claude/projects/${encoded}"/*.jsonl 2>/dev/null | head -1)
        [ -z "$jsonl" ] && { echo error; exit 0; }
        session_id=$(basename "$jsonl" .jsonl)
        command -v lsof >/dev/null 2>&1 || { echo error; exit 0; }
        real_tmp=$(cd /tmp && pwd -P)
        tasks_dir="${real_tmp}/claude-$(id -u)/${encoded}/${session_id}/tasks"
        [ -d "$tasks_dir" ] || { echo no; exit 0; }
        out=$(lsof +D "$tasks_dir" -Fn 2>/dev/null) || true
        found=no
        while IFS= read -r line; do
            case "$line" in
                n*.output) found=yes; break ;;
            esac
        done <<< "$out"
        echo "$found"
    ' _ "$SPAWN" "$project" "$name" 2>/dev/null || echo error
}

cmd_wait() {
    _wait_parse_args "$@"
    local project timeout="$_WAIT_TIMEOUT"
    project=$(resolve_project_path "$(pwd)")
    _WAIT_TRACE_TAG="pid=$$ project=$(basename "$project")"
    _wait_trace_init
    _wait_trace "$_WAIT_TRACE_TAG event=start timeout=$timeout"
    local start_ts elapsed names
    local stable_count=0 empty_count=0
    start_ts=$(date +%s)
    _WAIT_SAW_WORKING=0
    while true; do
        elapsed=$(( $(date +%s) - start_ts ))
        if [ "$elapsed" -ge "$timeout" ]; then
            _wait_trace "$_WAIT_TRACE_TAG event=exit reason=timeout elapsed=$elapsed saw_working=$_WAIT_SAW_WORKING"
            echo "timeout"
            exit 0
        fi
        if ! names=$(_wait_list_names "$project"); then
            _wait_trace "$_WAIT_TRACE_TAG event=exit reason=list_failed elapsed=$elapsed saw_working=$_WAIT_SAW_WORKING"
            echo "worker-cli: worker_list failed for project $project" >&2
            exit 1
        fi
        if [ -z "$names" ]; then
            stable_count=0
            empty_count=$((empty_count + 1))
            _wait_trace "$_WAIT_TRACE_TAG event=decision empty=1 empty_count=$empty_count elapsed=$elapsed"
            sleep "$_WAIT_POLL_INTERVAL"
            continue
        fi
        empty_count=0
        _wait_poll_once "$project" "$names"
        if [ "$_WAIT_ALL_NONBLOCKING" = "1" ]; then
            stable_count=$((stable_count + 1))
        else
            stable_count=0
        fi
        _wait_trace "$_WAIT_TRACE_TAG event=decision all_nonblocking=$_WAIT_ALL_NONBLOCKING any_dead=$_WAIT_ANY_TERMINAL stable_count=$stable_count elapsed=$elapsed"
        _wait_exit_if_settled "$stable_count" "$elapsed"
        sleep "$_WAIT_POLL_INTERVAL"
    done
}

_wait_parse_args() {
    _WAIT_TIMEOUT=3300
    while [ $# -gt 0 ]; do
        case "$1" in
            --timeout) _WAIT_TIMEOUT="${2:?worker-cli wait: --timeout needs a value}"; shift 2 ;;
            --timeout=*) _WAIT_TIMEOUT="${1#--timeout=}"; shift ;;
            *) arg_unexpected wait "wait [--timeout SEC]" "wait takes no path and uses the current project." "$1" ;;
        esac
    done
}

_wait_list_names() {
    local project="$1"
    local listing
    listing=$(bash -c "source \"$SPAWN\" && worker_list \"\$1\"" _ "$project") || return 1
    echo "$listing" | awk '{print $1}'
}

_wait_poll_once() {
    local project="$1" names="$2"
    local wname status
    _WAIT_ALL_NONBLOCKING=1
    _WAIT_ANY_TERMINAL=0
    while IFS= read -r wname; do
        [ -z "$wname" ] && continue
        status=$(bash -c "source \"$SPAWN\" && worker_status \"\$1\" \"\$2\"" \
            _ "$wname" "$project" 2>/dev/null || echo "probe-error")
        if ! _wait_classify_status "$wname" "$status" "$project"; then
            _WAIT_ALL_NONBLOCKING=0
            break
        fi
    done <<< "$names"
}

_wait_classify_status() {
    local wname="$1" status="$2" project="$3"
    local bg
    case "$status" in
        working)
            _WAIT_SAW_WORKING=1
            _wait_trace "$_WAIT_TRACE_TAG event=poll worker=$wname status=working bg=- class=busy saw_working=$_WAIT_SAW_WORKING"
            return 1
            ;;
        idle)
            bg=$(_wait_has_live_bg_task "$wname" "$project")
            if [ "$bg" != "no" ]; then
                _wait_trace "$_WAIT_TRACE_TAG event=poll worker=$wname status=idle bg=$bg class=busy saw_working=$_WAIT_SAW_WORKING"
                return 1
            fi
            _wait_trace "$_WAIT_TRACE_TAG event=poll worker=$wname status=idle bg=no class=idle saw_working=$_WAIT_SAW_WORKING"
            return 0
            ;;
        dead)
            _WAIT_ANY_TERMINAL=1
            _wait_trace "$_WAIT_TRACE_TAG event=poll worker=$wname status=dead bg=- class=dead saw_working=$_WAIT_SAW_WORKING"
            return 0
            ;;
        *)
            _wait_trace "$_WAIT_TRACE_TAG event=poll worker=$wname status=${status// /_} bg=- class=busy saw_working=$_WAIT_SAW_WORKING"
            return 1
            ;;
    esac
}

_wait_exit_if_settled() {
    local stable_count="$1" elapsed="$2"
    if [ "$stable_count" -ge "$_WAIT_STABLE_SAMPLES" ] && [ "$_WAIT_SAW_WORKING" = "1" ]; then
        if [ "$_WAIT_ANY_TERMINAL" = "1" ]; then
            _wait_trace "$_WAIT_TRACE_TAG event=exit reason=worker_dead elapsed=$elapsed saw_working=$_WAIT_SAW_WORKING"
            echo "worker dead"
            exit 0
        fi
        _wait_trace "$_WAIT_TRACE_TAG event=exit reason=workers_idle elapsed=$elapsed saw_working=$_WAIT_SAW_WORKING"
        echo "workers idle"
        exit 0
    fi
}
