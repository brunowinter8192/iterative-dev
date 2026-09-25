#!/usr/bin/env bash

set -uo pipefail

NAME="${1:?need worker name}"
SESSION="${2:?need session name}"
LOG_DIR="${3:?need log dir}"
EVENT="${4:-spawn}"

SAMPLE_INTERVAL="${WORKER_LOGGER_INTERVAL:-10}"
PID_FILE="/tmp/worker-logger-${NAME}.pid"

mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/${NAME}_${TS}_${EVENT}.log"
DEATH_FILE="${LOG_DIR}/${NAME}_${TS}_${EVENT}_DEATH.txt"

echo $$ > "$PID_FILE"

_self_cleanup() {
    rm -f "$PID_FILE"
    exit 0
}
trap _self_cleanup TERM INT HUP

_find_jsonl() {
    local proj_pattern="*${NAME}*"
    local p
    for d in "$HOME/.claude/projects"/*; do
        [ -d "$d" ] || continue
        case "$d" in
            *"--claude-worktrees-${NAME}"*) ls -t "$d"/*.jsonl 2>/dev/null | head -1; return ;;
        esac
    done
    return 1
}

JSONL_PATH="$(_find_jsonl || true)"

{
    echo "# worker_logger v1 — diagnostic samples for worker '$NAME'"
    echo "# event=$EVENT session=$SESSION log_dir=$LOG_DIR"
    echo "# jsonl=$JSONL_PATH"
    echo "# sample_interval=${SAMPLE_INTERVAL}s"
    echo "# started=$(date -Iseconds)"
    echo "# format: <iso-ts> pane_dead=<0|1> claude_pid=<N> claude_rss_mb=<X> total_rss_gb=<Y> jsonl_age_s=<Z>"
} >> "$LOG_FILE"

_sample() {
    local now pane_dead claude_pid claude_rss_mb total_rss_gb jsonl_age_s

    now=$(date -Iseconds)
    pane_dead=$(tmux display-message -t "${SESSION}:^" -p "#{pane_dead}" 2>/dev/null || echo "?")
    claude_pid=$(_find_claude_pid)
    claude_rss_mb=$(_claude_rss_mb "$claude_pid")
    total_rss_gb=$(_total_rss_gb)
    jsonl_age_s=$(_jsonl_age_s)

    echo "$now pane_dead=$pane_dead claude_pid=${claude_pid:-?} claude_rss_mb=$claude_rss_mb total_rss_gb=$total_rss_gb jsonl_age_s=$jsonl_age_s" >> "$LOG_FILE"

    if [ "$pane_dead" = "1" ]; then
        _capture_death "$now" "$pane_dead" "$claude_pid" "$claude_rss_mb" "$total_rss_gb" "$jsonl_age_s"
        rm -f "$PID_FILE"
        exit 0
    fi
}

_find_claude_pid() {
    local pane_pid
    pane_pid=$(tmux display-message -t "${SESSION}:^" -p "#{pane_pid}" 2>/dev/null || echo "")
    [ -n "$pane_pid" ] || return 0
    local children c comm gc g gcomm
    children=$(pgrep -P "$pane_pid" 2>/dev/null || true)
    for c in $children; do
        comm=$(ps -p "$c" -o comm= 2>/dev/null || true)
        if [[ "$comm" == *"claude.exe" ]]; then
            echo "$c"
            return 0
        fi
        gc=$(pgrep -P "$c" 2>/dev/null || true)
        for g in $gc; do
            gcomm=$(ps -p "$g" -o comm= 2>/dev/null || true)
            if [[ "$gcomm" == *"claude.exe" ]]; then
                echo "$g"
                return 0
            fi
        done
    done
}

_claude_rss_mb() {
    local claude_pid="$1"
    local claude_rss_kb claude_rss_mb=""
    if [ -n "$claude_pid" ]; then
        claude_rss_kb=$(ps -p "$claude_pid" -o rss= 2>/dev/null | tr -d ' ')
        [ -n "$claude_rss_kb" ] && claude_rss_mb=$(awk "BEGIN{printf \"%.0f\", $claude_rss_kb/1024}")
    fi
    echo "${claude_rss_mb:-?}"
}

_total_rss_gb() {
    local total_rss_kb
    total_rss_kb=$(ps -axo rss= 2>/dev/null | awk '{s+=$1} END{print s}')
    awk "BEGIN{printf \"%.2f\", $total_rss_kb/1024/1024}"
}

_jsonl_age_s() {
    local mtime now_epoch
    if [ -n "$JSONL_PATH" ] && [ -f "$JSONL_PATH" ]; then
        mtime=$(stat -f %m "$JSONL_PATH" 2>/dev/null)
        now_epoch=$(date +%s)
        if [ -n "$mtime" ]; then
            echo $((now_epoch - mtime))
            return 0
        fi
    fi
    echo "?"
}

_capture_death() {
    local now="$1" pane_dead="$2" claude_pid="$3" claude_rss_mb="$4" total_rss_gb="$5" jsonl_age_s="$6"

    {
        echo "# Worker Death Snapshot"
        echo "# worker=$NAME session=$SESSION timestamp=$now"
        echo "# pane_dead=$pane_dead claude_pid=$claude_pid claude_rss_mb=$claude_rss_mb total_rss_gb=$total_rss_gb jsonl_age_s=$jsonl_age_s"
        echo ""
        echo "## tmux pane state"
        tmux list-panes -t "$SESSION" -F "#{pane_id} pane_dead=#{pane_dead} pane_dead_status=#{pane_dead_status} pane_dead_signal=#{pane_dead_signal} pane_pid=#{pane_pid}" 2>/dev/null || echo "(session vanished)"
        echo ""
        echo "## Full process tree (PID, PPID, USER, RSS_KB, ETIME, COMMAND — sorted by RSS desc)"
        ps -axo pid,ppid,user,rss,etime,command | sort -k4 -rn | head -50
        echo ""
        echo "## vm_stat"
        vm_stat 2>/dev/null || echo "(vm_stat unavailable)"
        echo ""
        echo "## Recent oom-watchdog log (last 30 lines)"
        tail -30 "$HOME/.oom-watchdog.log" 2>/dev/null || echo "(no oom-watchdog log)"
        echo ""
        echo "## Recent menubar-abort log (last 30 lines)"
        tail -30 /tmp/menubar-abort.log 2>/dev/null || echo "(no menubar-abort log)"
        echo ""
        echo "## Worker session JSONL — last 20 entries"
        if [ -n "$JSONL_PATH" ] && [ -f "$JSONL_PATH" ]; then
            tail -20 "$JSONL_PATH"
        else
            echo "(no JSONL found at $JSONL_PATH)"
        fi
        echo ""
        echo "## Sampling history (last 30 samples from this log)"
        tail -30 "$LOG_FILE"
    } > "$DEATH_FILE"
}

while true; do
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "$(date -Iseconds) session_gone=1 — exiting" >> "$LOG_FILE"
        rm -f "$PID_FILE"
        exit 0
    fi
    _sample
    sleep "$SAMPLE_INTERVAL"
done
