#!/usr/bin/env bash

# INFRASTRUCTURE

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SPAWN_SH="$PLUGIN_ROOT/src/spawn/tmux_spawn.sh"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
source "$SELF_DIR/../strand_runner.sh"

STRANDS=(viewer proxy spawn)
POLL_BOUND=60

# ORCHESTRATOR

test_spawn_flow_workflow() {
    strand_main "$@"
}

# FUNCTIONS

strand_cleanup() {
    [ -n "${VIEWER_RELEASE:-}" ] && touch "$VIEWER_RELEASE"
    [ -n "${MARKER:-}" ] && rm -f "$MARKER"
    [ -n "${SPAWN_NAME:-}" ] && rm -f "/tmp/worker-logger-${SPAWN_NAME}.pid" /tmp/.worker_"${SPAWN_NAME}".* "/tmp/worker-${SPAWN_NAME}.done"
    [ -n "${PROXY_PID:-}" ] && kill "$PROXY_PID" 2>/dev/null
    return 0
}

init_project() {
    PROJ="$STRAND_DIR/spawnproj"
    mkdir -p "$PROJ"
    git init "$PROJ" -b main -q
    echo "init" > "$PROJ/init.txt"
    git -C "$PROJ" add init.txt
    git -C "$PROJ" commit -m "init" -q
}

install_viewer_stubs() {
    VIEWER_LOG="$STRAND_DIR/viewer_calls.log"
    printf '#!/usr/bin/env bash\necho "Ghostty 1.3.1"\n' > "$STRAND_DIR/bin/ghostty"
    printf '#!/usr/bin/env bash\necho "osascript $*" >> "%s"\n' "$VIEWER_LOG" > "$STRAND_DIR/bin/osascript"
    printf '#!/usr/bin/env bash\necho "open $*" >> "%s"\n' "$VIEWER_LOG" > "$STRAND_DIR/bin/open"
    chmod +x "$STRAND_DIR/bin/ghostty" "$STRAND_DIR/bin/osascript" "$STRAND_DIR/bin/open"
}

install_blocking_viewer_stubs() {
    install_viewer_stubs
    VIEWER_RELEASE="$STRAND_DIR/viewer_release"
    VIEWER_STUB_PID="$STRAND_DIR/viewer_stub.pid"
    cat > "$STRAND_DIR/bin/osascript" <<STUB
#!/usr/bin/env bash
echo "osascript \$*" >> "$VIEWER_LOG"
echo \$\$ > "$VIEWER_STUB_PID"
while [ ! -e "$VIEWER_RELEASE" ]; do sleep 0.2; done
STUB
    chmod +x "$STRAND_DIR/bin/osascript"
}

poll_until() {
    local tries=0
    while ! "$@"; do
        [ "$tries" -ge $((POLL_BOUND * 5)) ] && return 1
        sleep 0.2
        tries=$((tries + 1))
    done
}

pane_shows_mock() {
    tmux capture-pane -p -t "$1" 2>/dev/null | grep -q "MOCK Claude Code"
}

viewer_stub_started() {
    grep -q "tmux attach -t $1" "$VIEWER_LOG" 2>/dev/null && [ -s "$VIEWER_STUB_PID" ]
}

process_gone() {
    ! kill -0 "$1" 2>/dev/null
}

install_mitmdump_stub() {
    cat > "$STRAND_DIR/bin/mitmdump" <<'STUB'
#!/usr/bin/env bash
port=""
while [ $# -gt 0 ]; do
    [ "$1" = "-p" ] && port="$2"
    shift
done
exec python3 -c "
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', int(sys.argv[1])))
s.listen(1)
time.sleep(600)
" "$port"
STUB
    chmod +x "$STRAND_DIR/bin/mitmdump"
}

write_mock_claude() {
    MOCK_CLAUDE="$STRAND_DIR/mock_claude.sh"
    cat > "$MOCK_CLAUDE" <<'MOCK'
#!/usr/bin/env bash
echo "MOCK Claude Code started with args: $@"
echo "❯"
sleep 300
MOCK
    chmod +x "$MOCK_CLAUDE"
}

project_hash() {
    echo -n "$1" | md5 | head -c 8
}

strand_viewer() {
    install_viewer_stubs
    source "$SPAWN_SH"
    local session="viewer-target"
    tmux new-session -d -s "$session" "sleep 30"

    open_tmux_viewer "$session" 2>/dev/null || fail "open_tmux_viewer returned non-zero"
    pass "open_tmux_viewer returned"
    if grep -q "tmux attach -t $session" "$VIEWER_LOG" 2>/dev/null; then
        pass "viewer invoked the (stubbed) Ghostty launcher with the tmux attach command"
    else
        fail "stubbed launcher was not called with 'tmux attach -t $session' (log: $(cat "$VIEWER_LOG" 2>/dev/null))"
    fi
}

strand_proxy() {
    init_project
    install_mitmdump_stub
    source "$SPAWN_SH"

    local monitor_root="$STRAND_DIR/monitor_root" main_port=$((47000 + RANDOM % 1000))
    mkdir -p "$monitor_root/src/proxy"
    echo "# addon stub" > "$monitor_root/src/proxy_addon.py"
    printf '#!/bin/bash\ncp "$(dirname "$0")/proxy_addon.py" "$1"\nmkdir -p "$2"\n' > "$monitor_root/src/copy_proxy_live.sh"
    chmod +x "$monitor_root/src/copy_proxy_live.sh"
    MARKER="/tmp/.monitor_cc_proxy_$(project_hash "$PROJ")"
    printf '%s\n%s\n%s\n' "$main_port" "fixture" "$monitor_root" > "$MARKER"

    _worker_proxy_setup "proxyflow" "$PROJ" || fail "_worker_proxy_setup returned non-zero"
    PROXY_PID="$WORKER_PROXY_PID"

    kill -0 "$PROXY_PID" 2>/dev/null && pass "worker proxy started (PID $PROXY_PID)" || fail "worker proxy died immediately"

    local worker_port
    worker_port=$(echo "$WORKER_PROXY_ENV_PREFIX" | grep -oE 'localhost:[0-9]+' | cut -d: -f2)
    if [ -n "$worker_port" ] && [ "$worker_port" -gt "$main_port" ] && lsof -iTCP:"$worker_port" -sTCP:LISTEN >/dev/null 2>&1; then
        pass "worker proxy listens on its own port $worker_port (main port $main_port), env prefix exported to the worker"
    else
        fail "no separate listening worker port found (prefix: '$WORKER_PROXY_ENV_PREFIX')"
    fi

    if ls "$monitor_root/src/logs"/proxy_errors_worker_*_proxyflow_*.log >/dev/null 2>&1; then
        pass "worker proxy has its own per-worker log file"
    else
        fail "no per-worker proxy log file in $monitor_root/src/logs"
    fi

    kill "$PROXY_PID" 2>/dev/null
    poll_until process_gone "$PROXY_PID" && pass "worker proxy cleaned up" || fail "worker proxy still alive after kill"
}

strand_spawn() {
    init_project
    install_blocking_viewer_stubs
    write_mock_claude
    export CLAUDE_BIN="$MOCK_CLAUDE"
    SPAWN_NAME="spawnflow$$"
    source "$SPAWN_SH"

    local session="worker-$(basename "$PROJ")-$SPAWN_NAME"
    spawn_claude_worker "workers" "$SPAWN_NAME" "$PROJ" "sonnet" "Test prompt for a mock spawn." > "$STRAND_DIR/spawn_output.txt" 2>&1
    echo "  spawn output: $(cat "$STRAND_DIR/spawn_output.txt")"
    tmux has-session -t "$session" 2>/dev/null && pass "tmux session '$session' exists" || fail "tmux session '$session' not found"

    if poll_until pane_shows_mock "$session"; then
        pass "mock claude running in pane"
    else
        fail "mock claude not found in pane output: $(tmux capture-pane -p -t "$session" 2>/dev/null)"
    fi
    poll_until viewer_stub_started "$session" && pass "spawn opened the (stubbed) viewer for the session" \
        || fail "spawn did not call the viewer launcher"
    kill -0 "$(cat "$VIEWER_STUB_PID")" 2>/dev/null && pass "spawn had returned while the viewer launcher was still running" \
        || fail "viewer launcher finished before spawn returned, so blocking cannot be told apart"
    touch "$VIEWER_RELEASE"
    poll_until process_gone "$(cat "$VIEWER_STUB_PID")" || fail "viewer launcher stub did not stop after release"
    _stop_worker_logger "$SPAWN_NAME"
}

test_spawn_flow_workflow "$@"
