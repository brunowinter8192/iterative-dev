#!/usr/bin/env bash
# worker_status.sh — worker status detection, list and status queries. Sourced by tmux_spawn.sh.

# _worker_detect_status SESSION
#   Returns status: working, idle, or dead — a closed three-value vocabulary (2026-09-02).
#   Shared logic used by worker_list and worker_status.
#   'dead': cannot accept a message anymore — tmux session gone (caller-side, see
#   worker_status), #{pane_dead}=1, no claude descendant under the pane pid, or the
#   session JSONL's last assistant message is Claude Code's client-side context-limit
#   marker (anthropics/claude-code #90113, #23377: message.model=="<synthetic>" + text
#   "Prompt is too long" + isApiErrorMessage=true + error="invalid_request" — every later
#   input fails the same way until /compact or /clear).
#   'idle': hooks.json status idle (Stop hook fired), OR status working but
#   #{window_activity} stale > 10s — the ESC-interrupt case: process alive, Stop hook
#   never fired, pane quiet. Same 10s rule applies when there is no hook data at all
#   (fresh spawn pre-JSONL, no hook entry, unreadable hooks file) — a quiet pane with no
#   data is still read as idle, not as a distinct placeholder state.
#   'working': the default — hook status working with fresh activity, or no dead signal
#   and no idle signal (including every case that used to report "unknown").
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
        hook_status=$(_worker_hook_status "$jsonl")
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

# _worker_pane_is_dead SESSION
#   Returns 0 when #{pane_dead}=1. A failed pane query (tmux hiccup) is no positive dead
#   signal — fail-open toward "working".
_worker_pane_is_dead() {
    local session="$1"
    local dead
    dead=$(tmux display-message -t "${session}:^" -p "#{pane_dead}" 2>/dev/null || echo "?")
    [ "$dead" = "1" ]
}

# _worker_claude_process_gone SESSION
#   Returns 0 when the pane pid is known but has no `claude` descendant. Process-tree check:
#   pane_dead is 0 in our zsh/bash-wrapped CC setup even after Claude exits (shell keeps the
#   pane alive), so the reliable signal is whether a `claude` child of the pane PID exists.
#   Unknown pane pid returns 1 (no positive signal).
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

# _worker_session_jsonl SESSION
#   Echoes the newest session JSONL path for the pane's cwd, or nothing when unresolvable.
#   CC encoding: replace /, _, . with - (matches Monitor_CC/src/session_finder.py:encode_project_path).
_worker_session_jsonl() {
    local session="$1"
    local worktree encoded
    worktree=$(tmux display-message -t "${session}:^" -p "#{pane_current_path}" 2>/dev/null || true)
    [ -n "$worktree" ] || return 0
    encoded=$(echo "$worktree" | tr '/_.' '-')
    ls -t "$HOME/.claude/projects/${encoded}"/*.jsonl 2>/dev/null | head -1 || true
}

# _worker_jsonl_context_limit JSONL
#   Returns 0 when the LAST assistant-type entry is the synthetic rejection Claude Code writes
#   when it blocks a turn for prompt length — the worker cannot take another message until
#   /compact or /clear, so this counts as "dead". Bounded to the last 200 lines (tail, not a
#   full slurp) — a multi-megabyte session JSONL must stay cheap under `wait`'s 5s poll cadence.
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

# _worker_hook_status JSONL
#   Echoes the hooks.json status for the session id derived from JSONL, or empty when absent.
_worker_hook_status() {
    local jsonl="$1"
    local session_id hook_status
    session_id=$(basename "$jsonl" .jsonl)
    local hook_file="$HOME/Library/Application Support/com.brunowinter.monitor-cc-menubar/hooks.json"
    hook_status=$(jq -r --arg sid "$session_id" '.[$sid].status // ""' "$hook_file" 2>/dev/null || true)
    [ "$hook_status" = "null" ] && hook_status=""
    echo "$hook_status"
}

# _worker_pane_quiet SESSION
#   Returns 0 when the pane has been inactive > 10s — applies whether hook status is "working"
#   or entirely absent (ESC-interrupt / crash / no-data-yet). Mirrors menubar discover.py:178-181
#   (WORKING_THRESHOLD_SECS=10, #{window_activity}). Fail-open: activity unreadable or
#   non-positive returns 1.
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

# worker_list [PROJECT_PATH]
#   Lists active worker sessions for the given project (default: pwd).
#   Output: NAME  STATUS  SPAWNED  PURPOSE per line (STATUS: working/idle/dead).
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
        status=$(_worker_detect_status "$session_name" 2>/dev/null || echo "working")
        local spawned
        spawned=$(tmux show-environment -t "$session_name" WORKER_SPAWNED 2>/dev/null | cut -d= -f2)
        [ -z "$spawned" ] && spawned="(?)"
        local purpose
        purpose=$(tmux show-environment -t "$session_name" WORKER_PURPOSE 2>/dev/null | cut -d= -f2)
        [ -z "$purpose" ] && purpose="(?)"
        echo "$name  $status  $spawned  $purpose"
    done <<< "$sessions"
}

# worker_status NAME [PROJECT_PATH]
#   Returns status: working, idle, or dead.
#   working = Claude Code is actively processing (the default; also every no-data case)
#   idle = waiting for input — Stop hook fired, or process alive with a quiet pane (ESC)
#   dead = cannot accept a message anymore — no session, pane dead, no claude child, or
#   the JSONL's last assistant message is the context-limit marker
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
    raw=$(_worker_detect_status "$session")
    echo "$raw"
}
