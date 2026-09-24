#!/usr/bin/env bash
# worker_io.sh — pane capture, message delivery, viewer window, orchestrator signals. Sourced by tmux_spawn.sh.

# --- Helpers ---

# _orchestrator_signal_update SESSION_NAME
#   Update the orchestrator-signal file: set signals[SESSION_NAME] = now, prune entries > 1h.
#   Atomic write via tmp + os.replace. Failures are non-fatal — signal is a hint to the menubar,
#   not a correctness requirement for worker delivery. Menubar treats workers without signals
#   normally (falls through to hook-state for status).
_orchestrator_signal_update() {
    local session_name="$1"
    python3 - "$_ORCHESTRATOR_SIGNALS_FILE" "$session_name" <<'PYEOF' 2>/dev/null || true
import json, os, sys, time
path, key = sys.argv[1], sys.argv[2]
now = time.time()
try:
    data = json.loads(open(path).read())
    if not isinstance(data, dict):
        data = {}
except (FileNotFoundError, json.JSONDecodeError, OSError):
    data = {}
# prune entries > 1h old (excluding the one we're about to set)
data = {k: float(v) for k, v in data.items()
        if isinstance(v, (int, float)) and (now - float(v)) < 3600 and k != key}
data[key] = now
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f)
os.replace(tmp, path)
PYEOF
}

# _orchestrator_signal_delete SESSION_NAME
#   Remove the signal entry for SESSION_NAME (used on worker kill).
_orchestrator_signal_delete() {
    local session_name="$1"
    python3 - "$_ORCHESTRATOR_SIGNALS_FILE" "$session_name" <<'PYEOF' 2>/dev/null || true
import json, os, sys, time
path, key = sys.argv[1], sys.argv[2]
try:
    raw = open(path).read()
    data = json.loads(raw)
    if not isinstance(data, dict):
        sys.exit(0)
except (FileNotFoundError, json.JSONDecodeError, OSError):
    sys.exit(0)
data.pop(key, None)
# prune > 1h old entries while we are touching the file
now = time.time()
data = {k: float(v) for k, v in data.items()
        if isinstance(v, (int, float)) and (now - float(v)) < 3600}
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f)
os.replace(tmp, path)
PYEOF
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

# worker_capture_clean NAME [PROJECT_PATH]
#   Captures worker pane, scopes to output since last real orchestrator prompt (❯ with content),
#   applies clean filter (boot box, spinners, diff hunks, widget chrome), prints to stdout.
#   Output shape: "=== capture from <name> (since last prompt, N chars) ===" + cleaned body.
#   Fallback: if no ❯ prompt marker in scrollback → prints full cleaned buffer + warning.
#   Uses _capture_clean.py (same dir as this script) for the scope + filter logic.
worker_capture_clean() {
    local name="$1"
    local project_path="${2:-$(pwd)}"
    local session
    session=$(_worker_session_name "$project_path" "$name")

    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "ERROR: No session '$session'" >&2
        return 1
    fi

    local clean_script
    clean_script="$(dirname "${BASH_SOURCE[0]}")/_capture_clean.py"
    if [ ! -f "$clean_script" ]; then
        echo "ERROR: _capture_clean.py not found at $clean_script" >&2
        return 1
    fi

    local pane_id pane_file
    pane_id=$(tmux list-panes -t "$session" -F "#{pane_id}" | head -1)
    pane_file=$(mktemp "/tmp/.cap_pane_${name}_XXXXXX.txt")

    tmux capture-pane -p -t "$pane_id" -S - > "$pane_file"
    python3 "$clean_script" "$pane_file" "$name"
    local exit_code=$?
    rm -f "$pane_file"
    return $exit_code
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

    # Signal the orchestrator-send event BEFORE delivering the keys. The Monitor_CC menubar
    # treats workers with a recent signal as 'working' for auto-abort, bridging the latency
    # window between this tmux send-keys and CC's UserPromptSubmit hook firing — see
    # Monitor_CC process-docs (menubar signal grace).
    _orchestrator_signal_update "$session"

    # Paste message via bracketed paste (-p), then send Enter as key event.
    # Without -p, CC 2.1.280 loses the head of long/multi-line pastes and Enter
    # doesn't submit (process-docs/worker_message_delivery/2026-09-23_paste_breaks_on_cc_280.md).
    # Sleep prevents race condition where Enter arrives before the paste renders.
    printf '%s' "$message" | tmux load-buffer -
    tmux paste-buffer -d -p -t "$pane_id"
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
