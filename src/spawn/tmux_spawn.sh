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
_ORCHESTRATOR_SIGNALS_FILE="$HOME/Library/Application Support/com.brunowinter.monitor_cc_menubar/orchestrator_signals.json"

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

    # Process-tree check: pane_dead is 0 in our zsh/bash-wrapped CC setup even
    # after Claude exits (shell keeps the pane alive). The reliable signal is
    # whether a `claude` descendant of the pane PID still exists. If none →
    # CC has exited (context-limit death, crash, manual quit) — return "exited"
    # instead of falsely reporting "idle".
    local pane_pid
    pane_pid=$(tmux display-message -t "${session}:^" -p "#{pane_pid}" 2>/dev/null)
    if [ -n "$pane_pid" ]; then
        local children
        children=$(pgrep -P "$pane_pid" 2>/dev/null || true)
        if [ -z "$children" ]; then
            echo "exited"
            return 0
        fi
        local has_claude=0
        for cpid in $children; do
            if ps -o command= -p "$cpid" 2>/dev/null | grep -q "claude"; then
                has_claude=1
                break
            fi
        done
        if [ "$has_claude" = "0" ]; then
            echo "exited"
            return 0
        fi
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

    # Signal the orchestrator-send event BEFORE delivering the keys. The Monitor_CC menubar
    # treats workers with a recent signal as 'working' for auto-abort, bridging the latency
    # window between this tmux send-keys and CC's UserPromptSubmit hook firing — see
    # Monitor_CC/decisions/OldThemes/menubar_signal_grace/initial_design.md.
    _orchestrator_signal_update "$session"

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
    local extra_flags="${6:---dangerously-skip-permissions}"

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
    local worker_proxy_pid=""
    local worker_live_addon=""
    local worker_live_dir=""
    local proxy_marker="/tmp/.monitor_cc_proxy_${proxy_session_id}"
    if [ -f "$proxy_marker" ]; then
        local main_port monitor_cc_root
        main_port=$(sed -n '1p' "$proxy_marker")
        monitor_cc_root=$(sed -n '3p' "$proxy_marker")
        if [ -z "$monitor_cc_root" ] || [ ! -d "$monitor_cc_root" ]; then
            # Marker exists but no MONITOR_CC_ROOT (old format) — skip proxy setup
            monitor_cc_root=""
        fi
    fi
    if [ -f "$proxy_marker" ] && [ -n "$monitor_cc_root" ]; then
        # Find a free port starting at main_port + 1
        local worker_port=$((main_port + 1))
        while lsof -iTCP:${worker_port} -sTCP:LISTEN >/dev/null 2>&1; do
            worker_port=$((worker_port + 1))
        done
        # Generate human-readable log id: worker_{project_session_id}_{name}_{timestamp}
        # project_session_id scopes this log to the active project (mirrors _proxy_session_id_for_project in parser.py)
        local worker_log_id="worker_${proxy_session_id}_${name}_$(date +%s)"
        # Start worker-specific mitmproxy in background (live-copy to prevent hot-reload)
        local log_dir="${monitor_cc_root}/src/logs"
        mkdir -p "$log_dir"
        local worker_live_id="worker_${name}"
        local worker_live_addon="${log_dir}/.proxy_addon_live_${worker_live_id}.py"
        local worker_live_dir="${log_dir}/.proxy_live_${worker_live_id}"
        # Dedup guard: if this worker's live-copy already exists AND a mitmdump process is
        # still using it, abort rather than overwriting (which would hot-reload the running proxy).
        if [ -f "$worker_live_addon" ] && lsof "$worker_live_addon" >/dev/null 2>&1; then
            echo "ERROR: Worker proxy for '$name' is already running (live addon in use)." >&2
            echo "  Kill the existing '$name' worker or choose a different name." >&2
            return 1
        fi
        cp "${monitor_cc_root}/src/proxy_addon.py" "$worker_live_addon"
        mkdir -p "$worker_live_dir"
        cp -r "${monitor_cc_root}/src/proxy" "$worker_live_dir/"
        MONITOR_CC_ROOT="$monitor_cc_root" PROXY_LOG_ID="$worker_log_id" \
            PROXY_PROJECT_PATH="$proxy_project_path" \
            mitmdump -p "$worker_port" -s "$worker_live_addon" \
            --set flow_detail=0 -q \
            >/dev/null 2>"${log_dir}/proxy_errors_${worker_log_id}.log" &
        worker_proxy_pid=$!
        proxy_env_prefix="HTTPS_PROXY=http://localhost:${worker_port} NODE_EXTRA_CA_CERTS=~/.mitmproxy/mitmproxy-ca-cert.pem SSL_CERT_FILE=~/.mitmproxy/combined-ca.pem REQUESTS_CA_BUNDLE=~/.mitmproxy/combined-ca.pem "
    fi

    # Build a runner script so trap fires reliably on EXIT/INT/TERM/HUP regardless
    # of how the tmux pane shell is killed (tmux kill-session sends SIGHUP, which
    # cuts the ; chain before cleanup commands can run).
    local worker_claude_bin="${CLAUDE_BIN:-$HOME/.local/bin/claude-114}"
    local runner
    runner=$(mktemp "/tmp/.worker_${name}.XXXXXX")
    cat > "$runner" <<RUNSCRIPT
#!/usr/bin/env bash
_cleanup() {
    [ -n '${worker_proxy_pid}' ] && kill '${worker_proxy_pid}' 2>/dev/null || true
    [ -n '${worker_live_addon}' ] && rm -f '${worker_live_addon}' || true
    [ -n '${worker_live_dir}' ]   && rm -rf '${worker_live_dir}' || true
    touch '/tmp/worker-${name}.done'
    rm -f '${runner}'
}
trap _cleanup EXIT INT TERM HUP
cd '${project_path}'
${proxy_env_prefix}${worker_claude_bin} --model '${model}' ${extra_flags} "\$(cat '${prompt_file}')"
RUNSCRIPT
    local claude_cmd="bash '${runner}'"

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
    open_tmux_viewer "$session" &

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
    local extra_flags="${6:---dangerously-skip-permissions}"

    if [ ! -f "$prompt_file" ]; then
        echo "ERROR: Prompt file not found: $prompt_file" >&2
        return 1
    fi

    local task_prompt
    task_prompt=$(cat "$prompt_file")

    spawn_claude_worker "$session" "$name" "$project_path" "$model" "$task_prompt" "$extra_flags"
}
