#!/usr/bin/env bash

# INFRASTRUCTURE

_ORCHESTRATOR_SIGNALS_FILE="$HOME/Library/Application Support/com.brunowinter.monitor-cc-menubar/orchestrator_signals.json"

# FUNCTIONS

_orchestrator_signal_update() {
    local session_name="$1"
    python3 - "$_ORCHESTRATOR_SIGNALS_FILE" "$session_name" <<'PYEOF'
import json, os, sys, time
path, key = sys.argv[1], sys.argv[2]
now = time.time()
try:
    data = json.loads(open(path).read())
except FileNotFoundError:
    data = {}
if not isinstance(data, dict):
    raise ValueError(f"{path} is not a JSON object")
data = {k: float(v) for k, v in data.items()
        if isinstance(v, (int, float)) and (now - float(v)) < 3600 and k != key}
data[key] = now
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = f"{path}.tmp.{os.getpid()}"
with open(tmp, "w") as f:
    json.dump(data, f)
os.replace(tmp, path)
PYEOF
}

_orchestrator_signal_delete() {
    local session_name="$1"
    python3 - "$_ORCHESTRATOR_SIGNALS_FILE" "$session_name" <<'PYEOF'
import json, os, sys, time
path, key = sys.argv[1], sys.argv[2]
try:
    data = json.loads(open(path).read())
except FileNotFoundError:
    sys.exit(0)
if not isinstance(data, dict):
    raise ValueError(f"{path} is not a JSON object")
data.pop(key, None)
now = time.time()
data = {k: float(v) for k, v in data.items()
        if isinstance(v, (int, float)) and (now - float(v)) < 3600}
tmp = f"{path}.tmp.{os.getpid()}"
with open(tmp, "w") as f:
    json.dump(data, f)
os.replace(tmp, path)
PYEOF
}

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

    _orchestrator_signal_update "$session"

    printf '%s' "$message" | tmux load-buffer -
    tmux paste-buffer -d -p -t "$pane_id"
    sleep 0.2
    tmux send-keys -t "$pane_id" Enter
}

open_tmux_viewer() {
    local session="$1"

    local ghostty_version
    ghostty_version=$(ghostty +version | head -1 | grep -oE '[0-9]+\.[0-9]+') || {
        echo "ERROR: cannot read the ghostty version" >&2
        return 1
    }
    local major minor
    major=$(echo "$ghostty_version" | cut -d. -f1)
    minor=$(echo "$ghostty_version" | cut -d. -f2)

    if [ "$major" -ge 2 ] || { [ "$major" -ge 1 ] && [ "$minor" -ge 3 ]; }; then
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
        open -na Ghostty.app --args \
            --quit-after-last-window-closed=true \
            --window-save-state=never \
            -e tmux attach -t "$session"
    fi
}
