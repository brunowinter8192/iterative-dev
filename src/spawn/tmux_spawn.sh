#!/usr/bin/env bash
# tmux_spawn.sh — Spawn Claude Code sessions in tmux with Ghostty viewer.
#
# Usage: source this file, then call spawn_claude_worker.

set -euo pipefail

# --- Constants ---
SPAWN_READY_MARKER="ITERDEV_SPAWN_READY_a9f3c7"
SPAWN_DEFAULT_SESSION="workers"
SPAWN_SHELL_TIMEOUT=10

# --- Functions ---

# open_tmux_viewer SESSION [WINDOW_NAME]
#   Opens a new Ghostty window and attaches to the tmux session.
#   Ghostty 1.3+: Uses native AppleScript API (PR #11208).
#   Ghostty 1.2.x: Falls back to open -na with isolation flags.
open_tmux_viewer() {
    local session="$1"
    local window_name="${2:-}"

    local ghostty_version
    ghostty_version=$(ghostty +version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
    local major minor
    major=$(echo "$ghostty_version" | cut -d. -f1)
    minor=$(echo "$ghostty_version" | cut -d. -f2)

    if [ "$major" -ge 2 ] || { [ "$major" -ge 1 ] && [ "$minor" -ge 3 ]; }; then
        # Ghostty 1.3+: native AppleScript
        local attach_cmd="tmux attach -t $session"
        if [ -n "$window_name" ]; then
            attach_cmd="tmux select-window -t $session:$window_name && tmux attach -t $session"
        fi
        osascript -e "
tell application \"Ghostty\"
    activate
    set win to new window
    set t to terminal 1 of selected tab of win
    input text \"$attach_cmd\" to t
    send key \"enter\" to t
end tell
"
    else
        # Ghostty 1.2.x: -e expects separate args, not a quoted string
        if [ -n "$window_name" ]; then
            open -na Ghostty.app --args \
                --quit-after-last-window-closed=true \
                --window-save-state=never \
                -e sh -c "tmux select-window -t $session:$window_name && tmux attach -t $session"
        else
            open -na Ghostty.app --args \
                --quit-after-last-window-closed=true \
                --window-save-state=never \
                -e tmux attach -t "$session"
        fi
    fi
}

# spawn_claude_worker SESSION NAME PROJECT_PATH MODEL TASK_PROMPT [EXTRA_FLAGS]
#   Spawns Claude Code in a tmux window with the prompt as CLI argument.
#   Opens a Ghostty window to view the session.
#
#   Prints PANE_ID on success. Returns 1 on failure with error message on stderr.
spawn_claude_worker() {
    local session="${1:-$SPAWN_DEFAULT_SESSION}"
    local name="$2"
    local project_path="$3"
    local model="${4:-sonnet}"
    local task_prompt="$5"
    local extra_flags="${6:-}"

    # Ensure tmux session exists
    tmux new-session -d -s "$session" 2>/dev/null || true

    # 1. Create window, capture pane_id
    local pane_id
    pane_id=$(tmux new-window -t "$session" -n "$name" -P -F "#{pane_id}")
    if [ -z "$pane_id" ]; then
        echo "ERROR: Failed to create tmux window" >&2
        return 1
    fi

    # 2. Wait for shell ready
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

    # 3. Write prompt to temp file to avoid shell escaping issues
    local prompt_file="/tmp/spawn-prompt-${name}-$$.txt"
    echo "$task_prompt" > "$prompt_file"

    # 4. Launch Claude with prompt as CLI argument, reading from file
    local claude_cmd="cd $project_path && claude --model $model $extra_flags \"\$(cat $prompt_file)\""
    tmux send-keys -t "$pane_id" "$claude_cmd" C-m

    # 5. Open Ghostty window attached to the tmux session
    open_tmux_viewer "$session" "$name"

    # Return pane_id
    echo "$pane_id"
}

# spawn_claude_worker_from_file SESSION NAME PROJECT_PATH MODEL PROMPT_FILE [EXTRA_FLAGS]
#   Like spawn_claude_worker, but reads the task prompt from a file instead of
#   an argument. Avoids shell escaping issues with complex multi-line prompts.
spawn_claude_worker_from_file() {
    local session="${1:-$SPAWN_DEFAULT_SESSION}"
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
