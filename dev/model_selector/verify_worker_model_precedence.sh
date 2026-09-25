#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPAWN_SH="$PLUGIN_ROOT/src/spawn/tmux_spawn.sh"
REVIVE_SH="$PLUGIN_ROOT/src/spawn/worker_revive.sh"
WORKER_CLI="$PLUGIN_ROOT/bin/worker-cli"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
source "$SCRIPT_DIR/../strand_runner.sh"

STRANDS=(resolver e2e_no_model e2e_explicit structural)

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

strand_resolver() {
    source "$SPAWN_SH"
    echo "=== _resolve_worker_model() directly — this IS the shared logic all 3 bash sites use ==="

    MODEL_SELECTION_FILE="$STRAND_DIR/does_not_exist.json"
    _assert_eq "missing config file -> hardcoded fallback" \
        "claude-sonnet-5" "$(_resolve_worker_model)"

    VALID_CONFIG="$STRAND_DIR/valid.json"
    echo '{"main": "claude-opus-5", "worker": "claude-fable-5"}' > "$VALID_CONFIG"
    MODEL_SELECTION_FILE="$VALID_CONFIG"
    _assert_eq "valid config -> config's worker model" \
        "claude-fable-5" "$(_resolve_worker_model)"

    MALFORMED_CONFIG="$STRAND_DIR/malformed.json"
    echo '{not valid json' > "$MALFORMED_CONFIG"
    MODEL_SELECTION_FILE="$MALFORMED_CONFIG"
    _assert_eq "malformed JSON config -> hardcoded fallback, no crash" \
        "claude-sonnet-5" "$(_resolve_worker_model)"

    MISSING_KEY_CONFIG="$STRAND_DIR/missing_key.json"
    echo '{"main": "claude-opus-5"}' > "$MISSING_KEY_CONFIG"
    MODEL_SELECTION_FILE="$MISSING_KEY_CONFIG"
    _assert_eq "config present but missing 'worker' key -> hardcoded fallback" \
        "claude-sonnet-5" "$(_resolve_worker_model)"

    EMPTY_KEY_CONFIG="$STRAND_DIR/empty_key.json"
    echo '{"main": "claude-opus-5", "worker": ""}' > "$EMPTY_KEY_CONFIG"
    MODEL_SELECTION_FILE="$EMPTY_KEY_CONFIG"
    _assert_eq "config present with empty 'worker' value -> hardcoded fallback" \
        "claude-sonnet-5" "$(_resolve_worker_model)"

    echo ""
    echo "=== spawn_claude_worker / spawn_claude_worker_from_file's real \${4:-\$(_resolve_worker_model)} pattern ==="
    echo "    (the identical expansion literally used at both call sites, not a reimplementation)"

    MODEL_SELECTION_FILE="$VALID_CONFIG"
    _site_expand() { local model="${4:-$(_resolve_worker_model)}"; echo "$model"; }

    _assert_eq "explicit 4th arg present -> explicit wins, config never even consulted" \
        "claude-explicit-arg" "$(_site_expand a b c claude-explicit-arg e)"

    _assert_eq "4th arg empty string -> falls to config (via _resolve_worker_model)" \
        "claude-fable-5" "$(_site_expand a b c "" e)"

    _assert_eq "4th arg entirely absent -> falls to config (via _resolve_worker_model)" \
        "claude-fable-5" "$(_site_expand a b c)"

    echo ""
    echo "=== worker_revive's real 'stored value wins, else _resolve_worker_model' pattern ==="

    MODEL_SELECTION_FILE="$VALID_CONFIG"
    _revive_expand() { local model="$1"; [ -z "$model" ] && model="$(_resolve_worker_model)"; echo "$model"; }

    _assert_eq "WORKER_MODEL present in tmux env -> stored value wins over config" \
        "claude-originally-spawned-with" "$(_revive_expand "claude-originally-spawned-with")"

    _assert_eq "WORKER_MODEL absent from tmux env -> config applies" \
        "claude-fable-5" "$(_revive_expand "")"

    MODEL_SELECTION_FILE="$STRAND_DIR/does_not_exist.json"
    _assert_eq "WORKER_MODEL absent AND config absent -> hardcoded fallback" \
        "claude-sonnet-5" "$(_revive_expand "")"
}

strand_e2e_no_model() {
    source "$SPAWN_SH"
    _write_e2e_config
    _run_e2e_spawn "mstestnomodel$$" "" "$E2E_CONFIG" "claude-e2e-verify-9999"
}

strand_e2e_explicit() {
    source "$SPAWN_SH"
    _write_e2e_config
    _run_e2e_spawn "mstestexplicit$$" "claude-e2e-explicit-arg" "$E2E_CONFIG" "claude-e2e-explicit-arg"
}

strand_structural() {
    echo ""
    echo "=== structural check: _resolve_worker_model defined once, called from all 3 sites ==="
    DEFINITION_HITS=$(grep -c '^_resolve_worker_model()' "$SPAWN_SH")
    CALL_SITE_HITS=$(cat "$SPAWN_SH" "$REVIVE_SH" | grep -c '\$(_resolve_worker_model)')
    if [ "$DEFINITION_HITS" -eq 1 ] && [ "$CALL_SITE_HITS" -eq 3 ]; then
        echo "  PASS: _resolve_worker_model defined $DEFINITION_HITS time, called at $CALL_SITE_HITS sites (tmux_spawn.sh, worker_revive.sh)"
    else
        echo "  FAIL: _resolve_worker_model definitions=$DEFINITION_HITS call sites=$CALL_SITE_HITS — expected 1 definition + 3 call sites"
        exit 1
    fi
}

strand_main "$@"
