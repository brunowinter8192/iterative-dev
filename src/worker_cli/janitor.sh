#!/usr/bin/env bash
# janitor.sh — worker-cli janitor: stale-worker cleanup (age-gated session sweep + orphan registry sweep). Sourced by bin/worker-cli.

# --- janitor (stale-worker cleanup) ---
# Same shared-file + fail-open pattern as _wait_trace (WORKER_LOGGER_DIR override,
# every write guarded by `|| true` so a logging hiccup can never abort the sweep
# under this file's `set -e`). Default dir moved 2026-09-17, same as _WAIT_TRACE_FILE above.
_JANITOR_LOG_FILE="${WORKER_LOGGER_DIR:-$HOME/Documents/ai/Meta/iterative-dev/src/logs}/janitor.log"
_JANITOR_ORPHAN_GRACE_SECS=30

_janitor_log() {
    mkdir -p "$(dirname "$_JANITOR_LOG_FILE")" 2>/dev/null || true
    echo "$(date -Iseconds) $1" >> "$_JANITOR_LOG_FILE" 2>/dev/null || true
}

# _janitor_resolve_worker SESSION
#   Resolves (name, project) for a raw worker-* tmux session name — the registry is
#   keyed by name, not session, so this is the inverse of _worker_session_name.
#   Order: registry (any entry whose recomputed session matches) -> pane_current_path
#   (worktree-mode spawns cd into PROJECT/.claude/worktrees/NAME — same lookup
#   _worker_detect_status already relies on; --no-worktree spawns cd into PROJECT
#   directly, matched via exact "worker-<basename>-" prefix) -> tmux_scan_project
#   fallback (existing helper, keyed off the session's trailing segment as a name
#   guess). Every candidate is round-trip verified via _worker_session_name before
#   being accepted — a wrong split/guess must never masquerade as resolved.
#   Echoes "name|project" on success; silent + returns 1 on failure.
_janitor_resolve_worker() {
    local session="$1"
    local f rname rproj rsession
    for f in "$REGISTRY_DIR"/*; do
        [ -f "$f" ] || continue
        [[ "$f" == *.worktrees ]] && continue
        rname=$(basename "$f")
        rproj=$(cat "$f" 2>/dev/null) || continue
        [ -z "$rproj" ] && continue
        rsession=$(bash -c "source \"$SPAWN\" && _worker_session_name \"\$1\" \"\$2\"" _ "$rproj" "$rname" 2>/dev/null) || continue
        if [ "$rsession" = "$session" ]; then
            echo "${rname}|${rproj}"
            return 0
        fi
    done

    local pcp
    pcp=$(tmux display-message -t "${session}:^" -p "#{pane_current_path}" 2>/dev/null) || pcp=""
    if [ -n "$pcp" ]; then
        local name="" proj=""
        if [[ "$pcp" == */.claude/worktrees/* ]]; then
            name=$(basename "$pcp")
            proj="${pcp%%/.claude/worktrees/*}"
        else
            proj=$(resolve_project_path "$pcp")
            local prefix="worker-$(basename "$proj")-"
            [[ "$session" == "$prefix"* ]] && name="${session#$prefix}"
        fi
        if [ -n "$name" ] && [ -n "$proj" ]; then
            rsession=$(bash -c "source \"$SPAWN\" && _worker_session_name \"\$1\" \"\$2\"" _ "$proj" "$name" 2>/dev/null) || rsession=""
            if [ "$rsession" = "$session" ]; then
                echo "${name}|${proj}"
                return 0
            fi
        fi
    fi

    local guess="${session##*-}"
    local resolved
    resolved=$(tmux_scan_project "$guess" 2>/dev/null) || resolved=""
    if [ -n "$resolved" ]; then
        rsession=$(bash -c "source \"$SPAWN\" && _worker_session_name \"\$1\" \"\$2\"" _ "$resolved" "$guess" 2>/dev/null) || rsession=""
        if [ "$rsession" = "$session" ]; then
            echo "${guess}|${resolved}"
            return 0
        fi
    fi
    return 1
}

# _janitor_has_uncommitted PROJECT NAME
#   yes/no/n-a (worktree dir absent) — logged before every real kill.
_janitor_has_uncommitted() {
    local project="$1" name="$2"
    local wt="$project/.claude/worktrees/$name"
    [ -d "$wt" ] || { echo "n/a"; return 0; }
    if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
        echo "yes"
    else
        echo "no"
    fi
}

cmd_janitor() {
    _janitor_parse_args "$@"
    _JANITOR_THRESHOLD_SECS=$((_JANITOR_MAX_AGE_HOURS * 3600))
    _JANITOR_NOW_TS=$(date +%s)
    _janitor_log "event=start dry_run=$_JANITOR_DRY_RUN max_age_hours=$_JANITOR_MAX_AGE_HOURS"
    _janitor_sweep_sessions
    _janitor_sweep_orphans
    _janitor_log "event=end"
}

# _janitor_parse_args ARGS...
#   Sets _JANITOR_DRY_RUN and _JANITOR_MAX_AGE_HOURS (default 12); exits 2 on an unknown arg.
_janitor_parse_args() {
    _JANITOR_DRY_RUN=0
    _JANITOR_MAX_AGE_HOURS=12
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) _JANITOR_DRY_RUN=1; shift ;;
            --max-age-hours) _JANITOR_MAX_AGE_HOURS="${2:?worker-cli janitor: --max-age-hours needs a value}"; shift 2 ;;
            --max-age-hours=*) _JANITOR_MAX_AGE_HOURS="${1#--max-age-hours=}"; shift ;;
            *) echo "worker-cli janitor: unknown arg '$1'" >&2; exit 2 ;;
        esac
    done
}

# _janitor_sweep_sessions
#   Pass 1: age-gated sweep over live worker-* tmux sessions.
_janitor_sweep_sessions() {
    local sessions sess created
    sessions=$(tmux list-sessions -F "#{session_name} #{session_created}" 2>/dev/null | grep "^worker-" || true)
    [ -n "$sessions" ] || return 0
    while IFS=' ' read -r sess created; do
        [ -z "$sess" ] && continue
        _janitor_process_session "$sess" "$created"
    done <<< "$sessions"
}

# _janitor_process_session SESS CREATED
#   Skips young, working and unresolvable sessions; dry-runs or kills the rest.
_janitor_process_session() {
    local sess="$1" created="$2"
    local age=$((_JANITOR_NOW_TS - created))
    [ "$age" -lt "$_JANITOR_THRESHOLD_SECS" ] && return 0

    # A failed probe here means the check itself broke, not that the worker died —
    # $sess was just confirmed live via `tmux list-sessions`, so fall back to
    # a direct has-session recheck: genuinely gone -> dead, else -> working (same
    # decision as the display commands' _status_or_probe_error).
    local status
    status=$(bash -c "source \"$SPAWN\" && _worker_detect_status \"\$1\"" _ "$sess" 2>/dev/null) \
        || status=$(tmux has-session -t "$sess" 2>/dev/null && echo "working" || echo "dead")
    if [ "$status" = "working" ]; then
        echo "SKIP (working): $sess  age=${age}s"
        _janitor_log "action=skip-working session=$sess age_s=$age"
        return 0
    fi

    local resolved rname rproj dirty
    resolved=$(_janitor_resolve_worker "$sess") || resolved=""
    if [ -z "$resolved" ]; then
        echo "SKIP (unresolvable project): $sess  age=${age}s  status=$status"
        _janitor_log "action=skip-unresolvable session=$sess age_s=$age status=${status// /_}"
        return 0
    fi
    rname="${resolved%%|*}"
    rproj="${resolved#*|}"
    dirty=$(_janitor_has_uncommitted "$rproj" "$rname")

    if [ "$_JANITOR_DRY_RUN" = "1" ]; then
        echo "DRY-RUN candidate: $sess  name=$rname project=$rproj age=${age}s status=$status uncommitted=$dirty"
        _janitor_log "action=dry-run-candidate session=$sess name=$rname project=$rproj age_s=$age status=${status// /_} uncommitted=$dirty"
    else
        echo "KILL: $sess  name=$rname project=$rproj age=${age}s status=$status uncommitted=$dirty"
        _janitor_log "action=kill session=$sess name=$rname project=$rproj age_s=$age status=${status// /_} uncommitted=$dirty"
        "$0" kill "$rname" "$rproj" 2>&1 | sed 's/^/  /'
    fi
}

# _janitor_sweep_orphans
#   Pass 2: orphan registry entries — registry file whose tmux session no longer
#   exists. Grace window on file mtime absorbs the spawn race (registry written
#   moments before the tmux session appears).
_janitor_sweep_orphans() {
    [ -d "$REGISTRY_DIR" ] || return 0
    local f
    for f in "$REGISTRY_DIR"/*; do
        [ -f "$f" ] || continue
        [[ "$f" == *.worktrees ]] && continue
        _janitor_process_orphan "$f"
    done
}

# _janitor_process_orphan REGISTRY_FILE
_janitor_process_orphan() {
    local f="$1"
    local oname oproj osession mtime fage dirty
    oname=$(basename "$f")
    oproj=$(cat "$f" 2>/dev/null) || return 0
    [ -z "$oproj" ] && return 0
    osession=$(bash -c "source \"$SPAWN\" && _worker_session_name \"\$1\" \"\$2\"" _ "$oproj" "$oname" 2>/dev/null) || return 0
    tmux has-session -t "$osession" 2>/dev/null && return 0

    mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
    fage=$((_JANITOR_NOW_TS - mtime))
    if [ "$fage" -lt "$_JANITOR_ORPHAN_GRACE_SECS" ]; then
        echo "SKIP (spawn-race grace): $oname  registry_age=${fage}s"
        _janitor_log "action=skip-spawn-race name=$oname project=$oproj registry_age_s=$fage"
        return 0
    fi

    dirty=$(_janitor_has_uncommitted "$oproj" "$oname")
    if [ "$_JANITOR_DRY_RUN" = "1" ]; then
        echo "DRY-RUN orphan-registry candidate: $oname  project=$oproj uncommitted=$dirty"
        _janitor_log "action=dry-run-orphan name=$oname project=$oproj uncommitted=$dirty"
    else
        echo "ORPHAN-CLEAN: $oname  project=$oproj uncommitted=$dirty"
        _janitor_log "action=orphan-clean name=$oname project=$oproj uncommitted=$dirty"
        "$0" kill "$oname" "$oproj" 2>&1 | sed 's/^/  /'
    fi
}
