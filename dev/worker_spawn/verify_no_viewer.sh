#!/usr/bin/env bash

# INFRASTRUCTURE

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKER_CLI="$PLUGIN_ROOT/bin/worker-cli"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
source "$SCRIPT_DIR/../strand_runner.sh"

STRANDS=(viewer_default viewer_suppressed viewer_function)

# ORCHESTRATOR

verify_no_viewer_workflow() {
    strand_main "$@"
}

# FUNCTIONS

_install_stubs() {
    OSA_LOG="$STRAND_DIR/osascript.log"
    : > "$OSA_LOG"
    cat > "$STRAND_DIR/bin/osascript" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$OSA_LOG"
STUB
    cat > "$STRAND_DIR/bin/ghostty" <<'STUB'
#!/usr/bin/env bash
echo "Ghostty 1.3.0"
STUB
    chmod +x "$STRAND_DIR/bin/osascript" "$STRAND_DIR/bin/ghostty"
}

_write_mock_claude() {
    MOCK_CLAUDE="$STRAND_DIR/mock_claude.sh"
    printf '#!/bin/bash\necho "❯"\nsleep 8\n' > "$MOCK_CLAUDE"
    chmod +x "$MOCK_CLAUDE"
}

_spawn_via_cli() {
    local name="$1"
    PROJECT="$STRAND_DIR/project"
    mkdir -p "$PROJECT"
    git init "$PROJECT" -b main -q
    echo "# viewer test prompt" > "$STRAND_DIR/prompt.txt"
    SESSION="worker-project-${name}"
    ( unset PROXY_PROJECT_PATH
      cd "$PROJECT"
      export MODEL_SELECTION_FILE="$STRAND_DIR/none.json"
      export CLAUDE_BIN="$MOCK_CLAUDE"
      "$WORKER_CLI" spawn "$name" "$STRAND_DIR/prompt.txt" --no-worktree \
          > "$STRAND_DIR/spawn.log" 2>&1
    )
}

_cleanup_spawn() {
    local name="$1"
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    rm -f /tmp/.worker_"${name}".* "/tmp/worker-${name}.done" 2>/dev/null
}

_osascript_calls() {
    grep -c "tmux attach" "$OSA_LOG"
}

strand_viewer_default() {
    _install_stubs
    _write_mock_claude
    local name="vwdefault$$"
    unset WORKER_NO_VIEWER
    _spawn_via_cli "$name"
    sleep 1
    check "spawn without WORKER_NO_VIEWER -> session exists" \
        "$(tmux has-session -t "$SESSION" 2>/dev/null && echo ok || echo "missing, see $STRAND_DIR/spawn.log")"
    check "spawn without WORKER_NO_VIEWER -> exactly one osascript call" \
        "$([ "$(_osascript_calls)" = "1" ] && echo ok || echo "calls=$(_osascript_calls)")"
    check "spawn without WORKER_NO_VIEWER -> the call attaches to the worker session" \
        "$(grep -q "tmux attach -t $SESSION; exit" "$OSA_LOG" && echo ok || echo "no attach line")"
    _cleanup_spawn "$name"
}

strand_viewer_suppressed() {
    _install_stubs
    _write_mock_claude
    local name="vwquiet$$"
    export WORKER_NO_VIEWER=1
    _spawn_via_cli "$name"
    sleep 2
    check "spawn with WORKER_NO_VIEWER=1 -> session exists" \
        "$(tmux has-session -t "$SESSION" 2>/dev/null && echo ok || echo "missing, see $STRAND_DIR/spawn.log")"
    check "spawn with WORKER_NO_VIEWER=1 -> zero osascript calls" \
        "$([ "$(_osascript_calls)" = "0" ] && echo ok || echo "calls=$(_osascript_calls)")"
    _cleanup_spawn "$name"
}

strand_viewer_function() {
    _install_stubs
    source "$PLUGIN_ROOT/src/spawn/worker_io.sh"
    WORKER_NO_VIEWER=1 open_tmux_viewer "any-session"
    check "open_tmux_viewer with WORKER_NO_VIEWER=1 -> zero osascript calls" \
        "$([ "$(_osascript_calls)" = "0" ] && echo ok || echo "calls=$(_osascript_calls)")"
    ( unset WORKER_NO_VIEWER; open_tmux_viewer "any-session" )
    check "open_tmux_viewer unset -> one osascript call (revive path shares this function)" \
        "$([ "$(_osascript_calls)" = "1" ] && echo ok || echo "calls=$(_osascript_calls)")"
}

verify_no_viewer_workflow "$@"
