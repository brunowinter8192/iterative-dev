#!/usr/bin/env bash

sweep_stale_logs() {
    local log_dir="${1:?need log dir}"
    local max_age_hours="${2:-72}"
    [ -z "$max_age_hours" ] && max_age_hours=72
    local dry_run="${3:-0}"
    mkdir -p "$log_dir" 2>/dev/null || true
    [ -d "$log_dir" ] || return 0
    local max_age_secs=$((max_age_hours * 3600))
    local now_ts
    now_ts=$(date +%s)
    local removed=0
    local f
    while IFS= read -r -d '' f; do
        local base
        base="$(basename "$f")"
        [ "$base" = "wait_trace.log" ] && continue
        [ "$base" = ".gitkeep" ] && continue
        local mtime age
        mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo "$now_ts")
        age=$((now_ts - mtime))
        if [ "$age" -gt "$max_age_secs" ]; then
            removed=$((removed + 1))
            if [ "$dry_run" = "1" ]; then
                echo "DRY-RUN would remove: $f (age ${age}s, max ${max_age_secs}s)"
            else
                rm -f "$f" 2>/dev/null || true
            fi
        fi
    done < <(find "$log_dir" -maxdepth 1 -type f -print0 2>/dev/null || true)
    echo "$(date -Iseconds) event=sweep dry_run=$dry_run max_age_hours=$max_age_hours removed=$removed" \
        >> "$log_dir/log_sweep.log" 2>/dev/null || true
}

_start_worker_logger() {
    local name="$1"
    local session="$2"
    local event="${3:-spawn}"
    local logger_script
    logger_script="$(dirname "${BASH_SOURCE[0]}")/worker_logger.sh"
    if [ ! -x "$logger_script" ]; then
        return 0
    fi
    local log_dir="${WORKER_LOGGER_DIR:-$HOME/Documents/ai/Meta/iterative-dev/src/logs}"
    mkdir -p "$log_dir"
    sweep_stale_logs "$log_dir" 72 0 2>/dev/null || true
    nohup "$logger_script" "$name" "$session" "$log_dir" "$event" \
        >/dev/null 2>&1 &
    disown
}

_stop_worker_logger() {
    local name="$1"
    local pid_file="/tmp/worker-logger-${name}.pid"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || echo "")
        [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
        rm -f "$pid_file"
    fi
}
