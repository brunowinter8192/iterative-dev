#!/usr/bin/env bash

# INFRASTRUCTURE

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPAWN_SH="$PLUGIN_ROOT/src/spawn/tmux_spawn.sh"
REVIVE_SH="$PLUGIN_ROOT/src/spawn/worker_revive.sh"
WORKER_CLI="$PLUGIN_ROOT/bin/worker-cli"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
source "$SCRIPT_DIR/../strand_runner.sh"

STRANDS=(explicit_model missing_model e2e_no_model e2e_explicit e2e_malformed structural)

# ORCHESTRATOR

verify_worker_model_precedence_workflow() {
    strand_main "$@"
}

# FUNCTIONS

_assert_eq() {
    local desc="$1" expected="$2" got="$3"
    if [ "$got" = "$expected" ]; then
        pass "$desc"
    else
        fail "$desc (expected '$expected', got '$got')"
    fi
}

_write_mock_claude() {
    local mock_claude="$1"
    cat > "$mock_claude" << 'MOCKEOF'
#!/bin/bash
echo "❯"
sleep 8
MOCKEOF
    chmod +x "$mock_claude"
}

_spawn_via_cli() {
    local e2e_name="$1" model_arg="$2" config_path="$3" e2e_project="$4" e2e_prompt="$5" mock_claude="$6"
    ( unset PROXY_PROJECT_PATH
      export MODEL_SELECTION_FILE="$config_path"
      export CLAUDE_BIN="$mock_claude"
      export WORKER_NO_VIEWER=1
      export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
      "$WORKER_CLI" spawn "$e2e_name" "$e2e_prompt" "$e2e_project" "$model_arg" --no-worktree \
          > "$STRAND_DIR/e2e_output_${e2e_name}.log" 2>&1
    )
}

_assert_spawn_models() {
    local e2e_name="$1" model_arg="$2" expected="$3" session="$4"
    local runner_file runner_model
    runner_file=$(ls /tmp/.worker_"${e2e_name}".* 2>/dev/null | head -1)
    if [ -n "$runner_file" ] && [ -f "$runner_file" ]; then
        runner_model=$(grep -o "\-\-model '[^']*'" "$runner_file" | head -1 | sed "s/--model '//;s/'\$//")
    else
        runner_model="<runner file not found — see $STRAND_DIR/e2e_output_${e2e_name}.log>"
    fi
    _assert_eq "real worker-cli spawn (model_arg='$model_arg') -> runner script's --model" \
        "$expected" "$runner_model"

    local env_model
    env_model=$(tmux show-environment -t "$session" WORKER_MODEL 2>/dev/null | cut -d= -f2-)
    _assert_eq "real worker-cli spawn (model_arg='$model_arg') -> tmux WORKER_MODEL env" \
        "$expected" "$env_model"
}

_run_e2e_spawn() {
    local e2e_name="$1" model_arg="$2" config_path="$3" expected="$4"

    local e2e_project="$STRAND_DIR/e2e_project_${e2e_name}"
    mkdir -p "$e2e_project"
    local e2e_prompt="$STRAND_DIR/e2e_prompt_${e2e_name}.txt"
    echo "# e2e test prompt" > "$e2e_prompt"

    local mock_claude="$STRAND_DIR/mock_claude_${e2e_name}.sh"
    _write_mock_claude "$mock_claude"

    local session
    session="worker-$(basename "$e2e_project")-${e2e_name}"
    tmux kill-session -t "$session" 2>/dev/null || true
    rm -f /tmp/.worker_"${e2e_name}".* 2>/dev/null

    _spawn_via_cli "$e2e_name" "$model_arg" "$config_path" "$e2e_project" "$e2e_prompt" "$mock_claude"

    sleep 1

    _assert_spawn_models "$e2e_name" "$model_arg" "$expected" "$session"

    local runner_file
    runner_file=$(ls /tmp/.worker_"${e2e_name}".* 2>/dev/null | head -1)
    tmux kill-session -t "$session" 2>/dev/null || true
    rm -f "$runner_file" "/tmp/worker-${e2e_name}.done" 2>/dev/null
}

_write_e2e_config() {
    E2E_CONFIG="$STRAND_DIR/e2e_config.json"
    echo '{"main": "claude-opus-5", "worker": "claude-e2e-verify-9999"}' > "$E2E_CONFIG"
}

strand_explicit_model() {
    source "$SPAWN_SH"
    open_tmux_viewer() { :; }
    local name="mstestdirect$$" project="$STRAND_DIR/direct_project" prompt="$STRAND_DIR/direct_prompt.txt"
    mkdir -p "$project"
    echo "# direct test prompt" > "$prompt"
    _write_mock_claude "$STRAND_DIR/mock_claude.sh"
    export CLAUDE_BIN="$STRAND_DIR/mock_claude.sh"
    rm -f /tmp/.worker_"${name}".* 2>/dev/null

    local rc=0
    spawn_claude_worker_from_file "workers" "$name" "$project" "claude-direct-explicit" "$prompt" \
        > "$STRAND_DIR/direct_output.log" 2>&1 || rc=$?
    _assert_eq "spawn_claude_worker_from_file with an explicit model -> returns 0" "0" "$rc"
    _assert_spawn_models "$name" "claude-direct-explicit" "claude-direct-explicit" "worker-$(basename "$project")-$name"
    rm -f /tmp/.worker_"${name}".* "/tmp/worker-${name}.done" 2>/dev/null
}

strand_missing_model() {
    source "$SPAWN_SH"
    local project="$STRAND_DIR/missing_project" prompt="$STRAND_DIR/missing_prompt.txt"
    mkdir -p "$project"
    echo "# missing model prompt" > "$prompt"
    _write_mock_claude "$STRAND_DIR/mock_claude.sh"
    export CLAUDE_BIN="$STRAND_DIR/mock_claude.sh"
    local name="mstestmissing$$"
    rm -f /tmp/.worker_"${name}".* 2>/dev/null

    _assert_missing_model "spawn_claude_worker" "empty model" \
        spawn_claude_worker "workers" "$name" "$project" "" "task"
    _assert_missing_model "spawn_claude_worker" "absent model" \
        spawn_claude_worker "workers" "$name" "$project"
    _assert_missing_model "spawn_claude_worker_from_file" "empty model" \
        spawn_claude_worker_from_file "workers" "$name" "$project" "" "$prompt"
    _assert_missing_model "spawn_claude_worker_from_file" "absent model" \
        spawn_claude_worker_from_file "workers" "$name" "$project"

    _assert_eq "missing model -> no worker session was created" \
        "0" "$(tmux list-sessions 2>/dev/null | grep -c "$name")"
    _assert_eq "missing model -> no runner script was written" \
        "0" "$(ls /tmp/.worker_"${name}".* 2>/dev/null | wc -l | tr -d ' ')"
}

_assert_missing_model() {
    local fn="$1" desc="$2"
    shift 2
    local rc=0 err
    err=$("$@" 2>&1 >/dev/null) || rc=$?
    _assert_eq "$fn with $desc -> non-zero return" \
        "nonzero" "$([ "$rc" -ne 0 ] && echo nonzero || echo "rc=$rc")"
    _assert_eq "$fn with $desc -> clear stderr message" \
        "ERROR: $fn: model argument is required" "$err"
}

strand_e2e_no_model() {
    source "$SPAWN_SH"
    _write_e2e_config
    _run_e2e_spawn "mstestnomodel$$" "" "$E2E_CONFIG" "claude-e2e-verify-9999"
}

strand_e2e_malformed() {
    source "$SPAWN_SH"
    local malformed_config="$STRAND_DIR/malformed.json" e2e_name="mstestmalformed$$"
    echo '{not valid json' > "$malformed_config"
    _write_mock_claude "$STRAND_DIR/mock_claude.sh"
    local e2e_project="$STRAND_DIR/e2e_project" e2e_prompt="$STRAND_DIR/e2e_prompt.txt"
    mkdir -p "$e2e_project"
    echo "# e2e test prompt" > "$e2e_prompt"
    rm -f /tmp/.worker_"${e2e_name}".* 2>/dev/null

    local spawn_rc=0
    _spawn_via_cli "$e2e_name" "" "$malformed_config" "$e2e_project" "$e2e_prompt" "$STRAND_DIR/mock_claude.sh" || spawn_rc=$?
    local log="$STRAND_DIR/e2e_output_${e2e_name}.log"

    _assert_eq "real worker-cli spawn with a malformed config -> non-zero exit" \
        "nonzero" "$([ "$spawn_rc" -ne 0 ] && echo nonzero || echo "rc=$spawn_rc")"
    _assert_eq "real worker-cli spawn with a malformed config -> the parse error is reported" \
        "JSONDecodeError" "$(grep -o 'JSONDecodeError' "$log" | head -1)"
    _assert_eq "real worker-cli spawn with a malformed config -> no worker session was created" \
        "0" "$(tmux list-sessions 2>/dev/null | grep -c "$e2e_name")"
    _assert_eq "real worker-cli spawn with a malformed config -> no runner script was written" \
        "0" "$(ls /tmp/.worker_"${e2e_name}".* 2>/dev/null | wc -l | tr -d ' ')"
}

strand_e2e_explicit() {
    source "$SPAWN_SH"
    _write_e2e_config
    _run_e2e_spawn "mstestexplicit$$" "claude-e2e-explicit-arg" "$E2E_CONFIG" "claude-e2e-explicit-arg"
}

strand_structural() {
    echo ""
    echo "=== structural check: no shell resolver, one require helper called by the two spawn entry points, revive reads the stored model ==="
    RESOLVER_HITS=$(cat "$PLUGIN_ROOT"/src/spawn/*.sh | grep -c '_resolve_worker_model')
    DEFINITION_HITS=$(grep -c '^_require_worker_model()' "$SPAWN_SH")
    SPAWN_CALL_HITS=$(grep -c '_require_worker_model "\$model"' "$SPAWN_SH")
    REVIVE_STORED_HITS=$(grep -c '_tmux_env_value "\$session" WORKER_MODEL' "$REVIVE_SH")
    if [ "$RESOLVER_HITS" -eq 0 ] && [ "$DEFINITION_HITS" -eq 1 ] && [ "$SPAWN_CALL_HITS" -eq 2 ] && [ "$REVIVE_STORED_HITS" -eq 1 ]; then
        echo "  PASS: shell resolver references=$RESOLVER_HITS, require definition=$DEFINITION_HITS, call sites=$SPAWN_CALL_HITS, stored-model read in worker_revive.sh=$REVIVE_STORED_HITS"
    else
        echo "  FAIL: shell resolver references=$RESOLVER_HITS (want 0), require definition=$DEFINITION_HITS (want 1), call sites=$SPAWN_CALL_HITS (want 2), stored-model read=$REVIVE_STORED_HITS (want 1)"
        exit 1
    fi
}

verify_worker_model_precedence_workflow "$@"
