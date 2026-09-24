#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$(dirname "${BASH_SOURCE[0]}")/md/render_runner_flags.md"
FAKE_HOME=$(mktemp -d /tmp/render_home.XXXXXX)
WT="$FAKE_HOME/proj/.claude/worktrees/rt"
mkdir -p "$WT"
ENC=$(echo "$WT" | tr '/_.' '---')
mkdir -p "$FAKE_HOME/.claude/projects/$ENC"
touch "$FAKE_HOME/.claude/projects/$ENC/11111111-2222-3333-4444-555555555555.jsonl"
export HOME="$FAKE_HOME" CLAUDE_BIN=/fake/claude
source "$REPO/src/spawn/tmux_spawn.sh"
set +e
tmux() {
    case "$1" in
        has-session) return 0 ;;
        display-message) echo 1 ;;
        list-panes) echo "%0" ;;
        capture-pane) echo "❯" ;;
        show-environment) echo "X=claude-sonnet-5" ;;
        *) return 0 ;;
    esac
}
open_tmux_viewer() { :; }
_start_worker_logger() { :; }
_orchestrator_signal_update() { :; }
_worker_proxy_setup() { WORKER_PROXY_PID=""; WORKER_PROXY_ENV_PREFIX=""; WORKER_PROXY_LIVE_ADDON=""; WORKER_PROXY_LIVE_DIR=""; }
sleep() { :; }
tmux_new_runner_line() { grep -h -- '--model' "$1" | grep fake; }
echo "# t" > "$FAKE_HOME/prompt.txt"
rm -f /tmp/.worker_rt.* /tmp/.worker_rt_revive.*
spawn_claude_worker s rt "$WT" claude-sonnet-5 "# task" >/dev/null 2>&1
SPAWN_LINE=$(tmux_new_runner_line /tmp/.worker_rt.*)
spawn_claude_worker_from_file s rt2 "$WT" claude-sonnet-5 "$FAKE_HOME/prompt.txt" >/dev/null 2>&1
FILE_LINE=$(tmux_new_runner_line /tmp/.worker_rt2.*)
worker_revive rt "$WT" >/dev/null 2>&1
REVIVE_LINE=$(tmux_new_runner_line /tmp/.worker_rt_revive.*)
{
    echo "# render_runner_flags report"
    echo
    echo "spawn:      $SPAWN_LINE"
    echo "spawn_file: $FILE_LINE"
    echo "revive:     $REVIVE_LINE"
} | tee "$OUT"
rm -f /tmp/.worker_rt*.* ; rm -rf "$FAKE_HOME"
for l in "$SPAWN_LINE" "$FILE_LINE" "$REVIVE_LINE"; do
    [[ "$l" == *"--permission-mode bypassPermissions"* ]] || { echo "FAIL"; exit 1; }
    [[ "$l" != *acceptEdits* ]] || { echo "FAIL"; exit 1; }
done
echo PASS
