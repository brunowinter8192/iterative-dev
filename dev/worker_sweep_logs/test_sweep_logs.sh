#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
WCLI="$PLUGIN_ROOT/bin/worker-cli"
SPAWN="$PLUGIN_ROOT/src/spawn/tmux_spawn.sh"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
source "$SELF_DIR/../strand_runner.sh"

STRANDS=(dry_run real_run trace_exempt default_72h logger_trigger)

backdate() {
    local file="$1" hours="$2"
    touch -t "$(date -v-"${hours}"H +%Y%m%d%H%M.%S 2>/dev/null || date -d "-${hours} hours" +%Y%m%d%H%M.%S)" "$file"
}

strand_dry_run() {
    echo "=== Case 1: sweep-logs --dry-run --max-age-hours 72 — candidates listed, nothing removed ==="

    echo "old" > "$WORKER_LOGGER_DIR/stale-worker_20260101_000000_spawn.log"
    backdate "$WORKER_LOGGER_DIR/stale-worker_20260101_000000_spawn.log" 200
    echo "fresh" > "$WORKER_LOGGER_DIR/fresh-worker_20260917_000000_spawn.log"

    DRYRUN_OUT=$("$WCLI" sweep-logs --dry-run --max-age-hours 72 "$WORKER_LOGGER_DIR" 2>&1)
    echo "$DRYRUN_OUT" | sed 's/^/  /'

    if echo "$DRYRUN_OUT" | grep -q "would remove.*stale-worker_20260101_000000_spawn.log"; then
        check "stale file listed as dry-run candidate" "ok"
    else
        check "stale file listed as dry-run candidate" "not found in output"
    fi

    if [ -f "$WORKER_LOGGER_DIR/stale-worker_20260101_000000_spawn.log" ]; then
        check "dry-run did not delete the stale file" "ok"
    else
        check "dry-run did not delete the stale file" "file gone after dry-run!"
    fi

    if echo "$DRYRUN_OUT" | grep -q "fresh-worker_20260917_000000_spawn.log"; then
        check "fresh file not mentioned by dry-run" "mentioned — $(echo "$DRYRUN_OUT" | grep fresh-worker)"
    else
        check "fresh file not mentioned by dry-run" "ok"
    fi
}

strand_real_run() {
    echo "old" > "$WORKER_LOGGER_DIR/stale-worker_20260101_000000_spawn.log"
    backdate "$WORKER_LOGGER_DIR/stale-worker_20260101_000000_spawn.log" 200
    echo "fresh" > "$WORKER_LOGGER_DIR/fresh-worker_20260917_000000_spawn.log"

    echo "=== Case 2: sweep-logs --max-age-hours 72 (real) — stale removed, fresh spared ==="

    REAL_OUT=$("$WCLI" sweep-logs --max-age-hours 72 "$WORKER_LOGGER_DIR" 2>&1)
    echo "$REAL_OUT" | sed 's/^/  /'

    if [ ! -f "$WORKER_LOGGER_DIR/stale-worker_20260101_000000_spawn.log" ]; then
        check "stale file removed" "ok"
    else
        check "stale file removed" "still exists"
    fi

    if [ -f "$WORKER_LOGGER_DIR/fresh-worker_20260917_000000_spawn.log" ]; then
        check "fresh file spared" "ok"
    else
        check "fresh file spared" "was removed!"
    fi

    if [ -f "$WORKER_LOGGER_DIR/log_sweep.log" ] && grep -q "event=sweep dry_run=0 max_age_hours=72 removed=1" "$WORKER_LOGGER_DIR/log_sweep.log"; then
        check "log_sweep.log has a removed=1 line for this run" "ok"
    else
        check "log_sweep.log has a removed=1 line for this run" "not found — $(cat "$WORKER_LOGGER_DIR/log_sweep.log" 2>/dev/null)"
    fi
}

strand_trace_exempt() {
    echo "=== Case 3: wait_trace.log survives --max-age-hours 0 (matches everything else) ==="

    echo "trace" > "$WORKER_LOGGER_DIR/wait_trace.log"
    backdate "$WORKER_LOGGER_DIR/wait_trace.log" 999
    echo "also old" > "$WORKER_LOGGER_DIR/another-stale_20260101_000000_spawn.log"
    backdate "$WORKER_LOGGER_DIR/another-stale_20260101_000000_spawn.log" 999

    "$WCLI" sweep-logs --max-age-hours 0 "$WORKER_LOGGER_DIR" >/dev/null 2>&1

    if [ -f "$WORKER_LOGGER_DIR/wait_trace.log" ]; then
        check "wait_trace.log spared even at --max-age-hours 0" "ok"
    else
        check "wait_trace.log spared even at --max-age-hours 0" "was removed!"
    fi

    if [ ! -f "$WORKER_LOGGER_DIR/another-stale_20260101_000000_spawn.log" ]; then
        check "an ordinary file IS removed at --max-age-hours 0" "ok"
    else
        check "an ordinary file IS removed at --max-age-hours 0" "still exists"
    fi
}

strand_default_72h() {
    echo "=== Case 4: default max-age-hours is 72 ==="

    echo "just under" > "$WORKER_LOGGER_DIR/under-71h_20260101_000000_spawn.log"
    backdate "$WORKER_LOGGER_DIR/under-71h_20260101_000000_spawn.log" 71
    echo "just over" > "$WORKER_LOGGER_DIR/over-73h_20260101_000000_spawn.log"
    backdate "$WORKER_LOGGER_DIR/over-73h_20260101_000000_spawn.log" 73

    "$WCLI" sweep-logs "$WORKER_LOGGER_DIR" >/dev/null 2>&1

    if [ -f "$WORKER_LOGGER_DIR/under-71h_20260101_000000_spawn.log" ]; then
        check "71h-old file spared under the default 72h" "ok"
    else
        check "71h-old file spared under the default 72h" "was removed!"
    fi

    if [ ! -f "$WORKER_LOGGER_DIR/over-73h_20260101_000000_spawn.log" ]; then
        check "73h-old file removed under the default 72h" "ok"
    else
        check "73h-old file removed under the default 72h" "still exists"
    fi
}

strand_logger_trigger() {
    echo "=== Case 5: _start_worker_logger triggers the sweep automatically ==="

    echo "ancient" > "$WORKER_LOGGER_DIR/ancient-worker_20260101_000000_spawn.log"
    backdate "$WORKER_LOGGER_DIR/ancient-worker_20260101_000000_spawn.log" 999

    bash -c "source \"$SPAWN\" && _start_worker_logger fixture-name worker-nonexistent-fixture-name spawn"
    local waited=0
    while [ "$waited" -lt 50 ] && ! ls "$WORKER_LOGGER_DIR"/fixture-name_*_spawn.log >/dev/null 2>&1; do
        sleep 0.2
        waited=$((waited + 1))
    done

    if [ ! -f "$WORKER_LOGGER_DIR/ancient-worker_20260101_000000_spawn.log" ]; then
        check "pre-existing ancient file swept by a real _start_worker_logger call" "ok"
    else
        check "pre-existing ancient file swept by a real _start_worker_logger call" "still exists"
    fi

    if ls "$WORKER_LOGGER_DIR"/fixture-name_*_spawn.log >/dev/null 2>&1; then
        check "_start_worker_logger wrote its own new log file in the same (new default) dir" "ok"
    else
        check "_start_worker_logger wrote its own new log file in the same (new default) dir" "no fixture-name_*_spawn.log found"
    fi
}

strand_main "$@"
