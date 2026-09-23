#!/usr/bin/env bash
# Verifies bracketed-paste delivery (tmux paste-buffer -p) into a real CC 2.1.280
# worker pane via the real worker_send() from src/spawn/tmux_spawn.sh, across the
# four message sizes from process-docs/worker_message_delivery/2026-09-23_paste_breaks_on_cc_280.md,
# plus one run of the old (pre-fix) method to show the contrast. Measures paste-to-
# render latency to justify the fixed 0.2s sleep before Enter.
#
# Usage: bash dev/worker_message_delivery/probe_bracketed_paste.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPAWN_SH="$PLUGIN_ROOT/src/spawn/tmux_spawn.sh"
VERIFY_PY="$SCRIPT_DIR/_verify_user_message.py"
CLAUDE_BIN="$HOME/.local/bin/claude-280"
MODEL="claude-sonnet-5"
REPORT_DIR="$SCRIPT_DIR/md"
REPORT_FILE="$REPORT_DIR/probe_bracketed_paste_report.md"
mkdir -p "$REPORT_DIR"

SCRATCH_DIRS=()
PROJECT_JSONL_DIRS=()
SESSIONS=()
REPORT_ROWS=()
LATENCY_ROWS=()

cleanup() {
    for s in "${SESSIONS[@]:-}"; do
        [ -n "$s" ] && tmux kill-session -t "$s" 2>/dev/null || true
    done
    for s in "${SESSIONS[@]:-}"; do
        [ -n "$s" ] && bash -c "source \"$SPAWN_SH\" && _orchestrator_signal_delete \"\$1\"" _ "$s" 2>/dev/null || true
    done
    for d in "${SCRATCH_DIRS[@]:-}"; do
        [ -n "$d" ] && rm -rf "$d"
    done
    for d in "${PROJECT_JSONL_DIRS[@]:-}"; do
        [ -n "$d" ] && rm -rf "$d"
    done
}
trap cleanup EXIT

cleanup_case() {
    local session="$1" scratch="$2" jsonl_dir="${3:-}"
    tmux kill-session -t "$session" 2>/dev/null || true
    bash -c "source \"$SPAWN_SH\" && _orchestrator_signal_delete \"\$1\"" _ "$session" 2>/dev/null || true
    # CC writes an async post-turn title record a moment after the turn is visible in the
    # JSONL — without this delay, a kill-session right after verification can race that
    # write and leave a one-line orphan project dir (observed live, see process-docs).
    sleep 1.5
    rm -rf "$scratch"
    [ -n "$jsonl_dir" ] && rm -rf "$jsonl_dir"
}

resolve_real_path() {
    (cd "$1" && pwd -P)
}

encode_path() {
    echo "$1" | tr '/_.' '-'
}

setup_session() {
    local session="$1" scratch="$2"
    tmux kill-session -t "$session" 2>/dev/null || true
    tmux new-session -d -s "$session" -c "$scratch" "$CLAUDE_BIN --model $MODEL" \; \
        set-option -p -t "$session" remain-on-exit on
    local pane_id
    pane_id=$(tmux list-panes -t "$session" -F "#{pane_id}" | head -1)
    local trust_handled=0
    local deadline=$(( $(date +%s) + 25 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if ! tmux has-session -t "$session" 2>/dev/null; then
            return 1
        fi
        local content
        content=$(tmux capture-pane -p -t "$pane_id" 2>/dev/null)
        if [ "$trust_handled" = "0" ] && echo "$content" | grep -q "Enter to confirm"; then
            tmux send-keys -t "$pane_id" Down
            sleep 0.2
            tmux send-keys -t "$pane_id" Enter
            trust_handled=1
            sleep 1
            continue
        fi
        if echo "$content" | grep -q '^❯'; then
            return 0
        fi
        sleep 0.3
    done
    return 1
}

measure_paste_latency() {
    local session="$1" message_file="$2" marker="$3"
    local pane_id
    pane_id=$(tmux list-panes -t "$session" -F "#{pane_id}" | head -1)
    local msg
    msg=$(cat "$message_file")
    printf '%s' "$msg" | tmux load-buffer -
    local start_ns
    start_ns=$(python3 -c "import time; print(time.time_ns())")
    tmux paste-buffer -d -p -t "$pane_id"
    local elapsed_ms="timeout"
    for _ in $(seq 1 100); do
        if tmux capture-pane -p -t "$pane_id" 2>/dev/null | grep -qF "$marker"; then
            local end_ns
            end_ns=$(python3 -c "import time; print(time.time_ns())")
            elapsed_ms=$(python3 -c "print(f'{($end_ns-$start_ns)/1e6:.1f}')")
            break
        fi
        sleep 0.01
    done
    tmux send-keys -t "$session" C-u
    sleep 0.2
    echo "$elapsed_ms"
}

wait_for_user_entry() {
    local jsonl_dir="$1"
    local deadline=$(( $(date +%s) + 15 ))
    local jsonl=""
    while [ "$(date +%s)" -lt "$deadline" ]; do
        jsonl=$(ls -t "$jsonl_dir"/*.jsonl 2>/dev/null | head -1)
        if [ -n "$jsonl" ] && grep -qE '"type":[[:space:]]*"user"' "$jsonl" 2>/dev/null; then
            echo "$jsonl"
            return 0
        fi
        sleep 0.3
    done
    echo "$jsonl"
    return 1
}

run_delivery_case() {
    local case_name="$1" worker_name="$2" message_file="$3" marker="$4"
    local scratch session real_path enc jsonl_dir

    scratch=$(mktemp -d "/tmp/pastefix-msgtest-XXXXXX")
    git -C "$scratch" init -q
    SCRATCH_DIRS+=("$scratch")
    session="worker-$(basename "$scratch")-${worker_name}"
    SESSIONS+=("$session")

    echo "=== $case_name ==="
    if ! setup_session "$session" "$scratch"; then
        echo "  setup FAILED (no input-ready state within 25s)"
        REPORT_ROWS+=("| $case_name | FAIL | setup timeout | - | - |")
        cleanup_case "$session" "$scratch"
        return
    fi

    for i in 1 2 3; do
        local ms
        ms=$(measure_paste_latency "$session" "$message_file" "$marker")
        echo "  latency sample $i: ${ms}ms"
        LATENCY_ROWS+=("| $case_name | $i | ${ms} |")
    done

    real_path=$(resolve_real_path "$scratch")
    enc=$(encode_path "$real_path")
    jsonl_dir="$HOME/.claude/projects/$enc"
    PROJECT_JSONL_DIRS+=("$jsonl_dir")

    local msg
    msg=$(cat "$message_file")
    _WORKER_MSG="$msg" bash -c 'source "$1" && worker_send "$2" "$_WORKER_MSG" "$3"' \
        _ "$SPAWN_SH" "$worker_name" "$scratch"

    local jsonl
    jsonl=$(wait_for_user_entry "$jsonl_dir")
    if [ -z "$jsonl" ] || [ ! -f "$jsonl" ]; then
        echo "  delivery FAILED (no session JSONL found)"
        REPORT_ROWS+=("| $case_name | FAIL | no JSONL | - | - |")
        cleanup_case "$session" "$scratch" "$jsonl_dir"
        return
    fi

    local verify_out verify_rc
    verify_out=$(python3 "$VERIFY_PY" "$jsonl" "$message_file")
    verify_rc=$?
    echo "$verify_out" | sed 's/^/  /'

    local entry_count match_val expected_len actual_len
    entry_count=$(echo "$verify_out" | grep '^USER_ENTRY_COUNT=' | cut -d= -f2)
    match_val=$(echo "$verify_out" | grep '^MATCH=' | cut -d= -f2)
    expected_len=$(echo "$verify_out" | grep '^EXPECTED_LEN=' | cut -d= -f2)
    actual_len=$(echo "$verify_out" | grep '^ACTUAL_LEN=' | cut -d= -f2)

    if [ "$verify_rc" -eq 0 ]; then
        echo "  delivery PASS (one user entry, full text matched)"
        REPORT_ROWS+=("| $case_name | PASS | entries=$entry_count match=$match_val | ${expected_len} | ${actual_len} |")
    else
        echo "  delivery FAIL"
        REPORT_ROWS+=("| $case_name | FAIL | entries=$entry_count match=$match_val | ${expected_len} | ${actual_len} |")
    fi
    cleanup_case "$session" "$scratch" "$jsonl_dir"
}

run_old_method_demo() {
    local scratch session real_path enc jsonl_dir message_file="/tmp/pastefix-old-method-msg.txt"

    scratch=$(mktemp -d "/tmp/pastefix-msgtest-XXXXXX")
    git -C "$scratch" init -q
    SCRATCH_DIRS+=("$scratch")
    session="worker-$(basename "$scratch")-oldmethod"
    SESSIONS+=("$session")

    echo "=== OLD METHOD (no -p, pre-fix) ==="
    if ! setup_session "$session" "$scratch"; then
        echo "  setup FAILED (no input-ready state within 25s)"
        REPORT_ROWS+=("| OLD METHOD (demo) | FAIL | setup timeout | - | - |")
        cleanup_case "$session" "$scratch"
        return
    fi

    local pane_id
    pane_id=$(tmux list-panes -t "$session" -F "#{pane_id}" | head -1)
    local msg
    msg=$(cat "$message_file")
    printf '%s' "$msg" | tmux load-buffer -
    tmux paste-buffer -d -t "$pane_id"
    sleep 0.2
    tmux send-keys -t "$pane_id" Enter

    real_path=$(resolve_real_path "$scratch")
    enc=$(encode_path "$real_path")
    jsonl_dir="$HOME/.claude/projects/$enc"
    PROJECT_JSONL_DIRS+=("$jsonl_dir")

    local jsonl
    jsonl=$(wait_for_user_entry "$jsonl_dir")
    if [ -z "$jsonl" ] || [ ! -f "$jsonl" ]; then
        echo "  no JSONL / no submission observed (this IS the expected pre-fix failure)"
        REPORT_ROWS+=("| OLD METHOD (demo) | FAIL (expected) | never submitted | - | - |")
        cleanup_case "$session" "$scratch" "$jsonl_dir"
        return
    fi

    local verify_out verify_rc
    verify_out=$(python3 "$VERIFY_PY" "$jsonl" "$message_file")
    verify_rc=$?
    echo "$verify_out" | sed 's/^/  /'

    local entry_count match_val expected_len actual_len
    entry_count=$(echo "$verify_out" | grep '^USER_ENTRY_COUNT=' | cut -d= -f2)
    match_val=$(echo "$verify_out" | grep '^MATCH=' | cut -d= -f2)
    expected_len=$(echo "$verify_out" | grep '^EXPECTED_LEN=' | cut -d= -f2)
    actual_len=$(echo "$verify_out" | grep '^ACTUAL_LEN=' | cut -d= -f2)

    if [ "$verify_rc" -eq 0 ]; then
        echo "  UNEXPECTED: old method delivered cleanly this run"
        REPORT_ROWS+=("| OLD METHOD (demo) | PASS (unexpected) | entries=$entry_count match=$match_val | ${expected_len} | ${actual_len} |")
    else
        echo "  reproduced pre-fix failure (content corrupted/incomplete)"
        REPORT_ROWS+=("| OLD METHOD (demo) | FAIL (expected) | entries=$entry_count match=$match_val | ${expected_len} | ${actual_len} |")
    fi
    cleanup_case "$session" "$scratch" "$jsonl_dir"
}

printf '%s' "hi test $$" > /tmp/pastefix-short-msg.txt
python3 -c "print('x' * 850, end='')" > /tmp/pastefix-800char-msg.txt
python3 -c "
lines = [f'This is filler line number {i:02d} for a multiline paste test.' for i in range(1, 19)]
print('\n'.join(lines), end='')
" > /tmp/pastefix-18line-msg.txt
python3 -c "
import random
random.seed(42)
words = ['alpha', 'beta', 'gamma', 'delta', 'filler', 'prompt', 'context', 'worker', 'module', 'pastetest']
lines, total, i = [], 0, 0
while total < 9000:
    i += 1
    line = f'Line {i:04d}: ' + ' '.join(random.choice(words) for _ in range(10)) + '.'
    lines.append(line)
    total += len(line) + 1
print('\n'.join(lines), end='')
" > /tmp/pastefix-9000char-msg.txt
cp /tmp/pastefix-18line-msg.txt /tmp/pastefix-old-method-msg.txt

run_delivery_case "short single line" "short" /tmp/pastefix-short-msg.txt "hi test $$"
run_delivery_case "800+ char single line" "longline" /tmp/pastefix-800char-msg.txt "Pasted text"
run_delivery_case "18-line / ~1470 char" "multiline" /tmp/pastefix-18line-msg.txt "Pasted text"
run_delivery_case "9000-char multiline" "bigprompt" /tmp/pastefix-9000char-msg.txt "Pasted text"
run_old_method_demo

{
    echo "# Bracketed-paste delivery probe (CC 2.1.280)"
    echo
    echo "Generated by \`dev/worker_message_delivery/probe_bracketed_paste.sh\` on $(date -Iseconds)."
    echo
    echo "## Delivery results"
    echo
    echo "| case | result | detail | expected_len | actual_len |"
    echo "|---|---|---|---|---|"
    for row in "${REPORT_ROWS[@]}"; do
        echo "$row"
    done
    echo
    echo "## Paste-to-render latency (ms, 3 samples per case, no Enter sent)"
    echo
    echo "| case | sample | latency_ms |"
    echo "|---|---|---|"
    for row in "${LATENCY_ROWS[@]}"; do
        echo "$row"
    done
    echo
    echo "Fixed sleep before Enter in production code: 200ms."
} > "$REPORT_FILE"

echo
echo "Report written to $REPORT_FILE"
rm -f /tmp/pastefix-short-msg.txt /tmp/pastefix-800char-msg.txt /tmp/pastefix-18line-msg.txt /tmp/pastefix-9000char-msg.txt /tmp/pastefix-old-method-msg.txt
