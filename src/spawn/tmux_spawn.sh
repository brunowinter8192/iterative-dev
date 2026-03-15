#!/usr/bin/env bash
# tmux_spawn.sh — Spawn Claude Code sessions in tmux with Ghostty viewer.
#
# Architecture: One tmux session per worker (session name = "worker-<name>").
# Each Ghostty window attaches to its own session — no sync, no zombies.
#
# Usage: source this file, then call spawn_claude_worker.
#
# Orchestration: worker_list, worker_capture, worker_send allow the main
# agent to monitor and interact with running workers.

set -euo pipefail

# --- Constants ---
SPAWN_READY_MARKER="ITERDEV_SPAWN_READY_a9f3c7"
SPAWN_SHELL_TIMEOUT=10

# --- Orchestration ---

# worker_list
#   Lists all active worker sessions (names only, without "worker-" prefix).
worker_list() {
    tmux list-sessions -F "#{session_name}" 2>/dev/null \
        | grep "^worker-" \
        | sed 's/^worker-//' \
        || true
}

# worker_capture NAME [LINES]
#   Captures worker pane content to /tmp/worker-<name>-pane.txt.
#   LINES: number of scrollback lines to capture (default: all).
#   Returns: path to the capture file.
worker_capture() {
    local name="$1"
    local lines="${2:-}"
    local session="worker-${name}"
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

# worker_send NAME MESSAGE
#   Sends text input to a running worker's tmux pane (followed by Enter).
worker_send() {
    local name="$1"
    local message="$2"
    local session="worker-${name}"

    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "ERROR: No session '$session'" >&2
        return 1
    fi

    local pane_id
    pane_id=$(tmux list-panes -t "$session" -F "#{pane_id}" | head -1)

    tmux send-keys -t "$pane_id" "$message" C-m
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
    input text \"tmux attach -t $session\" to t
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
#   Spawns Claude Code in its own tmux session ("worker-<name>").
#   Opens a Ghostty window to view the session.
#
#   Note: SESSION parameter is kept for API compatibility but ignored.
#   Each worker gets its own session named "worker-<name>".
#
#   Prints PANE_ID on success. Returns 1 on failure with error message on stderr.
spawn_claude_worker() {
    local _session_ignored="${1:-}"
    local name="$2"
    local project_path="$3"
    local model="${4:-sonnet}"
    local task_prompt="$5"
    local extra_flags="${6:-}"

    local session="worker-${name}"

    # Kill existing session with same name (clean restart)
    tmux kill-session -t "$session" 2>/dev/null || true

    # Create dedicated session for this worker
    tmux new-session -d -s "$session"

    # Capture pane_id of the default window
    local pane_id
    pane_id=$(tmux list-panes -t "$session" -F "#{pane_id}" | head -1)
    if [ -z "$pane_id" ]; then
        echo "ERROR: Failed to get pane_id for session $session" >&2
        return 1
    fi

    # Wait for shell ready
    tmux send-keys -t "$pane_id" "echo $SPAWN_READY_MARKER" C-m
    local elapsed=0
    while (( $(echo "$elapsed < $SPAWN_SHELL_TIMEOUT" | bc -l) )); do
        local content
        content=$(tmux capture-pane -p -t "$pane_id" 2>/dev/null || true)
        if echo "$content" | grep -qF "$SPAWN_READY_MARKER"; then
            break
        fi
        sleep 0.3
        elapsed=$(echo "$elapsed + 0.3" | bc -l)
    done

    # Write prompt to temp file to avoid shell escaping issues
    local prompt_file="/tmp/spawn-prompt-${name}-$$.txt"
    echo "$task_prompt" > "$prompt_file"

    # Launch Claude with prompt as CLI argument, reading from file
    local claude_cmd="cd $project_path && claude --model $model $extra_flags \"\$(cat $prompt_file)\""
    tmux send-keys -t "$pane_id" "$claude_cmd" C-m

    # Open Ghostty window attached to this worker's session
    open_tmux_viewer "$session"

    # Return pane_id
    echo "$pane_id"
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
