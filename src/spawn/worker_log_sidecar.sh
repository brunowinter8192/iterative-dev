#!/usr/bin/env bash
# worker_log_sidecar.sh — log-dir retention sweep and logger sidecar start/stop. Sourced by tmux_spawn.sh.

# sweep_stale_logs LOG_DIR [MAX_AGE_HOURS] [DRY_RUN]
#   Deletes regular files directly under LOG_DIR whose mtime is older than MAX_AGE_HOURS
#   (default 72, empty string also means "use the default"). This is the retention rule
#   for the per-spawn worker_logger.sh output (`<name>_<ts>_<event>.log`,
#   `<...>_DEATH.txt`) and janitor.log, none of which had any rotation before 2026-09-17
#   (process-docs/worker_sweep_logs/) — the 333-file, 49MB pile this fixed lived entirely
#   in these categories, measured live before this change.
#
#   wait_trace.log is explicitly excluded by name, always, regardless of age: it already
#   self-trims by LINE COUNT (20000 -> 10000, `_wait_trace_init` in bin/worker-cli) on a
#   different axis than age — it's a single continuously-relevant trace read for live
#   `wait` diagnostics, not a one-shot dateable snapshot like the per-spawn files. Adding
#   an age bound on top would either never fire (mtime refreshes on every poll while
#   `wait` is in active use) or, during a lull, delete the one thing still worth reading
#   for negligible space (it's capped at ~1-2MB by the line count alone). Keeping the two
#   mechanisms on separate axes, one per file, avoids a collision rather than trying to
#   unify them.
#
#   Deliberately not named/logged anywhere near "janitor" (`_janitor_log`/janitor.log,
#   `bin/worker-cli`'s `janitor` case) — that sweep kills stale tmux WORKER SESSIONS on a
#   12h default; this one deletes stale FILES on a 72h default. Own audit line goes to
#   log_sweep.log in the same LOG_DIR, which is itself subject to this same rule on later
#   runs (no special-casing needed: it gets rewritten every time this function runs, so
#   its mtime only ever goes stale if the sweep itself stops being invoked).
#
#   Called automatically, real (non-dry-run) only, from _start_worker_logger below — every
#   spawn/revive sweeps the directory it is about to add a new file to. Also exposed
#   directly as `worker-cli sweep-logs` for manual/dry-run use and testing.
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

# _start_worker_logger NAME SESSION EVENT
#   Spawn the diagnostic logger sidecar in background. Samples every 10s; on detected
#   pane_dead writes a forensic snapshot. Writes its own PID to /tmp/worker-logger-<name>.pid
#   so _stop_worker_logger can clean it up.
#
#   EVENT is "spawn" or "revive" — only affects the log filename suffix.
#
#   Log dir defaults to ~/Documents/ai/Meta/iterative-dev/src/logs (this repo's own
#   checkout — moved 2026-09-17 off a placeholder repo, Meta/blank, that held nothing but
#   this same directory); override via WORKER_LOGGER_DIR env var. Plugin runs from cache
#   but logs go to source-repo dir so they survive plugin-publish overwrites.
_start_worker_logger() {
    local name="$1"
    local session="$2"
    local event="${3:-spawn}"
    local logger_script
    logger_script="$(dirname "${BASH_SOURCE[0]}")/worker_logger.sh"
    if [ ! -x "$logger_script" ]; then
        # Logger missing — non-fatal, just skip
        return 0
    fi
    local log_dir="${WORKER_LOGGER_DIR:-$HOME/Documents/ai/Meta/iterative-dev/src/logs}"
    mkdir -p "$log_dir"
    sweep_stale_logs "$log_dir" 72 0 2>/dev/null || true
    # Start in background, fully detached so the logger survives worker_spawn returning
    nohup "$logger_script" "$name" "$session" "$log_dir" "$event" \
        >/dev/null 2>&1 &
    disown
}

# _stop_worker_logger NAME
#   Stop the diagnostic logger sidecar via PID file (best-effort).
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
