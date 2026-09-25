#!/usr/bin/env bash

worker_revive() {
    local name="$1"
    local project_path="$2"
    local session
    session=$(_worker_session_name "$project_path" "$name")

    _revive_check_session "$session" || return 2
    _revive_check_pane_dead "$session" "$name" || return 2

    local worktree
    worktree=$(_revive_resolve_worktree "$project_path" "$name") || return 2

    local jsonl
    jsonl=$(_revive_find_jsonl "$worktree") || return 2
    local session_id
    session_id=$(basename "$jsonl" .jsonl)

    _revive_load_env "$session" || return 1
    local model="$_REVIVE_MODEL" purpose="$_REVIVE_PURPOSE" parent="$_REVIVE_PARENT"

    echo "Reviving $name (session-id $session_id, model $model)"

    tmux kill-session -t "$session" 2>/dev/null || true

    _worker_proxy_setup "$name" "$project_path" || return 1

    local death_log="$HOME/.claude/worker-deaths.log"
    local runner
    runner=$(_build_revive_runner "$name" "$session" "$worktree" "$model" "$session_id" "$death_log")

    _create_worker_session "$session" "bash '$runner'"

    _revive_restore_env "$session" "$purpose" "$parent" "$model"

    tmux set-hook -t "$session" pane-died \
        "run-shell 'echo \"\$(date -Iseconds) worker=${name} session=#{session_name} status=#{pane_dead_status} signal=#{pane_dead_signal}\" >> ${death_log}'"

    _orchestrator_signal_update "$session"

    _start_worker_logger "$name" "$session" "revive"

    open_tmux_viewer "$session" &

    echo "  session: $session"
    echo "  jsonl:   $jsonl"
    echo "$session"
}

_revive_check_session() {
    local session="$1"
    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "worker_revive: session '$session' not found — worker was fully killed; use 'spawn'" >&2
        return 2
    fi
}

_revive_check_pane_dead() {
    local session="$1" name="$2"
    local pane_dead
    pane_dead=$(tmux display-message -t "${session}:^" -p "#{pane_dead}" 2>/dev/null || echo "?")
    if [ "$pane_dead" = "0" ]; then
        echo "worker_revive: worker '$name' is still running — use 'send'" >&2
        return 2
    elif [ "$pane_dead" != "1" ]; then
        echo "worker_revive: cannot determine pane state for '$session' (got: $pane_dead)" >&2
        return 2
    fi
}

_revive_resolve_worktree() {
    local project_path="$1" name="$2"
    local worktree
    if [[ "$project_path" == */.claude/worktrees/* ]]; then
        worktree="$project_path"
    else
        worktree="$project_path/.claude/worktrees/$name"
    fi
    if [ ! -d "$worktree" ]; then
        echo "worker_revive: worktree not found at $worktree — revive not possible" >&2
        return 2
    fi
    echo "$worktree"
}

_revive_find_jsonl() {
    local worktree="$1"
    local jsonl encoded_dir
    encoded_dir="$HOME/.claude/projects/$(encode_worktree_path "$worktree")"
    jsonl=$(ls -t "$encoded_dir"/*.jsonl 2>/dev/null | head -1)
    if [ -z "$jsonl" ]; then
        echo "worker_revive: no session JSONL found at $encoded_dir — context lost; use 'spawn'" >&2
        return 2
    fi
    echo "$jsonl"
}

_revive_load_env() {
    local session="$1"
    _REVIVE_MODEL=$(_tmux_env_value "$session" WORKER_MODEL) || return 1
    _REVIVE_PURPOSE=$(_tmux_env_value "$session" WORKER_PURPOSE) || return 1
    _REVIVE_PARENT=$(_tmux_env_value "$session" WORKER_PARENT) || return 1
}

_build_revive_runner() {
    local name="$1" session="$2" worktree="$3" model="$4" session_id="$5" death_log="$6"
    local proxy_env_prefix="$WORKER_PROXY_ENV_PREFIX"
    local worker_proxy_pid="$WORKER_PROXY_PID"
    local worker_live_addon="$WORKER_PROXY_LIVE_ADDON"
    local worker_live_dir="$WORKER_PROXY_LIVE_DIR"
    local worker_claude_bin="${CLAUDE_BIN:-$HOME/.local/bin/claude-280}"
    local runner
    runner=$(mktemp "/tmp/.worker_${name}_revive.XXXXXX")
    cat > "$runner" <<RUNSCRIPT
#!/usr/bin/env bash
_cleanup() {
    local _s=\$?
    echo "\$(date -Iseconds) worker=${name} session=${session} status=\$_s signal=EXIT" >> '${death_log}'
    [ -n '${worker_proxy_pid}' ] && kill '${worker_proxy_pid}' 2>/dev/null || true
    [ -n '${worker_live_addon}' ] && rm -f '${worker_live_addon}' || true
    [ -n '${worker_live_dir}' ]   && rm -rf '${worker_live_dir}' || true
    touch '/tmp/worker-${name}.done'
    rm -f '${runner}'
}
trap _cleanup EXIT INT TERM HUP
cd '${worktree}'
${proxy_env_prefix}${worker_claude_bin} --model '${model}' ${_WORKER_PERMISSION_FLAGS} --resume '${session_id}'
RUNSCRIPT
    chmod +x "$runner"
    echo "$runner"
}

_revive_restore_env() {
    local session="$1" purpose="$2" parent="$3" model="$4"
    tmux set-environment -t "$session" WORKER_SPAWNED "$(date +%H:%M)"
    tmux set-environment -t "$session" WORKER_REVIVED "$(date +%H:%M)"
    tmux set-environment -t "$session" WORKER_PURPOSE "$purpose"
    tmux set-environment -t "$session" WORKER_PARENT "$parent"
    tmux set-environment -t "$session" WORKER_MODEL "$model"
}
