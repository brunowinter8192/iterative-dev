#!/usr/bin/env bash
# wait.sh — worker-cli wait: poll loop, transition gate, trace log, background-task probe. Sourced by bin/worker-cli.

# --- wait helpers ---
# Poll cadence + stability window for `wait`. Two consecutive idle samples aren't enough to
# rule out a sampling race at the exact hook-transition instant; three samples 5s apart give
# a 10s span between the first and last confirmation — reuses the same 10s figure
# _worker_detect_status already relies on for its window_activity stale-check (worker_status_hooks_source.md),
# an already-vetted "long enough to not be noise" constant in this codebase.
_WAIT_POLL_INTERVAL=5
_WAIT_STABLE_SAMPLES=3

# --- wait trace (2026-08-18: observability — a timeout previously degraded silently, no error,
# no log line, indistinguishable from a legitimately long-running worker;
# process-docs/worker_wait/bg_task_detection_handle_based_rewrite_2026-08-17.md) ---
# One shared, growing file (not one per invocation, unlike worker_logger.sh's per-worker files)
# so concurrent `wait` calls for the same project interleave chronologically, tagged by pid=$$ —
# directly surfaces stacked/duplicate arms as a visible pattern. Same WORKER_LOGGER_DIR override
# + default worker_logger.sh already uses (survives plugin-publish overwrites — same reasoning
# applies here). Disable via WORKER_CLI_WAIT_TRACE=0.
# Default dir moved 2026-09-17 from a placeholder repo (Meta/blank, held nothing but this
# same log directory) to this repo's own checkout — see process-docs/worker_sweep_logs/.
_WAIT_TRACE_ENABLED="${WORKER_CLI_WAIT_TRACE:-1}"
_WAIT_TRACE_FILE="${WORKER_LOGGER_DIR:-$HOME/Documents/ai/Meta/iterative-dev/src/logs}/wait_trace.log"
_WAIT_TRACE_MAX_LINES=20000
_WAIT_TRACE_KEEP_LINES=10000

# _wait_trace EVENT_LINE
#   Append one already-formatted line (ISO timestamp prefixed here) to _WAIT_TRACE_FILE.
#   Fail-open, always: worker-cli runs under `set -e` (line 5) — a tracing hiccup (disk full,
#   permission, missing dir) must never abort the wait loop itself, so every step is explicitly
#   `|| true`-guarded — same lesson as _wait_has_live_bg_task's own set -e/lsof-exit-code
#   incident (bg_task_detection_handle_based_rewrite_2026-08-17.md).
_wait_trace() {
    [ "$_WAIT_TRACE_ENABLED" = "1" ] || return 0
    echo "$(date -Iseconds) $1" >> "$_WAIT_TRACE_FILE" 2>/dev/null || true
}

# _wait_trace_init — mkdir -p the trace dir; trim the shared file if it has grown past
# _WAIT_TRACE_MAX_LINES (keeps the most recent _WAIT_TRACE_KEEP_LINES). Called once per `wait`
# invocation, before the poll loop — bounds growth ACROSS invocations (a single invocation is
# already self-bounded: timeout/poll-interval x worker-count, a few thousand lines at worst).
# Fail-open throughout — see _wait_trace.
_wait_trace_init() {
    [ "$_WAIT_TRACE_ENABLED" = "1" ] || return 0
    mkdir -p "$(dirname "$_WAIT_TRACE_FILE")" 2>/dev/null || return 0
    if [ -f "$_WAIT_TRACE_FILE" ]; then
        local lines
        lines=$(wc -l < "$_WAIT_TRACE_FILE" 2>/dev/null || echo 0)
        lines="${lines// /}"
        if [ -n "$lines" ] && [ "$lines" -gt "$_WAIT_TRACE_MAX_LINES" ] 2>/dev/null; then
            tail -n "$_WAIT_TRACE_KEEP_LINES" "$_WAIT_TRACE_FILE" > "${_WAIT_TRACE_FILE}.tmp" 2>/dev/null \
                && mv "${_WAIT_TRACE_FILE}.tmp" "$_WAIT_TRACE_FILE" 2>/dev/null || true
        fi
    fi
}

# _wait_has_live_bg_task NAME PROJECT_PATH
#   Handle-based background-task check (2026-08, replaces a process-tree walk that produced a
#   live false-positive incident: a persistent tooling child under the worker's claude pid —
#   observed live, pyright-langserver running 36+ minutes — made every grandchild-count check
#   read "busy" forever, so `wait` degraded to the timeout ceiling on any worker that ever spawned
#   tooling). Mirrors monitor-cc's src/menubar/proc_cache.py (`_has_active_bg` /
#   `_refresh_bg_task_cache`), NOT reimported: a session's backgrounded Bash task is in-progress
#   iff some process holds an open WRITE handle on a *.output file under
#   /tmp/claude-<uid>/<encoded-session-cwd>/<session-id>/tasks/ — the exact directory Claude Code
#   itself writes background-task output into. LSP/MCP/tooling child processes never hold such a
#   handle, so they never register here, unlike the old grandchild-count check.
#   encoded/session_id derived exactly like _worker_detect_status (pane_current_path -> tr
#   '/_.' '-' -> newest ~/.claude/projects/<encoded>/*.jsonl basename) — always the SAME session
#   tmux_spawn.sh's own status check just resolved.
#   /tmp -> /private/tmp (macOS symlink) resolved once via `cd /tmp && pwd -P` before building the
#   tasks-dir path — mirrors _TASKS_BASE_REAL in the reference module (lsof reports the resolved
#   form; live-confirmed real occupied task dirs on this machine report as /private/tmp/...).
#   Scoped per-worker (`lsof +D <this session's tasks dir>` only) rather than the reference's one
#   global scan per tick — deliberate simplification: that batching amortizes lsof across MANY
#   sessions polled every tick in the menubar; here each call checks exactly one worker, so a
#   directly-scoped call is simpler AND strictly narrower/faster (no manual prefix-filter needed,
#   lsof's own +D traversal already guarantees scope). ~120ms per call, measured — cheap for the
#   5s poll cadence.
#   lsof's own exit code is NOT used as a signal: verified live that `lsof +D <dir> -Fn` can exit
#   1 even when it DOES find open files (an observed lsof quirk on this system) — matches the
#   reference module's own approach of parsing stdout unconditionally rather than gating on the
#   subprocess return code. CRITICAL: `out=$(lsof ...)` MUST carry `|| true` — `source "$1"`
#   (tmux_spawn.sh) re-applies ITS OWN `set -euo pipefail` to this same shell for everything after
#   the source line; a bare assignment whose command substitution exits non-zero aborts the whole
#   subshell immediately under inherited set -e (same failure class documented in
#   worker_status_hooks_source.md) — without the guard, lsof's exit-1-on-success quirk above
#   turned "tasks dir exists" into an unconditional "error" on every single call, live-caught via
#   a `set -x` trace mid-debug (the assignment line printed, then the subshell silently died with
#   no further trace and no output, which the outer `2>/dev/null || echo error` then reported).
#   Echoes "yes" (open .output handle found), "no" (none found), or "error" (probe failed —
#   caller must treat as "yes", per the fail-toward-waiting contract) — never raises.
_wait_has_live_bg_task() {
    local name="$1" project="$2"
    bash -c '
        source "$1"
        session=$(_worker_session_name "$2" "$3")
        worktree=$(tmux display-message -t "${session}:^" -p "#{pane_current_path}" 2>/dev/null) || { echo error; exit 0; }
        [ -z "$worktree" ] && { echo error; exit 0; }
        encoded=$(echo "$worktree" | tr "/_." "-")
        jsonl=$(ls -t "$HOME/.claude/projects/${encoded}"/*.jsonl 2>/dev/null | head -1)
        [ -z "$jsonl" ] && { echo error; exit 0; }
        session_id=$(basename "$jsonl" .jsonl)
        command -v lsof >/dev/null 2>&1 || { echo error; exit 0; }
        real_tmp=$(cd /tmp 2>/dev/null && pwd -P) || real_tmp="/tmp"
        tasks_dir="${real_tmp}/claude-$(id -u)/${encoded}/${session_id}/tasks"
        [ -d "$tasks_dir" ] || { echo no; exit 0; }
        out=$(lsof +D "$tasks_dir" -Fn 2>/dev/null) || true
        found=no
        while IFS= read -r line; do
            case "$line" in
                n*.output) found=yes; break ;;
            esac
        done <<< "$out"
        echo "$found"
    ' _ "$SPAWN" "$project" "$name" 2>/dev/null || echo error
}

cmd_wait() {
    _wait_parse_args "$@"
    local project timeout="$_WAIT_TIMEOUT"
    project=$(resolve_project_path "$_WAIT_OVERRIDE")
    _WAIT_TRACE_TAG="pid=$$ project=$(basename "$project")"
    _wait_trace_init
    _wait_trace "$_WAIT_TRACE_TAG event=start timeout=$timeout"
    local start_ts elapsed names
    local stable_count=0 empty_count=0
    start_ts=$(date +%s)
    # Transition-gate flag (2026-09-02): `wait` may only exit "workers idle"/"worker
    # terminal" once THIS invocation has observed a real "working" poll — an idle-at-arm
    # or never-registered worker must never look like a finished transition. Level-
    # triggered exits on a bare state (armed already-idle, armed on zero workers) were
    # waking the orchestrator for nothing; only an actual working->non-blocking edge
    # matters now.
    _WAIT_SAW_WORKING=0
    while true; do
        elapsed=$(( $(date +%s) - start_ts ))
        if [ "$elapsed" -ge "$timeout" ]; then
            _wait_trace "$_WAIT_TRACE_TAG event=exit reason=timeout elapsed=$elapsed saw_working=$_WAIT_SAW_WORKING"
            echo "timeout"
            exit 0
        fi
        names=$(_wait_list_names "$project")
        if [ -z "$names" ]; then
            stable_count=0
            empty_count=$((empty_count + 1))
            _wait_trace "$_WAIT_TRACE_TAG event=decision empty=1 empty_count=$empty_count elapsed=$elapsed"
            sleep "$_WAIT_POLL_INTERVAL"
            continue
        fi
        empty_count=0
        _wait_poll_once "$project" "$names"
        if [ "$_WAIT_ALL_NONBLOCKING" = "1" ]; then
            stable_count=$((stable_count + 1))
        else
            stable_count=0
        fi
        _wait_trace "$_WAIT_TRACE_TAG event=decision all_nonblocking=$_WAIT_ALL_NONBLOCKING any_dead=$_WAIT_ANY_TERMINAL stable_count=$stable_count elapsed=$elapsed"
        _wait_exit_if_settled "$stable_count" "$elapsed"
        sleep "$_WAIT_POLL_INTERVAL"
    done
}

# _wait_parse_args ARGS...
#   Sets _WAIT_OVERRIDE (project path arg) and _WAIT_TIMEOUT (default 3300).
_wait_parse_args() {
    _WAIT_OVERRIDE=""
    _WAIT_TIMEOUT=3300
    while [ $# -gt 0 ]; do
        case "$1" in
            --timeout) _WAIT_TIMEOUT="${2:?worker-cli wait: --timeout needs a value}"; shift 2 ;;
            --timeout=*) _WAIT_TIMEOUT="${1#--timeout=}"; shift ;;
            *) _WAIT_OVERRIDE="$1"; shift ;;
        esac
    done
}

# _wait_list_names PROJECT
#   Best-effort listing — any failure (tmux hiccup, etc.) yields empty output,
#   which is handled identically to "no worker visible yet": keep waiting. Zero
#   workers is just another non-exiting state (the old "no workers" fast-exit is
#   removed entirely — same reasoning as the transition gate: a state, not a
#   transition, must never end `wait` on its own) — keep polling through it.
_wait_list_names() {
    local project="$1"
    bash -c "source \"$SPAWN\" && worker_list \"\$1\"" _ "$project" 2>/dev/null \
        | awk '{print $1}' || true
}

# _wait_poll_once PROJECT NAMES
#   Classifies every worker once. Sets _WAIT_ALL_NONBLOCKING and _WAIT_ANY_TERMINAL;
#   stops at the first blocking worker.
_wait_poll_once() {
    local project="$1" names="$2"
    local wname status
    _WAIT_ALL_NONBLOCKING=1
    _WAIT_ANY_TERMINAL=0
    while IFS= read -r wname; do
        [ -z "$wname" ] && continue
        status=$(bash -c "source \"$SPAWN\" && worker_status \"\$1\" \"\$2\"" \
            _ "$wname" "$project" 2>/dev/null || echo "probe-error")
        if ! _wait_classify_status "$wname" "$status" "$project"; then
            _WAIT_ALL_NONBLOCKING=0
            break
        fi
    done <<< "$names"
}

# _wait_classify_status WNAME STATUS PROJECT
#   Returns 0 for a non-blocking worker, 1 for a blocking one.
#   Whitelist classification (2026-08-19 incident regression, now expressed over
#   the closed three-value vocabulary _worker_detect_status/worker_status return
#   — working/idle/dead, 2026-09-02, see process-docs/worker_wait/). Only "idle"
#   and "dead" are non-blocking; "working", a failed probe ("probe-error", never
#   a real worker state), and any future/unrecognized status fall through to the
#   default arm and stay blocking — fail-toward-waiting is preserved for anything
#   not explicitly whitelisted here, and none of them arm the transition gate.
_wait_classify_status() {
    local wname="$1" status="$2" project="$3"
    local bg
    case "$status" in
        working)
            # Verbatim "working" is the ONLY status that arms the transition gate —
            # any future/unrecognized status (default arm below) stays blocking too,
            # but must not count as proof of real work.
            _WAIT_SAW_WORKING=1
            _wait_trace "$_WAIT_TRACE_TAG event=poll worker=$wname status=working bg=- class=busy saw_working=$_WAIT_SAW_WORKING"
            return 1
            ;;
        idle)
            # Only a verbatim "idle" gets the bg-task probe — a worker still
            # coordinating a background task isn't really done.
            bg=$(_wait_has_live_bg_task "$wname" "$project")
            if [ "$bg" != "no" ]; then
                _wait_trace "$_WAIT_TRACE_TAG event=poll worker=$wname status=idle bg=$bg class=busy saw_working=$_WAIT_SAW_WORKING"
                return 1
            fi
            _wait_trace "$_WAIT_TRACE_TAG event=poll worker=$wname status=idle bg=no class=idle saw_working=$_WAIT_SAW_WORKING"
            return 0
            ;;
        dead)
            # Terminal: the coordinating claude process is presumed gone/stuck and
            # will never transition back to working on its own — a dead worker needs
            # orchestrator intervention, not more waiting. Bg-task probe deliberately
            # SKIPPED here: its own tmux/jsonl lookups would very plausibly fail for a
            # genuinely dead session too (-> "error" -> busy under its own
            # fail-toward-waiting contract), which would silently re-trap `wait` in
            # the exact "blocks forever on an unresolvable probe" failure this whole
            # change fixes. An orphaned bg process surviving its dead coordinator
            # doesn't change that the orchestrator must intervene either way.
            _WAIT_ANY_TERMINAL=1
            _wait_trace "$_WAIT_TRACE_TAG event=poll worker=$wname status=dead bg=- class=dead saw_working=$_WAIT_SAW_WORKING"
            return 0
            ;;
        *)
            _wait_trace "$_WAIT_TRACE_TAG event=poll worker=$wname status=${status// /_} bg=- class=busy saw_working=$_WAIT_SAW_WORKING"
            return 1
            ;;
    esac
}

# _wait_exit_if_settled STABLE_COUNT ELAPSED
#   Exits the script with "worker dead" / "workers idle" once enough consecutive
#   non-blocking samples were seen AND this invocation observed a real "working" poll.
_wait_exit_if_settled() {
    local stable_count="$1" elapsed="$2"
    if [ "$stable_count" -ge "$_WAIT_STABLE_SAMPLES" ] && [ "$_WAIT_SAW_WORKING" = "1" ]; then
        if [ "$_WAIT_ANY_TERMINAL" = "1" ]; then
            _wait_trace "$_WAIT_TRACE_TAG event=exit reason=worker_dead elapsed=$elapsed saw_working=$_WAIT_SAW_WORKING"
            echo "worker dead"
            exit 0
        fi
        _wait_trace "$_WAIT_TRACE_TAG event=exit reason=workers_idle elapsed=$elapsed saw_working=$_WAIT_SAW_WORKING"
        echo "workers idle"
        exit 0
    fi
}
