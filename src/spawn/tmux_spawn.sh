#!/usr/bin/env bash

set -euo pipefail

_WORKER_PERMISSION_FLAGS="--permission-mode bypassPermissions"
_ORCHESTRATOR_SIGNALS_FILE="$HOME/Library/Application Support/com.brunowinter.monitor-cc-menubar/orchestrator_signals.json"

_SPAWN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SPAWN_LIB_DIR/worker_io.sh"
source "$_SPAWN_LIB_DIR/worker_status.sh"
source "$_SPAWN_LIB_DIR/worker_log_sidecar.sh"
source "$_SPAWN_LIB_DIR/worker_proxy.sh"
source "$_SPAWN_LIB_DIR/worker_revive.sh"

_worker_project_name() {
    local project_path="$1"
    if [[ "$project_path" == */.claude/worktrees/* ]]; then
        basename "$(echo "$project_path" | sed 's|/.claude/worktrees/.*||')"
    else
        basename "$project_path"
    fi
}

_worker_session_name() {
    local project_path="$1"
    local name="$2"
    local project
    project=$(_worker_project_name "$project_path")
    echo "worker-${project}-${name}"
}

_resolve_worker_model() {
    local file="${MODEL_SELECTION_FILE:-$HOME/.claude/shared-rules/model_selection.json}"
    local worker=""
    if command -v jq >/dev/null 2>&1 && [ -f "$file" ]; then
        worker=$(jq -r '.worker // empty' "$file" 2>/dev/null || true)
    fi
    if [ -n "$worker" ]; then
        echo "$worker"
    else
        echo "claude-sonnet-5"
    fi
}

spawn_claude_worker() {
    local _session_ignored="${1:-}"
    local name="$2"
    local project_path="$3"
    local model="${4:-$(_resolve_worker_model)}"
    local task_prompt="$5"
    local extra_flags="${6:-$_WORKER_PERMISSION_FLAGS}"

    local session
    session=$(_worker_session_name "$project_path" "$name")

    tmux kill-session -t "$session" 2>/dev/null || true

    local prompt_file="/tmp/spawn-prompt-${name}-$$.txt"
    echo "$task_prompt" > "$prompt_file"

    _worker_proxy_setup "$name" "$project_path" || { rm -f "$prompt_file"; return 1; }

    local runner
    runner=$(_build_spawn_runner "$name" "$project_path" "$model" "$extra_flags")

    _create_worker_session "$session" "bash '${runner}'"

    _orchestrator_signal_update "$session"

    _store_spawn_metadata "$session" "$model" "$task_prompt"

    _start_worker_logger "$name" "$session" "spawn"

    open_tmux_viewer "$session" &

    local pane_id
    pane_id=$(tmux list-panes -t "$session" -F "#{pane_id}" | head -1)
    if ! _wait_for_input_ready "$pane_id" "$session"; then
        rm -f "$prompt_file"
        return 1
    fi

    _inject_prompt "$pane_id" "$task_prompt"
    rm -f "$prompt_file"

    echo "$session"
}

_build_spawn_runner() {
    local name="$1" project_path="$2" model="$3" extra_flags="$4"
    local proxy_env_prefix="$WORKER_PROXY_ENV_PREFIX"
    local worker_proxy_pid="$WORKER_PROXY_PID"
    local worker_live_addon="$WORKER_PROXY_LIVE_ADDON"
    local worker_live_dir="$WORKER_PROXY_LIVE_DIR"
    local worker_claude_bin="${CLAUDE_BIN:-$HOME/.local/bin/claude-280}"
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
${proxy_env_prefix}${worker_claude_bin} --model '${model}' ${extra_flags}
RUNSCRIPT
    echo "$runner"
}

_create_worker_session() {
    local session="$1"
    local command="$2"
    tmux new-session -d -s "$session" "$command" \; \
        set-option -p -t "$session" remain-on-exit on \; \
        set-option -t "$session" history-limit 50000
}

_store_spawn_metadata() {
    local session="$1" model="$2" task_prompt="$3"
    tmux set-environment -t "$session" WORKER_SPAWNED "$(date +%H:%M)"
    local purpose
    purpose=$(echo "$task_prompt" | grep -m1 "^# " | sed 's/^# //' || echo "")
    [ -z "$purpose" ] && purpose="(?)"
    tmux set-environment -t "$session" WORKER_PURPOSE "$purpose"
    tmux set-environment -t "$session" WORKER_PARENT "${CLAUDE_SESSION_ID:-unknown}"
    tmux set-environment -t "$session" WORKER_MODEL "$model"
}

_wait_for_input_ready() {
    local pane_id="$1" session="$2"
    local deadline=$(( $(date +%s) + 30 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        tmux capture-pane -p -t "$pane_id" 2>/dev/null | grep -q '^❯' && break
        sleep 0.3
    done
    if ! tmux capture-pane -p -t "$pane_id" 2>/dev/null | grep -q '^❯'; then
        echo "spawn_claude_worker: CC did not reach input-ready state within 30s (session=$session)" >&2
        return 1
    fi
    return 0
}

_inject_prompt() {
    local pane_id="$1" task_prompt="$2"
    printf '%s' "$task_prompt" | tmux load-buffer -
    tmux paste-buffer -d -p -t "$pane_id"
    sleep 0.2
    tmux send-keys -t "$pane_id" Enter
}

spawn_claude_worker_from_file() {
    local session="${1:-}"
    local name="$2"
    local project_path="$3"
    local model="${4:-$(_resolve_worker_model)}"
    local prompt_file="$5"
    local extra_flags="${6:-$_WORKER_PERMISSION_FLAGS}"

    if [ ! -f "$prompt_file" ]; then
        echo "ERROR: Prompt file not found: $prompt_file" >&2
        return 1
    fi

    local task_prompt
    task_prompt=$(cat "$prompt_file")

    spawn_claude_worker "$session" "$name" "$project_path" "$model" "$task_prompt" "$extra_flags"
}
