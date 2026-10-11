#!/usr/bin/env bash

# INFRASTRUCTURE

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT="$SCRIPT_DIR/md/measure_viewer_focus.md"
WINDOW_LIST_JS="$SCRIPT_DIR/measure_viewer_focus_windows.js"
VIEWER_ID="com.brunowinter.ghostty-viewer"
MAIN_ID="com.mitchellh.ghostty"
WINDOW_COUNT="${1:?usage: measure_viewer_focus.sh <window count>}"
WAIT_FOR_MAIN_FRONT_S=30
SETTLE_S=1.5
SAMPLE_INTERVAL_S=0.02
SHIM_LOG="$HOME/Library/Application Support/iterative-dev/viewer-shim.log"
WORK_DIR="$(mktemp -d /tmp/measure_viewer_focus-XXXXXX)"
SESSION_PREFIX="vbgmeasure$$"

# ORCHESTRATOR

measure_viewer_focus_workflow() {
    source "$PLUGIN_ROOT/src/spawn/worker_io.sh"
    _wait_for_main_front
    _create_sessions
    _snapshot_state before
    _start_sampler
    _open_all_viewers
    sleep "$SETTLE_S"
    _stop_sampler
    _snapshot_state after
    _snapshot_windows
    _probe_viewer_windows
    _write_report
    _keep_raw_samples
    _cleanup
    cat "$REPORT"
}

# FUNCTIONS

_front_bundle() {
    lsappinfo info -only bundleid "$(lsappinfo front)" | sed -n 's/.*"CFBundleIdentifier"="\(.*\)"/\1/p'
}

_wait_for_main_front() {
    local deadline=$((SECONDS + WAIT_FOR_MAIN_FRONT_S))
    while [ "$(_front_bundle)" != "$MAIN_ID" ] && [ "$SECONDS" -lt "$deadline" ]; do
        sleep 0.5
    done
}

_create_sessions() {
    local i
    for i in $(seq 1 "$WINDOW_COUNT"); do
        tmux new-session -d -s "${SESSION_PREFIX}-$i" "sleep 600"
    done
}

_main_ghostty_state() {
    osascript -e 'tell application "Ghostty" to return (id of front window) & "|" & (id of focused terminal of selected tab of front window)'
}

_snapshot_state() {
    local label="$1"
    echo "$(lsappinfo front)" > "$WORK_DIR/$label.front_asn"
    _front_bundle > "$WORK_DIR/$label.front_bundle"
    _main_ghostty_state > "$WORK_DIR/$label.main_state"
    wc -l < "$SHIM_LOG" 2>/dev/null | tr -d ' ' > "$WORK_DIR/$label.shim_lines" || echo 0 > "$WORK_DIR/$label.shim_lines"
}

_start_sampler() {
    : > "$WORK_DIR/samples.txt"
    (
        while true; do
            echo "$(date +%s) $(lsappinfo front)" >> "$WORK_DIR/samples.txt"
            sleep "$SAMPLE_INTERVAL_S"
        done
    ) &
    SAMPLER_PID=$!
    sleep 0.5
}

_stop_sampler() {
    kill "$SAMPLER_PID"
    wait "$SAMPLER_PID" 2>/dev/null
}

_open_all_viewers() {
    local i start end pids=()
    start=$(date +%s)
    for i in $(seq 1 "$WINDOW_COUNT"); do
        open_tmux_viewer "${SESSION_PREFIX}-$i" > "$WORK_DIR/open_$i.out" 2>&1 &
        pids+=($!)
    done
    wait "${pids[@]}"
    end=$(date +%s)
    echo "$start $end $((end - start))" > "$WORK_DIR/open_window"
}

_snapshot_windows() {
    VIEWER_PID=$(pgrep -f "GhosttyViewer.app/Contents/MacOS/" | head -1)
    osascript -l JavaScript "$WINDOW_LIST_JS" > "$WORK_DIR/windows.txt"
}

_probe_viewer_windows() {
    local i tty marker
    osascript -e "tell application id \"$VIEWER_ID\" to count windows" > "$WORK_DIR/viewer_window_count"
    : > "$WORK_DIR/probe.txt"
    for i in $(seq 1 "$WINDOW_COUNT"); do
        tty=$(tmux list-clients -t "${SESSION_PREFIX}-$i" -F '#{client_tty}' | head -1)
        if [ -z "$tty" ]; then
            echo "$i|no-client|" >> "$WORK_DIR/probe.txt"
            continue
        fi
        marker="__GHT_vbg$i$$"
        printf '\033]2;%s\007' "$marker" > "$tty"
        sleep 0.15
        echo "$i|$tty|$(_lookup_marker "$marker")" >> "$WORK_DIR/probe.txt"
        printf '\033]2;\007' > "$tty"
    done
}

_lookup_marker() {
    osascript -e "tell application id \"$VIEWER_ID\"
  try
    return id of (first terminal whose name is \"$1\")
  on error
    return \"\"
  end try
end tell"
}

_samples_changed() {
    local baseline start end
    baseline=$(cat "$WORK_DIR/before.front_asn")
    read -r start end _ < "$WORK_DIR/open_window"
    awk -v b="$baseline" -v s="$start" -v e="$((end + 2))" '$1 >= s && $1 <= e && $2 != b {n++} END {print n+0}' "$WORK_DIR/samples.txt"
}

_verdict() {
    if [ "$2" = "$3" ]; then
        echo "- PASS: $1 ($2)"
    else
        echo "- FAIL: $1 (before=$2 after=$3)"
    fi
}

_verdict_at_least() {
    if [ "$3" -ge "$2" ]; then
        echo "- PASS: $1 ($3, expected at least $2)"
    else
        echo "- FAIL: $1 ($3, expected at least $2)"
    fi
}

_count_probe_hits() {
    awk -F'|' '$3 != "" {n++} END {print n+0}' "$WORK_DIR/probe.txt"
}

_viewer_windows_in_front_of_others() {
    awk -F'|' -v pid="$VIEWER_PID" '
        $1 == pid { if (seen_other) behind++; else front++ }
        $1 != pid { seen_other = 1 }
        END { print front+0 " viewer windows above every other app window, " behind+0 " with another app window above them" }
    ' "$WORK_DIR/windows.txt"
}

_write_report() {
    local swallowed shim_before shim_after
    shim_before=$(cat "$WORK_DIR/before.shim_lines")
    shim_after=$(wc -l < "$SHIM_LOG" | tr -d ' ')
    swallowed=$((shim_after - shim_before))
    {
        echo "# measure_viewer_focus.sh report ($(date '+%Y-%m-%d %H:%M:%S'), windows=$WINDOW_COUNT)"
        echo
        _verdict "frontmost app unchanged" "$(cat "$WORK_DIR/before.front_bundle")" "$(cat "$WORK_DIR/after.front_bundle")"
        _verdict "main Ghostty front window and focused terminal unchanged" "$(cat "$WORK_DIR/before.main_state")" "$(cat "$WORK_DIR/after.main_state")"
        _verdict "samples differing from the start between open begin and 2 s after open end (total samples $(wc -l < "$WORK_DIR/samples.txt" | tr -d ' '))" "0" "$(_samples_changed)"
        _verdict "viewer window count" "$WINDOW_COUNT" "$(cat "$WORK_DIR/viewer_window_count")"
        _verdict "viewer windows attached and found by the OSC2 marker" "$WINDOW_COUNT" "$(_count_probe_hits)"
        _verdict_at_least "activates swallowed by the shim" "$WINDOW_COUNT" "$swallowed"
        echo
        echo "Baseline frontmost bundle: $(cat "$WORK_DIR/before.front_bundle")"
        echo "Open phase (start end seconds, epoch): $(cat "$WORK_DIR/open_window")"
        echo "All distinct samples (count epoch-free ASN): $(awk '{print $2}' "$WORK_DIR/samples.txt" | sort | uniq -c | tr '\n' ';')"
        echo "Visibility: $(_viewer_windows_in_front_of_others)"
        echo
        echo "## Probe (index|tty|terminal id)"
        cat "$WORK_DIR/probe.txt"
        echo
        echo "## Onscreen layer-0 windows front to back (pid|owner|x|y|w|h), viewer pid=$VIEWER_PID"
        cat "$WORK_DIR/windows.txt"
        echo
        echo "## Shim log tail"
        tail -n $((WINDOW_COUNT + 2)) "$SHIM_LOG"
    } > "$REPORT"
}

_keep_raw_samples() {
    cp "$WORK_DIR/samples.txt" "$SCRIPT_DIR/md/measure_viewer_focus_samples.txt"
}

_cleanup() {
    local i
    for i in $(seq 1 "$WINDOW_COUNT"); do
        tmux kill-session -t "${SESSION_PREFIX}-$i" 2>/dev/null
    done
    sleep 3
    if pgrep -f "GhosttyViewer.app/Contents/MacOS/" > /dev/null; then
        pkill -f "GhosttyViewer.app/Contents/MacOS/"
    fi
    rm -rf "$WORK_DIR"
}

measure_viewer_focus_workflow
