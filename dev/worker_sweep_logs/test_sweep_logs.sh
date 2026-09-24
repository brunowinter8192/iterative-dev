#!/usr/bin/env bash
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WCLI="$PLUGIN_ROOT/bin/worker-cli"
SPAWN="$PLUGIN_ROOT/src/spawn/tmux_spawn.sh"

export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

TMPLOGS=$(mktemp -d)
export WORKER_LOGGER_DIR="$TMPLOGS"

cleanup() {
    rm -rf "$TMPLOGS"
}
trap cleanup EXIT

pass=0; fail=0
check() {
    local label="$1" result="$2"
    if [ "$result" = "ok" ]; then
        echo "  PASS: $label"; ((pass++)) || true
    else
        echo "  FAIL: $label — $result"; ((fail++)) || true
    fi
}

backdate() {
    local file="$1" hours="$2"
    touch -t "$(date -v-"${hours}"H +%Y%m%d%H%M.%S 2>/dev/null || date -d "-${hours} hours" +%Y%m%d%H%M.%S)" "$file"
}

echo "=== Case 1: sweep-logs --dry-run --max-age-hours 72 — candidates listed, nothing removed ==="

echo "old" > "$TMPLOGS/stale-worker_20260101_000000_spawn.log"
backdate "$TMPLOGS/stale-worker_20260101_000000_spawn.log" 200
echo "fresh" > "$TMPLOGS/fresh-worker_20260917_000000_spawn.log"

DRYRUN_OUT=$("$WCLI" sweep-logs --dry-run --max-age-hours 72 "$TMPLOGS" 2>&1)
echo "$DRYRUN_OUT" | sed 's/^/  /'

if echo "$DRYRUN_OUT" | grep -q "would remove.*stale-worker_20260101_000000_spawn.log"; then
    check "stale file listed as dry-run candidate" "ok"
else
    check "stale file listed as dry-run candidate" "not found in output"
fi

if [ -f "$TMPLOGS/stale-worker_20260101_000000_spawn.log" ]; then
    check "dry-run did not delete the stale file" "ok"
else
    check "dry-run did not delete the stale file" "file gone after dry-run!"
fi

if echo "$DRYRUN_OUT" | grep -q "fresh-worker_20260917_000000_spawn.log"; then
    check "fresh file not mentioned by dry-run" "mentioned — $(echo "$DRYRUN_OUT" | grep fresh-worker)"
else
    check "fresh file not mentioned by dry-run" "ok"
fi

echo ""
echo "=== Case 2: sweep-logs --max-age-hours 72 (real) — stale removed, fresh spared ==="

REAL_OUT=$("$WCLI" sweep-logs --max-age-hours 72 "$TMPLOGS" 2>&1)
echo "$REAL_OUT" | sed 's/^/  /'

if [ ! -f "$TMPLOGS/stale-worker_20260101_000000_spawn.log" ]; then
    check "stale file removed" "ok"
else
    check "stale file removed" "still exists"
fi

if [ -f "$TMPLOGS/fresh-worker_20260917_000000_spawn.log" ]; then
    check "fresh file spared" "ok"
else
    check "fresh file spared" "was removed!"
fi

if [ -f "$TMPLOGS/log_sweep.log" ] && grep -q "event=sweep dry_run=0 max_age_hours=72 removed=1" "$TMPLOGS/log_sweep.log"; then
    check "log_sweep.log has a removed=1 line for this run" "ok"
else
    check "log_sweep.log has a removed=1 line for this run" "not found — $(cat "$TMPLOGS/log_sweep.log" 2>/dev/null)"
fi

echo ""
echo "=== Case 3: wait_trace.log survives --max-age-hours 0 (matches everything else) ==="

echo "trace" > "$TMPLOGS/wait_trace.log"
backdate "$TMPLOGS/wait_trace.log" 999
echo "also old" > "$TMPLOGS/another-stale_20260101_000000_spawn.log"
backdate "$TMPLOGS/another-stale_20260101_000000_spawn.log" 999

"$WCLI" sweep-logs --max-age-hours 0 "$TMPLOGS" >/dev/null 2>&1

if [ -f "$TMPLOGS/wait_trace.log" ]; then
    check "wait_trace.log spared even at --max-age-hours 0" "ok"
else
    check "wait_trace.log spared even at --max-age-hours 0" "was removed!"
fi

if [ ! -f "$TMPLOGS/another-stale_20260101_000000_spawn.log" ]; then
    check "an ordinary file IS removed at --max-age-hours 0" "ok"
else
    check "an ordinary file IS removed at --max-age-hours 0" "still exists"
fi

echo ""
echo "=== Case 4: default max-age-hours is 72 ==="

echo "just under" > "$TMPLOGS/under-71h_20260101_000000_spawn.log"
backdate "$TMPLOGS/under-71h_20260101_000000_spawn.log" 71
echo "just over" > "$TMPLOGS/over-73h_20260101_000000_spawn.log"
backdate "$TMPLOGS/over-73h_20260101_000000_spawn.log" 73

"$WCLI" sweep-logs "$TMPLOGS" >/dev/null 2>&1

if [ -f "$TMPLOGS/under-71h_20260101_000000_spawn.log" ]; then
    check "71h-old file spared under the default 72h" "ok"
else
    check "71h-old file spared under the default 72h" "was removed!"
fi

if [ ! -f "$TMPLOGS/over-73h_20260101_000000_spawn.log" ]; then
    check "73h-old file removed under the default 72h" "ok"
else
    check "73h-old file removed under the default 72h" "still exists"
fi

echo ""
echo "=== Case 5: _start_worker_logger triggers the sweep automatically ==="

echo "ancient" > "$TMPLOGS/ancient-worker_20260101_000000_spawn.log"
backdate "$TMPLOGS/ancient-worker_20260101_000000_spawn.log" 999

bash -c "source \"$SPAWN\" && _start_worker_logger fixture-name worker-nonexistent-fixture-name spawn"
sleep 1

if [ ! -f "$TMPLOGS/ancient-worker_20260101_000000_spawn.log" ]; then
    check "pre-existing ancient file swept by a real _start_worker_logger call" "ok"
else
    check "pre-existing ancient file swept by a real _start_worker_logger call" "still exists"
fi

if ls "$TMPLOGS"/fixture-name_*_spawn.log >/dev/null 2>&1; then
    check "_start_worker_logger wrote its own new log file in the same (new default) dir" "ok"
else
    check "_start_worker_logger wrote its own new log file in the same (new default) dir" "no fixture-name_*_spawn.log found"
fi

echo ""
echo "=== Summary: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
