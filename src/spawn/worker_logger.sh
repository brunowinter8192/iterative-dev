#!/usr/bin/env bash
# worker_logger.sh — sidecar diagnostic logger for a single tmux worker session.
#
# Spawned in background by worker_spawn / worker_revive. Samples every SAMPLE_INTERVAL
# seconds while the worker's tmux pane is alive. On detected pane death (#{pane_dead}
# transitions to 1), writes a comprehensive forensic snapshot before exiting.
#
# Goal: when a worker dies unexpectedly (SIGTERM from unknown source, OOM kill, etc.),
# we have a record of: what the worker process looked like just before death (RSS,
# process tree, parent chain), what the surrounding system state was (total RSS, vm_stat),
# and what other watchdogs were reporting (oom-watchdog, menubar-abort).
#
# Args:
#   $1 = worker name (e.g. "eval-sweep")
#   $2 = tmux session name (e.g. "worker-RAG-eval-sweep")
#   $3 = log directory (absolute path; logger creates files inside)
#   $4 = lifecycle event marker — "spawn" or "revive" (only affects log filename suffix)
#
# Output files (in log_dir/):
#   <name>_<spawn-ts>_<event>.log         — periodic samples, one line per sample
#   <name>_<spawn-ts>_<event>_DEATH.txt   — forensic snapshot at death (only written on pane death)
#
# Self-exit conditions:
#   1. tmux session no longer exists (worker fully killed)
#   2. pane_dead transitions to 1 (worker process died — snapshot then exit)
#   3. SIGTERM received (caller is stopping us, e.g. worker_kill)

set -uo pipefail

NAME="${1:?need worker name}"
SESSION="${2:?need session name}"
LOG_DIR="${3:?need log dir}"
EVENT="${4:-spawn}"

SAMPLE_INTERVAL="${WORKER_LOGGER_INTERVAL:-10}"  # seconds between samples
PID_FILE="/tmp/worker-logger-${NAME}.pid"

mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/${NAME}_${TS}_${EVENT}.log"
DEATH_FILE="${LOG_DIR}/${NAME}_${TS}_${EVENT}_DEATH.txt"

# Register our own PID so worker_kill can stop us cleanly
echo $$ > "$PID_FILE"

# Cleanup on receiving SIGTERM (worker_kill flow)
_self_cleanup() {
    rm -f "$PID_FILE"
    exit 0
}
trap _self_cleanup TERM INT HUP

# Resolve JSONL path for last-mtime tracking
ENCODED_DIR=""
WORKTREE_PATH=""
if PANE_PID=$(tmux display-message -t "${SESSION}:^" -p "#{pane_pid}" 2>/dev/null); then
    # Try to find worktree path from session env
    WORKTREE_PATH=$(tmux show-environment -t "$SESSION" 2>/dev/null | grep -E '^WORKER_CWD=' | cut -d= -f2- || true)
fi

# JSONL location follows Claude Code's encoding (slashes → dashes)
# Best-effort: scan ~/.claude/projects for any dir matching this worker pattern
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

# Initial baseline line
{
    echo "# worker_logger v1 — diagnostic samples for worker '$NAME'"
    echo "# event=$EVENT session=$SESSION log_dir=$LOG_DIR"
    echo "# jsonl=$JSONL_PATH"
    echo "# sample_interval=${SAMPLE_INTERVAL}s"
    echo "# started=$(date -Iseconds)"
    echo "# format: <iso-ts> pane_dead=<0|1> claude_pid=<N> claude_rss_mb=<X> total_rss_gb=<Y> jsonl_age_s=<Z>"
} >> "$LOG_FILE"

_sample() {
    local now pane_dead claude_pid claude_rss_kb claude_rss_mb total_rss_kb total_rss_gb jsonl_age_s

    now=$(date -Iseconds)
    pane_dead=$(tmux display-message -t "${SESSION}:^" -p "#{pane_dead}" 2>/dev/null || echo "?")

    # claude.exe PID under this tmux session — walk pane_pid descendants for claude.exe
    local pane_pid
    pane_pid=$(tmux display-message -t "${SESSION}:^" -p "#{pane_pid}" 2>/dev/null || echo "")
    claude_pid=""
    if [ -n "$pane_pid" ]; then
        # Find descendants with comm matching claude.exe
        # pgrep -P traverses one level; we walk up to 3 levels
        local children
        children=$(pgrep -P "$pane_pid" 2>/dev/null || true)
        for c in $children; do
            local comm
            comm=$(ps -p "$c" -o comm= 2>/dev/null || true)
            if [[ "$comm" == *"claude.exe" ]]; then
                claude_pid="$c"
                break
            fi
            # one level deeper
            local gc
            gc=$(pgrep -P "$c" 2>/dev/null || true)
            for g in $gc; do
                local gcomm
                gcomm=$(ps -p "$g" -o comm= 2>/dev/null || true)
                if [[ "$gcomm" == *"claude.exe" ]]; then
                    claude_pid="$g"
                    break 2
                fi
            done
        done
    fi

    if [ -n "$claude_pid" ]; then
        claude_rss_kb=$(ps -p "$claude_pid" -o rss= 2>/dev/null | tr -d ' ')
        [ -n "$claude_rss_kb" ] && claude_rss_mb=$(awk "BEGIN{printf \"%.0f\", $claude_rss_kb/1024}")
    fi
    claude_rss_mb="${claude_rss_mb:-?}"

    total_rss_kb=$(ps -axo rss= 2>/dev/null | awk '{s+=$1} END{print s}')
    total_rss_gb=$(awk "BEGIN{printf \"%.2f\", $total_rss_kb/1024/1024}")

    # JSONL last-mtime age
    jsonl_age_s="?"
    if [ -n "$JSONL_PATH" ] && [ -f "$JSONL_PATH" ]; then
        local mtime now_epoch
        mtime=$(stat -f %m "$JSONL_PATH" 2>/dev/null)
        now_epoch=$(date +%s)
        [ -n "$mtime" ] && jsonl_age_s=$((now_epoch - mtime))
    fi

    echo "$now pane_dead=$pane_dead claude_pid=${claude_pid:-?} claude_rss_mb=$claude_rss_mb total_rss_gb=$total_rss_gb jsonl_age_s=$jsonl_age_s" >> "$LOG_FILE"

    # If pane died, capture forensic snapshot and exit
    if [ "$pane_dead" = "1" ]; then
        _capture_death "$now" "$pane_dead" "$claude_pid" "$claude_rss_mb" "$total_rss_gb" "$jsonl_age_s"
        rm -f "$PID_FILE"
        exit 0
    fi
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

# Main sample loop — exit on session-gone or pane-dead
while true; do
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        # Session vanished (worker_kill cleaned up before we noticed pane_dead)
        echo "$(date -Iseconds) session_gone=1 — exiting" >> "$LOG_FILE"
        rm -f "$PID_FILE"
        exit 0
    fi
    _sample
    sleep "$SAMPLE_INTERVAL"
done
