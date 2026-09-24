HOOKS_FILE="$HOME/Library/Application Support/com.brunowinter.monitor-cc-menubar/hooks.json"
HOOKS_BACKUP="/tmp/wait-test-hooks-backup-$$.json"
# Shared, growing, gitignored trace file `wait` itself writes to (C1, 2026-08-18) — real default
# path, not test-isolated (same file real live wait invocations use); checked via a before/after
# size diff, never overwritten or truncated by this suite.
TRACE_FILE="${WORKER_LOGGER_DIR:-$HOME/Documents/ai/Meta/iterative-dev/src/logs}/wait_trace.log"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; RESULT=1; }

# --- hooks.json scoping (backup original, restore on exit — never left mutated) ---

backup_hooks() {
    if [ -f "$HOOKS_FILE" ]; then
        cp "$HOOKS_FILE" "$HOOKS_BACKUP"
    else
        : > "$HOOKS_BACKUP.missing"
        mkdir -p "$(dirname "$HOOKS_FILE")"
        echo '{}' > "$HOOKS_FILE"
    fi
}

restore_hooks() {
    if [ -f "$HOOKS_BACKUP" ]; then
        mv "$HOOKS_BACKUP" "$HOOKS_FILE"
    elif [ -f "$HOOKS_BACKUP.missing" ]; then
        rm -f "$HOOKS_FILE" "$HOOKS_BACKUP.missing"
    fi
}

set_hook_status() {
    local session_id="$1" status="$2" cwd="$3"
    local tmp="$HOOKS_FILE.tmp.$$"
    jq --arg sid "$session_id" --arg st "$status" --arg cwd "$cwd" \
        '.[$sid] = {status: $st, cwd: $cwd, updated_ts: now}' "$HOOKS_FILE" > "$tmp" \
        && mv "$tmp" "$HOOKS_FILE"
}

# --- shared fixture building blocks ---

# encode_proj_dir PROJ_DIR — tmux reports pane_current_path canonicalized (e.g. macOS
# /tmp -> /private/tmp), so encode from the REAL path to match what _worker_detect_status
# looks up.
encode_proj_dir() {
    local real_proj_dir
    real_proj_dir=$(cd "$1" && pwd -P)
    echo "$real_proj_dir" | tr '/_.' '-'
}

# start_tmux_session SESSION PROJ_DIR COMMAND
start_tmux_session() {
    local session="$1" proj_dir="$2" command="$3"
    tmux new-session -d -s "$session" -c "$proj_dir" "$command" \; \
        set-option -p -t "$session" remain-on-exit on
    # Real spawn_claude_worker always sets these; worker_list's tmux show-environment lookup
    # errors on a missing var, which (under tmux_spawn.sh's set -euo pipefail) aborts the
    # whole function silently — match a real worker's env so the fixture is representative.
    tmux set-environment -t "$session" WORKER_SPAWNED "$(date +%H:%M)"
    tmux set-environment -t "$session" WORKER_PURPOSE "test fixture"
    sleep 0.5
}

# register_jsonl PROJ_DIR SESSION_ID
register_jsonl() {
    local proj_dir="$1" session_id="$2"
    local encoded
    encoded=$(encode_proj_dir "$proj_dir")
    mkdir -p "$HOME/.claude/projects/$encoded"
    touch "$HOME/.claude/projects/$encoded/$session_id.jsonl"
}

# claude-dummy stays alive as a real bash process (must NOT itself be exec'd away, or
# _worker_detect_status finds no "claude"-named descendant at all and misreports "limit
# reached" instead of "idle" — the tooling child is a genuine FORKED grandchild, not a
# further exec-replace of the claude-dummy identity).
write_wrap_bg() {
    local wrap="$1"
    cat > "$wrap" <<'INNER'
#!/bin/bash
( exec -a claude-dummy bash -c '(exec -a pyright-langserver-dummy sleep 100000) & wait' ) &
CLAUDE_PID=$!
echo "$CLAUDE_PID" > "$(dirname "$0")/.claude.pid"
wait $CLAUDE_PID
INNER
    chmod +x "$wrap"
}

write_wrap_chatty() {
    local proj_dir="$1" wrap="$2"
    cat > "$proj_dir/.chatty.sh" <<'INNER'
#!/bin/bash
QUIET_FILE="$1"
while [ ! -f "$QUIET_FILE" ]; do
    echo "tick $(date +%s)"
    sleep $(( (RANDOM % 2) + 1 ))
done
sleep 100000
INNER
    chmod +x "$proj_dir/.chatty.sh"
    cat > "$wrap" <<'INNER'
#!/bin/bash
( exec -a claude-dummy bash "$(dirname "$0")/.chatty.sh" "$(dirname "$0")/.chatty-quiet" ) &
CLAUDE_PID=$!
echo "$CLAUDE_PID" > "$(dirname "$0")/.claude.pid"
wait $CLAUDE_PID
INNER
    chmod +x "$wrap"
}

write_wrap_plain() {
    local wrap="$1"
    cat > "$wrap" <<'INNER'
#!/bin/bash
( exec -a claude-dummy sleep 100000 ) &
CLAUDE_PID=$!
echo "$CLAUDE_PID" > "$(dirname "$0")/.claude.pid"
wait $CLAUDE_PID
INNER
    chmod +x "$wrap"
}

write_wrap_no_pid() {
    local wrap="$1"
    cat > "$wrap" <<'INNER'
#!/bin/bash
( exec -a claude-dummy sleep 100000 ) &
CLAUDE_PID=$!
wait $CLAUDE_PID
INNER
    chmod +x "$wrap"
}

write_worker_wrapper() {
    local proj_dir="$1" wrap="$2" bg="$3" chatty="$4"
    if [ "$bg" = "1" ]; then
        write_wrap_bg "$wrap"
    elif [ "$chatty" = "1" ]; then
        write_wrap_chatty "$proj_dir" "$wrap"
    else
        write_wrap_plain "$wrap"
    fi
}

# --- fake worker: real tmux session (claude-dummy child, optional persistent tooling grandchild
# or chatty print-loop) + hooks entry ---
# create_worker NAME PROJ_DIR SESSION_ID STATUS BG(0|1) [CHATTY(0|1)]
# BG=1: claude-dummy forks a persistent grandchild (simulates a long-lived tooling child — e.g.
# pyright-langserver, the live incident this fixture regression-guards) that is NEVER killed
# during a test using it — the handle-based bg-task check must ignore it entirely, unlike the
# old process-tree walk this replaced (any grandchild = "busy", forever).
# CHATTY=1 (mutually exclusive with BG=1): claude-dummy loops printing to the pane every 1-2s
# until go_quiet() touches PROJ_DIR/.chatty-quiet, then falls silent (stays alive). This is the
# ONLY way to keep #{window_activity} fresh past 10s — the signal _worker_detect_status demotes
# hook_status=working on once stale (tmux_spawn.sh:172-186) — needed for any fixture that must
# read back as genuinely "working" for longer than a few seconds, or after a status flip that
# happens well after creation (the plain/BG=1 wrapper is silent, so window_activity goes stale
# the moment ~10s pass with no further pane output, independent of what hooks.json says).
create_worker() {
    local name="$1" proj_dir="$2" session_id="$3" status="$4" bg="$5" chatty="${6:-0}"
    mkdir -p "$proj_dir"
    local session="worker-$(basename "$proj_dir")-$name"
    tmux kill-session -t "$session" 2>/dev/null || true
    rm -f "$proj_dir/.claude.pid" "$proj_dir/.chatty-quiet"
    local wrap="$proj_dir/.wrap.sh"
    write_worker_wrapper "$proj_dir" "$wrap" "$bg" "$chatty"
    start_tmux_session "$session" "$proj_dir" "bash $wrap"
    register_jsonl "$proj_dir" "$session_id"
    set_hook_status "$session_id" "$status" "$proj_dir"
    echo "$session"
}

# go_quiet PROJ_DIR — stops a CHATTY=1 worker's print loop (touches the control file
# create_worker's chatty wrapper polls for). No-op if the worker wasn't created chatty.
go_quiet() {
    local proj_dir="$1"
    touch "$proj_dir/.chatty-quiet"
}

# kill_claude_child PROJ_DIR — kills just the claude-dummy process (pid recorded by
# create_worker), leaving the tmux session/pane alive. remain-on-exit then marks the pane
# dead once the wrapper's own `wait $CLAUDE_PID` returns and the wrapper script itself exits
# — _worker_detect_status reads that as pane_dead=1 -> dead: the "claude child gone"
# terminal path, distinct from killing the whole SESSION (which instead empties
# worker_list's NAMES entirely and never classifies as dead).
kill_claude_child() {
    local proj_dir="$1"
    local pf="$proj_dir/.claude.pid"
    [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null
    return 0
}

# delete_hook_entry SESSION_ID — removes the hooks.json entry while the tmux session/process
# stay alive, reproducing "no hook data". By itself this is NOT a dead signal under the
# working/idle/dead vocabulary (2026-09-02) — it just falls into the same shared
# working/idle window-activity check as any other no-hook-entry worker (working while
# fresh, idle once quiet > 10s). Used in Test 10 alongside kill_claude_child to build a
# realistic dead-AND-hook-orphaned worker, not on its own.
delete_hook_entry() {
    local sid="$1"
    jq --arg sid "$sid" 'del(.[$sid])' "$HOOKS_FILE" > "$HOOKS_FILE.tmp.$$" 2>/dev/null \
        && mv "$HOOKS_FILE.tmp.$$" "$HOOKS_FILE"
}

# create_worker_no_hook NAME PROJ_DIR SESSION_ID
#   Mirrors create_worker (claude-dummy child alive + JSONL present) but deliberately skips
#   set_hook_status — no hooks.json entry ever exists for this session_id. Session/pane ALIVE
#   (tmux session found by worker_list, claude-dummy child present), no dead signal fires, so
#   this resolves via the shared no-hook-entry window-activity check: "working" while the pane
#   is still fresh (just created), "idle" once quiet > 10s — NOT "dead" (2026-09-02 vocabulary
#   change; this fixture used to read as the old "unknown" placeholder). Distinct from Test 4's
#   session-GONE fixture (tmux session itself killed — routes through the empty-NAMES path
#   instead, untouched by this feature).
create_worker_no_hook() {
    local name="$1" proj_dir="$2" session_id="$3"
    mkdir -p "$proj_dir"
    local session="worker-$(basename "$proj_dir")-$name"
    tmux kill-session -t "$session" 2>/dev/null || true
    local wrap="$proj_dir/.wrap.sh"
    write_wrap_no_pid "$wrap"
    start_tmux_session "$session" "$proj_dir" "bash $wrap"
    register_jsonl "$proj_dir" "$session_id"
    # Deliberately no set_hook_status call.
    echo "$session"
}

# create_worker_dead NAME PROJ_DIR
#   Wrapper exits immediately (no claude-dummy child ever forked); pane stays alive via
#   remain-on-exit, so #{pane_dead} flips to 1 and _worker_detect_status returns "dead"
#   directly — returns before the JSONL/hooks lookups, so neither is needed for this fixture.
create_worker_dead() {
    local name="$1" proj_dir="$2"
    mkdir -p "$proj_dir"
    local session="worker-$(basename "$proj_dir")-$name"
    tmux kill-session -t "$session" 2>/dev/null || true
    start_tmux_session "$session" "$proj_dir" "true"
    echo "$session"
}

# destroy_worker NAME PROJ_DIR SESSION_ID
destroy_worker() {
    local name="$1" proj_dir="$2" session_id="$3"
    local session="worker-$(basename "$proj_dir")-$name"
    tmux kill-session -t "$session" 2>/dev/null || true
    jq --arg sid "$session_id" 'del(.[$sid])' "$HOOKS_FILE" > "$HOOKS_FILE.tmp.$$" 2>/dev/null \
        && mv "$HOOKS_FILE.tmp.$$" "$HOOKS_FILE"
    local real_proj_dir encoded
    real_proj_dir=$([ -d "$proj_dir" ] && (cd "$proj_dir" && pwd -P) || echo "$proj_dir")
    encoded=$(echo "$real_proj_dir" | tr '/_.' '-')
    rm -rf "$HOME/.claude/projects/$encoded"
    rm -rf "$proj_dir"
}

# real_tasks_dir PROJ_DIR SESSION_ID — resolved (/private/tmp on macOS) tasks dir path a fixture
# worker's background tasks would live under; mirrors _wait_has_live_bg_task's own derivation.
real_tasks_dir() {
    local proj_dir="$1" session_id="$2"
    local encoded real_tmp
    encoded=$(encode_proj_dir "$proj_dir")
    real_tmp=$(cd /tmp && pwd -P)
    echo "${real_tmp}/claude-$(id -u)/${encoded}/${session_id}/tasks"
}

# raw_tasks_dir PROJ_DIR SESSION_ID — same as real_tasks_dir but WITHOUT resolving /tmp (stays
# with the literal unresolved "/tmp/..." prefix) — used to deliberately open a fixture file via
# the unresolved path while the hook internally resolves to /private/tmp/..., proving detection
# still matches (same underlying file, OS-transparent symlink).
raw_tasks_dir() {
    local proj_dir="$1" session_id="$2"
    local encoded
    encoded=$(encode_proj_dir "$proj_dir")
    echo "/tmp/claude-$(id -u)/${encoded}/${session_id}/tasks"
}

# start_fake_bg_task TASKS_DIR TASK_ID — opens a genuine long-lived write handle on
# <TASKS_DIR>/<TASK_ID>.output (mirrors what Claude Code itself does for a real backgrounded Bash
# call — `exec` preserves the just-opened FD across the image replace, so the resulting `sleep`
# process itself holds the handle open, same PID `$!` captures). Records that pid to a sidecar
# file for kill_fake_bg_task to clean up.
start_fake_bg_task() {
    local tdir="$1" task_id="$2"
    mkdir -p "$tdir"
    ( exec sleep 100000 > "$tdir/$task_id.output" ) &
    disown
    echo $! > "/tmp/${TEST_TAG}-fakebg-${task_id}.pid"
}

# kill_fake_bg_task TASK_ID — closes the handle opened by start_fake_bg_task.
kill_fake_bg_task() {
    local task_id="$1"
    local pidfile="/tmp/${TEST_TAG}-fakebg-${task_id}.pid"
    if [ -f "$pidfile" ]; then
        kill "$(cat "$pidfile")" 2>/dev/null || true
        rm -f "$pidfile"
    fi
}
