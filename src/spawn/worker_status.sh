#!/usr/bin/env bash

_worker_detect_status() {
    local session="$1"

    if _worker_pane_is_dead "$session"; then
        echo "dead"
        return 0
    fi

    if _worker_claude_process_gone "$session"; then
        echo "dead"
        return 0
    fi

    local jsonl
    jsonl=$(_worker_session_jsonl "$session")

    if [ -n "$jsonl" ] && _worker_jsonl_context_limit "$jsonl"; then
        echo "dead"
        return 0
    fi

    local hook_status=""
    if [ -n "$jsonl" ]; then
        hook_status=$(_worker_hook_status "$jsonl") || return 1
    fi
    if [ "$hook_status" = "idle" ]; then
        echo "idle"
        return 0
    fi

    if _worker_pane_quiet "$session"; then
        echo "idle"
        return 0
    fi
    echo "working"
}

_worker_pane_is_dead() {
    local session="$1"
    local dead
    dead=$(tmux display-message -t "${session}:^" -p "#{pane_dead}" 2>/dev/null || echo "?")
    [ "$dead" = "1" ]
}

_worker_claude_process_gone() {
    local session="$1"
    local pane_pid
    pane_pid=$(tmux display-message -t "${session}:^" -p "#{pane_pid}" 2>/dev/null || true)
    [ -n "$pane_pid" ] || return 1
    local children
    children=$(pgrep -P "$pane_pid" 2>/dev/null || true)
    [ -n "$children" ] || return 0
    local cpid
    for cpid in $children; do
        if ps -o command= -p "$cpid" 2>/dev/null | grep -q "claude"; then
            return 1
        fi
    done
    return 0
}

_worker_session_jsonl() {
    local session="$1"
    local worktree encoded
    worktree=$(tmux display-message -t "${session}:^" -p "#{pane_current_path}" 2>/dev/null || true)
    [ -n "$worktree" ] || return 0
    encoded=$(echo "$worktree" | tr '/_.' '-')
    ls -t "$HOME/.claude/projects/${encoded}"/*.jsonl 2>/dev/null | head -1 || true
}

_worker_jsonl_context_limit() {
    local jsonl="$1"
    [ -f "$jsonl" ] || return 1
    local last_assistant
    last_assistant=$(tail -n 200 "$jsonl" 2>/dev/null \
        | jq -c -s '[.[] | select(.type=="assistant")] | last // empty' 2>/dev/null || true)
    if [ -z "$last_assistant" ] || [ "$last_assistant" = "null" ]; then
        return 1
    fi
    local marker_model marker_is_err marker_err marker_text
    marker_model=$(echo "$last_assistant" | jq -r '.message.model // empty' 2>/dev/null || true)
    marker_is_err=$(echo "$last_assistant" | jq -r '.isApiErrorMessage // false' 2>/dev/null || true)
    marker_err=$(echo "$last_assistant" | jq -r '.error // empty' 2>/dev/null || true)
    marker_text=$(echo "$last_assistant" | jq -r '[.message.content[]? | select(.type=="text") | .text] | join(" ")' 2>/dev/null || true)
    [ "$marker_model" = "<synthetic>" ] && [ "$marker_is_err" = "true" ] \
        && [ "$marker_err" = "invalid_request" ] && [[ "$marker_text" == *"Prompt is too long"* ]]
}

_worker_hook_status() {
    local jsonl="$1"
    local session_id hook_status
    session_id=$(basename "$jsonl" .jsonl)
    local hook_file="$HOME/Library/Application Support/com.brunowinter.monitor-cc-menubar/hooks.json"
    if [ ! -f "$hook_file" ]; then
        echo "ERROR: hooks file not found: $hook_file" >&2
        return 1
    fi
    hook_status=$(jq -r --arg sid "$session_id" '.[$sid].status // ""' "$hook_file") || {
        echo "ERROR: cannot read hook status from $hook_file" >&2
        return 1
    }
    [ "$hook_status" = "null" ] && hook_status=""
    echo "$hook_status"
}

_worker_pane_quiet() {
    local session="$1"
    local wa now_ts
    wa=$(tmux display-message -t "${session}:^" -p "#{window_activity}" 2>/dev/null || true)
    if [[ "$wa" =~ ^[0-9]+$ ]] && [ "$wa" -gt 0 ]; then
        now_ts=$(date +%s)
        [ $((now_ts - wa)) -gt 10 ]
        return
    fi
    return 1
}

worker_list() {
    local project_path="${1:-$(pwd)}"
    local project
    project=$(_worker_project_name "$project_path")
    local prefix="worker-${project}-"
    local sessions
    sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null \
        | grep "^${prefix}" || true)

    if [ -z "$sessions" ]; then
        return 0
    fi

    while IFS= read -r session_name; do
        local name="${session_name#$prefix}"
        local status
        if ! status=$(_worker_detect_status "$session_name"); then
            echo "worker_list: status probe failed for $session_name, showing working" >&2
            status="working"
        fi
        local spawned
        spawned=$(_tmux_env_value "$session_name" WORKER_SPAWNED) || return 1
        local purpose
        purpose=$(_tmux_env_value "$session_name" WORKER_PURPOSE) || return 1
        echo "$name  $status  $spawned  $purpose"
    done <<< "$sessions"
}

worker_status() {
    local name="$1"
    local project_path="${2:-$(pwd)}"
    local session
    session=$(_worker_session_name "$project_path" "$name")

    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "dead"
        return 0
    fi

    local raw
    raw=$(_worker_detect_status "$session") || return 1
    echo "$raw"
}
