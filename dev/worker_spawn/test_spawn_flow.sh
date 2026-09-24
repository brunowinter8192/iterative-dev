#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SPAWN_SH="$PLUGIN_ROOT/src/spawn/tmux_spawn.sh"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
source "$SELF_DIR/../strand_runner.sh"

STRANDS=(viewer proxy spawn)

strand_cleanup() {
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

    local start elapsed
    start=$(date +%s)
    open_tmux_viewer "$session" 2>/dev/null || true
    elapsed=$(( $(date +%s) - start ))

    [ "$elapsed" -le 5 ] && pass "open_tmux_viewer returned in ${elapsed}s" || fail "open_tmux_viewer took ${elapsed}s (should be <5s)"
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
    sleep 0.5
    kill -0 "$PROXY_PID" 2>/dev/null && fail "worker proxy still alive after kill" || pass "worker proxy cleaned up"
}

strand_spawn() {
    init_project
    install_viewer_stubs
    write_mock_claude
    export CLAUDE_BIN="$MOCK_CLAUDE"
    SPAWN_NAME="spawnflow$$"
    source "$SPAWN_SH"

    local session="worker-$(basename "$PROJ")-$SPAWN_NAME"
    local start_ms end_ms elapsed_ms
    start_ms=$(python3 -c "import time; print(int(time.time() * 1000))")
    spawn_claude_worker "workers" "$SPAWN_NAME" "$PROJ" "sonnet" "Test prompt for a mock spawn." > "$STRAND_DIR/spawn_output.txt" 2>&1
    end_ms=$(python3 -c "import time; print(int(time.time() * 1000))")
    elapsed_ms=$(( end_ms - start_ms ))
    echo "  spawn output: $(cat "$STRAND_DIR/spawn_output.txt")"
    echo "  elapsed: ${elapsed_ms}ms"

    [ "$elapsed_ms" -le 10000 ] && pass "spawn returned in ${elapsed_ms}ms (< 10s)" || fail "spawn took ${elapsed_ms}ms (should be < 10s)"
    tmux has-session -t "$session" 2>/dev/null && pass "tmux session '$session' exists" || fail "tmux session '$session' not found"

    sleep 1
    local pane
    pane=$(tmux capture-pane -p -t "$session" 2>/dev/null || echo "")
    if echo "$pane" | grep -q "MOCK Claude Code"; then
        pass "mock claude running in pane"
    else
        fail "mock claude not found in pane output: $pane"
    fi
    grep -q "tmux attach -t $session" "$VIEWER_LOG" 2>/dev/null && pass "spawn opened the (stubbed) viewer for the session" \
        || fail "spawn did not call the viewer launcher"
    _stop_worker_logger "$SPAWN_NAME"
}

strand_main "$@"
