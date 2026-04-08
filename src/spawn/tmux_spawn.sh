#!/usr/bin/env bash
# tmux_spawn.sh — Spawn Claude Code sessions in tmux with Ghostty viewer.
#
# Architecture: One tmux session per worker (session name = "worker-<project>-<name>").
# Project-scoped: workers from different projects never collide.
# Each Ghostty window attaches to its own session — no sync, no zombies.
# Direct command arg to tmux new-session (no shell-ready polling).
# remain-on-exit on for status detection via #{pane_dead}.
#
# Usage: source this file, then call spawn_claude_worker.
#
# Orchestration: worker_list, worker_status, worker_capture, worker_send allow
# the main agent to monitor and interact with running workers.

set -euo pipefail

# --- Constants ---

# --- Helpers ---

# _worker_project_name PROJECT_PATH
#   Derives project name from project path.
#   Strips .claude/worktrees/<name> suffix if path is a worktree.
#   Example: /path/to/RAG/.claude/worktrees/foo → RAG
#   Example: /path/to/RAG → RAG
_worker_project_name() {
    local project_path="$1"
    if [[ "$project_path" == */.claude/worktrees/* ]]; then
        basename "$(echo "$project_path" | sed 's|/.claude/worktrees/.*||')"
    else
        basename "$project_path"
    fi
}

# _worker_session_name PROJECT_PATH NAME
#   Returns the full tmux session name: "worker-<project>-<name>"
_worker_session_name() {
    local project_path="$1"
    local name="$2"
    local project
    project=$(_worker_project_name "$project_path")
    echo "worker-${project}-${name}"
}

# --- Orchestration ---

# _worker_detect_status SESSION
#   Returns status: working, idle, exited, or unknown.
#   Shared logic used by worker_list and worker_status.
#   Uses window_activity timestamp (last output to window). Claude Code updates
#   a live timer every second during thinking — so activity stays fresh
#   while working. When idle (prompt visible, no output), activity goes stale.
#   Workers have 1 window with 1 pane, so window_activity == pane activity.
#   Note: pane_activity does not exist in all tmux versions; window_activity does.
_worker_detect_status() {
    local session="$1"
    local idle_threshold=10

    local dead
    dead=$(tmux display-message -t "${session}:^" -p "#{pane_dead}" 2>/dev/null || echo "?")
    if [ "$dead" = "1" ]; then
        echo "exited"
        return 0
    elif [ "$dead" != "0" ]; then
        echo "unknown"
        return 1
    fi

    local now last_activity delta
    now=$(date +%s)
    last_activity=$(tmux list-panes -t "$session" -F "#{window_activity}" 2>/dev/null | head -1)
    delta=$((now - ${last_activity:-0}))

    if [ "$delta" -gt "$idle_threshold" ]; then
        echo "idle"
    else
        echo "working"
    fi
}

# worker_list [PROJECT_PATH]
#   Lists active worker sessions for the given project (default: pwd).
#   Output: NAME  STATUS  SPAWNED  PURPOSE per line (STATUS: working/idle/exited/unknown).
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
        status=$(_worker_detect_status "$session_name" 2>/dev/null || echo "unknown")
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
#   Returns status: working, idle, exited, or unknown.
#   working = Claude Code is actively processing
#   idle = Claude Code is waiting for input (prompt visible)
#   exited = pane process has terminated
worker_status() {
    local name="$1"
    local project_path="${2:-$(pwd)}"
    local session
    session=$(_worker_session_name "$project_path" "$name")

    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "unknown"
        return 1
    fi

    _worker_detect_status "$session"
}

# worker_capture NAME [LINES] [PROJECT_PATH]
#   Captures worker pane content to /tmp/worker-<name>-pane.txt.
#   LINES: number of scrollback lines to capture (default: all).
#   PROJECT_PATH: project the worker belongs to (default: pwd).
#   Returns: path to the capture file.
worker_capture() {
    local name="$1"
    local lines="${2:-}"
    local project_path="${3:-$(pwd)}"
    local session
    session=$(_worker_session_name "$project_path" "$name")
    local outfile="/tmp/worker-${name}-pane.txt"

    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "ERROR: No session '$session'" >&2
        return 1
    fi

    local pane_id
    pane_id=$(tmux list-panes -t "$session" -F "#{pane_id}" | head -1)

    if [ -n "$lines" ]; then
        tmux capture-pane -p -t "$pane_id" -S "-${lines}" > "$outfile"
    else
        tmux capture-pane -p -t "$pane_id" -S - > "$outfile"
    fi

    echo "$outfile"
}

# worker_send NAME MESSAGE [PROJECT_PATH]
#   Sends text input to a running worker's tmux pane (followed by Enter).
#   PROJECT_PATH: project the worker belongs to (default: pwd).
worker_send() {
    local name="$1"
    local message="$2"
    local project_path="${3:-$(pwd)}"
    local session
    session=$(_worker_session_name "$project_path" "$name")

    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "ERROR: No session '$session'" >&2
        return 1
    fi

    local pane_id
    pane_id=$(tmux list-panes -t "$session" -F "#{pane_id}" | head -1)

    # Paste message, then send Enter as key event.
    # Claude Code TUI ignores pasted newlines as submit — needs real key event.
    # Sleep prevents race condition where Enter arrives before paste completes.
    printf '%s' "$message" | tmux load-buffer -
    tmux paste-buffer -d -t "$pane_id"
    sleep 0.2
    tmux send-keys -t "$pane_id" Enter
}

# --- Functions ---

# open_tmux_viewer SESSION
#   Opens a new Ghostty window and attaches to the tmux session.
#   Ghostty 1.3+: Uses native AppleScript API (PR #11208).
#   Ghostty 1.2.x: Falls back to open -na with isolation flags.
open_tmux_viewer() {
    local session="$1"

    local ghostty_version
    ghostty_version=$(ghostty +version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
    local major minor
    major=$(echo "$ghostty_version" | cut -d. -f1)
    minor=$(echo "$ghostty_version" | cut -d. -f2)

    if [ "$major" -ge 2 ] || { [ "$major" -ge 1 ] && [ "$minor" -ge 3 ]; }; then
        # Ghostty 1.3+: native AppleScript
        osascript -e "
tell application \"Ghostty\"
    activate
    set win to new window
    set t to terminal 1 of selected tab of win
    input text \"tmux attach -t $session; exit\" to t
    send key \"enter\" to t
end tell
"
    else
        # Ghostty 1.2.x: -e expects separate args, not a quoted string
        open -na Ghostty.app --args \
            --quit-after-last-window-closed=true \
            --window-save-state=never \
            -e tmux attach -t "$session"
    fi
}

# spawn_claude_worker SESSION_IGNORED NAME PROJECT_PATH MODEL TASK_PROMPT [EXTRA_FLAGS]
#   Spawns Claude Code in its own tmux session ("worker-<project>-<name>").
#   Opens a Ghostty window to view the session.
#
#   Note: SESSION parameter is kept for API compatibility but ignored.
#   Each worker gets its own session named "worker-<project>-<name>".
#   Project prefix is derived from basename of PROJECT_PATH (worktree-aware).
#
#   Uses direct command arg to tmux new-session (no shell-ready polling).
#   Sets remain-on-exit on for status detection via #{pane_dead}.
spawn_claude_worker() {
    local _session_ignored="${1:-}"
    local name="$2"
    local project_path="$3"
    local model="${4:-sonnet}"
    local task_prompt="$5"
    local extra_flags="${6:-}"

    local session
    session=$(_worker_session_name "$project_path" "$name")

    # Kill existing session with same name (clean restart for THIS project + worker name)
    tmux kill-session -t "$session" 2>/dev/null || true

    # Write prompt to temp file to avoid shell escaping issues
    local prompt_file="/tmp/spawn-prompt-${name}-$$.txt"
    echo "$task_prompt" > "$prompt_file"

    # Detect mitmproxy: strip worktree suffix to get original project path for hash
    local proxy_project_path="$project_path"
    if [[ "$project_path" == */.claude/worktrees/* ]]; then
        proxy_project_path="${project_path%%/.claude/worktrees/*}"
    fi
    local proxy_session_id
    if command -v md5 >/dev/null 2>&1; then
        proxy_session_id=$(echo -n "$proxy_project_path" | md5 | head -c 8)
    else
        proxy_session_id=$(echo -n "$proxy_project_path" | md5sum | head -c 8)
    fi
    local proxy_env_prefix=""
    local proxy_marker="/tmp/.monitor_cc_proxy_${proxy_session_id}"
    if [ -f "$proxy_marker" ]; then
        local proxy_port
        proxy_port=$(cat "$proxy_marker")
        proxy_env_prefix="HTTPS_PROXY=http://localhost:${proxy_port} NODE_EXTRA_CA_CERTS=~/.mitmproxy/mitmproxy-ca-cert.pem SSL_CERT_FILE=~/.mitmproxy/combined-ca.pem REQUESTS_CA_BUNDLE=~/.mitmproxy/combined-ca.pem "
    fi

    # Build claude command with .done signal chained after exit
    local claude_cmd="cd $project_path && ${proxy_env_prefix}claude-patched --model $model $extra_flags \"\$(cat $prompt_file)\" ; touch '/tmp/worker-${name}.done'"

    # Create session with command as direct arg (no polling needed).
    # Atomic remain-on-exit via ; chain — set before process can exit.
    tmux new-session -d -s "$session" "$claude_cmd" \; \
        set-option -p -t "$session" remain-on-exit on

    # Store spawn metadata for worker_list display
    tmux set-environment -t "$session" WORKER_SPAWNED "$(date +%H:%M)"
    local purpose
    purpose=$(echo "$task_prompt" | grep -m1 "^# " | sed 's/^# //' || echo "")
    [ -z "$purpose" ] && purpose="(?)"
    tmux set-environment -t "$session" WORKER_PURPOSE "$purpose"
    tmux set-environment -t "$session" WORKER_PARENT "${CLAUDE_SESSION_ID:-unknown}"
    tmux set-environment -t "$session" WORKER_MODEL "$model"

    # Open Ghostty window attached to this worker's session
    open_tmux_viewer "$session"

    # Return session name (pane_id no longer needed — use session:^ for queries)
    echo "$session"
}

# spawn_claude_worker_from_file SESSION NAME PROJECT_PATH MODEL PROMPT_FILE [EXTRA_FLAGS]
#   Like spawn_claude_worker, but reads the task prompt from a file instead of
#   an argument. Avoids shell escaping issues with complex multi-line prompts.
spawn_claude_worker_from_file() {
    local session="${1:-}"
    local name="$2"
    local project_path="$3"
    local model="${4:-sonnet}"
    local prompt_file="$5"
    local extra_flags="${6:-}"

    if [ ! -f "$prompt_file" ]; then
        echo "ERROR: Prompt file not found: $prompt_file" >&2
        return 1
    fi

    local task_prompt
    task_prompt=$(cat "$prompt_file")

    spawn_claude_worker "$session" "$name" "$project_path" "$model" "$task_prompt" "$extra_flags"
}
