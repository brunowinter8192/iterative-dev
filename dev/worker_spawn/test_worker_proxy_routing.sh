#!/usr/bin/env bash

# INFRASTRUCTURE

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SPAWN_SH="$PLUGIN_ROOT/src/spawn/tmux_spawn.sh"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
source "$SELF_DIR/../strand_runner.sh"
source "$SELF_DIR/proxy_fixture.sh"

STRANDS=(project_marker_wins session_marker_fallback strict_without_marker no_proxy_context runner_blocks_fork)

# ORCHESTRATOR

test_worker_proxy_routing_workflow() {
    strand_main "$@"
}

# FUNCTIONS

strand_cleanup() {
    local m
    for m in ${MARKERS:-}; do rm -f "$m"; done
    [ -n "${PROXY_PID:-}" ] && kill "$PROXY_PID" 2>/dev/null
    return 0
}

strand_init() {
    install_mitmdump_stub
    install_monitor_root
    export STUB_ENV_LOG="$STRAND_DIR/stub_env.log"
    PROJ="$STRAND_DIR/worker_project"
    mkdir -p "$PROJ"
    SESSION_ID="fx$$_${STRAND_NAME}"
    PROJECT_ID=$(echo -n "$PROJ" | md5 | head -c 8)
    MARKERS="/tmp/.monitor_cc_proxy_${SESSION_ID} /tmp/.monitor_cc_proxy_${PROJECT_ID}"
    source "$SPAWN_SH"
}

worker_port_of() {
    echo "$WORKER_PROXY_ENV_PREFIX" | grep -oE 'localhost:[0-9]+' | cut -d: -f2
}

strand_session_marker_fallback() {
    local main_port=$((48000 + RANDOM % 500))
    write_proxy_marker "$SESSION_ID" "$main_port"
    export PROXY_SESSION_ID="$SESSION_ID"

    _worker_proxy_setup "routefb" "$PROJ" || fail "setup returned non-zero although the session marker exists"
    PROXY_PID="$WORKER_PROXY_PID"
    local worker_port
    worker_port=$(worker_port_of)
    [ -n "$worker_port" ] && [ "$worker_port" -gt "$main_port" ] && pass "worker routed through its own proxy port $worker_port (session marker port $main_port)" \
        || fail "no proxy env prefix (prefix: '$WORKER_PROXY_ENV_PREFIX')"
    ls "$MONITOR_ROOT/src/logs"/proxy_errors_worker_"${SESSION_ID}"_routefb_*.log >/dev/null 2>&1 \
        && pass "worker log id carries the session id of the marker that was used" \
        || fail "no proxy_errors_worker_${SESSION_ID}_routefb_* log in $MONITOR_ROOT/src/logs"
    sleep 0.5
    grep -q "PROXY_PROJECT_PATH=$PROJ " "$STUB_ENV_LOG" 2>/dev/null && pass "worker proxy runs with the worker project path, not the orchestrator's" \
        || fail "PROXY_PROJECT_PATH of the worker proxy is wrong: $(cat "$STUB_ENV_LOG" 2>/dev/null)"
}

strand_project_marker_wins() {
    local project_port=$((48500 + RANDOM % 200)) session_port=$((48800 + RANDOM % 200))
    write_proxy_marker "$PROJECT_ID" "$project_port"
    write_proxy_marker "$SESSION_ID" "$session_port"
    export PROXY_SESSION_ID="$SESSION_ID"

    _worker_proxy_setup "routepw" "$PROJ" || fail "setup returned non-zero"
    PROXY_PID="$WORKER_PROXY_PID"
    ls "$MONITOR_ROOT/src/logs"/proxy_errors_worker_"${PROJECT_ID}"_routepw_*.log >/dev/null 2>&1 \
        && pass "the worker project's own marker takes precedence over the session marker" \
        || fail "log id does not carry the project id $PROJECT_ID: $(ls "$MONITOR_ROOT/src/logs")"
}

strand_strict_without_marker() {
    export PROXY_SESSION_ID="$SESSION_ID"
    local err_file="$STRAND_DIR/strict.err"

    _worker_proxy_setup "routestrict" "$PROJ" 2> "$err_file" && fail "setup returned 0 with PROXY_SESSION_ID set and no marker"
    pass "setup returned non-zero when the session runs behind the proxy but no marker exists"
    grep -q "refusing to start a worker without proxy" "$err_file" && pass "error names the refusal" || fail "no refusal message: $(cat "$err_file")"
    [ -z "$WORKER_PROXY_PID" ] && [ -z "$WORKER_PROXY_ENV_PREFIX" ] && pass "no proxy started, no env prefix exported" \
        || fail "globals not empty: pid='$WORKER_PROXY_PID' prefix='$WORKER_PROXY_ENV_PREFIX'"
    [ ! -s "$STUB_ENV_LOG" ] && pass "mitmdump was never launched" || fail "mitmdump was launched: $(cat "$STUB_ENV_LOG")"
}

strand_no_proxy_context() {
    unset PROXY_SESSION_ID

    _worker_proxy_setup "routenone" "$PROJ" || fail "setup returned non-zero without any proxy context"
    [ -z "$WORKER_PROXY_PID" ] && [ -z "$WORKER_PROXY_ENV_PREFIX" ] && pass "without proxy context the worker starts without proxy, as before" \
        || fail "globals not empty: pid='$WORKER_PROXY_PID' prefix='$WORKER_PROXY_ENV_PREFIX'"
}

strand_runner_blocks_fork() {
    WORKER_PROXY_PID="" WORKER_PROXY_ENV_PREFIX="HTTPS_PROXY=http://localhost:1 " WORKER_PROXY_LIVE_ADDON="" WORKER_PROXY_LIVE_DIR=""
    export CLAUDE_BIN=/fake/claude
    local spawn_runner revive_runner line
    spawn_runner=$(_build_spawn_runner "routefork" "$PROJ" "claude-sonnet-5" "$_WORKER_PERMISSION_FLAGS")
    revive_runner=$(_build_revive_runner "routefork" "sess" "$PROJ" "claude-sonnet-5" "sid-1" "$STRAND_DIR/death.log")
    for line in "$spawn_runner" "$revive_runner"; do
        local launch
        launch=$(grep -- '--model' "$line")
        [[ "$launch" == CLAUDE_CODE_FORK_SUBAGENT=0\ HTTPS_PROXY=* ]] && pass "$(basename "$line" | cut -c1-20)...: fork env var set ahead of the proxy env" \
            || fail "launch line lacks CLAUDE_CODE_FORK_SUBAGENT=0 prefix: $launch"
        [[ "$launch" == *"--disallowedTools Agent"* ]] && pass "launch line denies the Agent tool" \
            || fail "launch line lacks --disallowedTools Agent: $launch"
        [[ "$launch" == *"--permission-mode bypassPermissions"* ]] && pass "permission mode kept" \
            || fail "permission mode lost: $launch"
    done
    rm -f "$spawn_runner" "$revive_runner"
}

test_worker_proxy_routing_workflow "$@"
