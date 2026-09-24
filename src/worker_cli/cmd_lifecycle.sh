#!/usr/bin/env bash
# cmd_lifecycle.sh — state-changing worker-cli subcommands: merge, kill, send, spawn, revive, worktree, worktree-rm, sweep-logs. Sourced by bin/worker-cli.

cmd_merge() {
    [ $# -lt 1 ] && { echo "worker-cli merge: need <name> [project_path]" >&2; exit 2; }
    local name="$1"
    local override="${2:-}"
    local project current
    project=$(resolve_worker_project "$name" "$override")
    current=$(git -C "$project" branch --show-current)
    echo "=== Commits on branch $name not in $current ==="
    git -C "$project" log "$current".."$name" --oneline -- || true
    echo
    echo "=== Merging $name into $current ==="
    _merge_run "$project" "$name" "$current"
    _merge_verify "$project" "$name" "$current"
}

# _merge_run PROJECT NAME CURRENT
#   set +e around the merge itself: under this script's set -e, a failing
#   assignment (`VAR=$(cmd)` where cmd exits non-zero — a real conflict) would abort
#   BEFORE the echo below ever ran, swallowing git's own conflict output. Capture the
#   exit code explicitly instead and echo the output unconditionally, so a conflict
#   is exactly as visible as it was before this command captured anything.
#   Stores the merge output in _MERGE_OUT; exits with git's code on failure.
_merge_run() {
    local project="$1" name="$2"
    local merge_rc
    set +e
    _MERGE_OUT=$(git -C "$project" merge "$name" --no-ff -m "merge: worker $name")
    merge_rc=$?
    set -e
    echo "$_MERGE_OUT"
    [ "$merge_rc" -ne 0 ] && exit "$merge_rc"
    return 0
}

# _merge_verify PROJECT NAME CURRENT
#   Loud, deterministic outcome check (2026, retired the orchestrator's by-hand
#   post-merge verification) — "Already up to date." means the branch carried zero
#   commits into $CURRENT; the two known causes are a cross-project worker merged
#   without its project_path (branch lives in the other repo) and a worker that
#   never committed.
#   ORIG_HEAD is the pre-merge tip of $CURRENT — a diff against it covers every
#   commit the merge brought in, unlike HEAD~1 which would miss earlier commits on
#   a multi-commit branch.
_merge_verify() {
    local project="$1" name="$2" current="$3"
    if [[ "$_MERGE_OUT" == *"Already up to date"* ]]; then
        echo "worker-cli merge: branch '$name' carried no commits into '$current' — merge was a no-op. Likely causes: (1) a cross-project worker merged without its project_path (the branch lives in the other repo), (2) the worker never committed." >&2
        exit 1
    fi
    local files
    files=$(git -C "$project" diff ORIG_HEAD --name-only)
    if [ -z "$files" ]; then
        echo "worker-cli merge: merge completed but brought in no file changes (git diff ORIG_HEAD --name-only was empty)" >&2
        exit 1
    fi
    echo
    echo "=== Files merged ==="
    echo "$files"
}

cmd_kill() {
    [ $# -lt 1 ] && { echo "worker-cli kill: need <name> [project_path]" >&2; exit 2; }
    local name="$1"
    local override="${2:-}"
    local project session
    project=$(resolve_worker_project "$name" "$override")
    session="worker-$(basename "$project")-$name"
    echo "Killing worker: $session"
    bash -c "source \"$SPAWN\" && _stop_worker_logger \"\$1\"" _ "$name" 2>/dev/null || true
    tmux kill-session -t "$session" 2>/dev/null && echo "  tmux session: killed" || echo "  tmux session: not found"
    git -C "$project" worktree remove --force ".claude/worktrees/$name" 2>/dev/null && echo "  worktree: removed" || echo "  worktree: not found"
    git -C "$project" branch -D "$name" 2>/dev/null && echo "  branch: deleted" || echo "  branch: not found"
    bash -c "source \"$SPAWN\" && _orchestrator_signal_delete \"$session\"" 2>/dev/null || true
    _kill_cross_project_worktrees "$name"
    registry_delete "$name"
    echo "  registry: removed"
}

# _kill_cross_project_worktrees NAME
#   Cleans cross-project worktrees registered in the sidecar (best-effort — never blocks registry_delete).
_kill_cross_project_worktrees() {
    local name="$1"
    local sidecar="$REGISTRY_DIR/$name.worktrees"
    [ -f "$sidecar" ] || return 0
    local xrepo xbranch
    while IFS=$'\t' read -r xrepo xbranch; do
        [ -z "$xrepo" ] && continue
        [ -z "$xbranch" ] && xbranch="$name"
        git -C "$xrepo" worktree remove --force ".claude/worktrees/$name" 2>/dev/null \
            && echo "  cross-project worktree ($xrepo): removed" \
            || echo "  cross-project worktree ($xrepo): not found"
        git -C "$xrepo" branch -D "$xbranch" 2>/dev/null \
            && echo "  cross-project branch $xbranch ($xrepo): deleted" \
            || echo "  cross-project branch $xbranch ($xrepo): not found"
    done < "$sidecar"
    rm -f "$sidecar"
    echo "  cross-project sidecar: removed"
}

cmd_send() {
    [ $# -lt 2 ] && { echo "worker-cli send: need <name> <message> [project_path]" >&2; exit 2; }
    local name="$1"
    local message="$2"
    local override="${3:-}"
    local project
    project=$(resolve_worker_project "$name" "$override")
    _WORKER_MSG="$message" bash -c 'source "$1" && worker_send "$2" "$_WORKER_MSG" "$3"' \
        _ "$SPAWN" "$name" "$project"
}

cmd_spawn() {
    [ $# -lt 3 ] && { echo "worker-cli spawn: need <name> <prompt_file> <project_path> [model] [--no-worktree]" >&2; exit 2; }
    local name="$1"
    local prompt_file="$2"; [[ "$prompt_file" != /* ]] && prompt_file="$(pwd)/$prompt_file"
    local project
    project=$(_spawn_resolve_project "$3")
    # 2026-08 (model-selector milestone 3 fix): do NOT pre-resolve a hardcoded default here —
    # that shadowed spawn.py's own config-file resolution (args.model was never actually
    # None on this path, since a concrete literal always arrived as the 4th positional).
    # Pass through empty when no model arg was given; spawn.py's `args.model or
    # _resolve_worker_model()` treats an empty string as falsy and resolves it correctly.
    local model="${4:-}"
    local worktree_flag=""
    [ "${5:-}" = "--no-worktree" ] && worktree_flag="--no-worktree"
    cd "$PLUGIN" && python3 -m src.spawn.spawn "$name" "$prompt_file" "$project" "$model" $worktree_flag
    registry_write "$name" "$project"
    _spawn_install_death_hook "$name" "$project"
}

# _spawn_resolve_project REQUESTED_ARG
#   Echoes the project to spawn into: the PROXY_PROJECT_PATH policy override (with a stderr
#   notice when the requested path differs) or the requested path itself.
_spawn_resolve_project() {
    local requested project
    requested=$(resolve_project_path "$1")
    if [ -n "${PROXY_PROJECT_PATH:-}" ]; then
        project=$(resolve_project_path "$PROXY_PROJECT_PATH")
        if [ "$requested" != "$project" ]; then
            echo "worker-cli spawn: spawning into main session project $project (PROXY_PROJECT_PATH policy); project_path arg '$1' ignored — for cross-project work, create a worktree in the target project and have the worker cd there" >&2
        fi
        echo "$project"
    else
        echo "$requested"
    fi
}

_spawn_install_death_hook() {
    local name="$1" project="$2"
    local death_log="$HOME/.claude/worker-deaths.log"
    local session="worker-$(basename "$project")-$name"
    tmux set-hook -t "$session" pane-died \
        "run-shell 'echo \"\$(date -Iseconds) worker=$name session=#{session_name} status=#{pane_dead_status} signal=#{pane_dead_signal}\" >> $death_log'" 2>/dev/null || true
}

cmd_revive() {
    [ $# -lt 1 ] && { echo "worker-cli revive: need <name> [project_path]" >&2; exit 2; }
    local name="$1"
    local override="${2:-}"
    local project
    project=$(resolve_worker_project "$name" "$override")
    # Delegate full revive flow (gates + proxy setup + session recreate) to worker_revive
    # in tmux_spawn.sh. CRITICAL: this now includes _worker_proxy_setup so the prompt-cache
    # prefix on the Anthropic side matches what the worker had before death — without that
    # the entire conversation context would be re-uploaded on resume (cache miss).
    bash -c "source \"$SPAWN\" && worker_revive \"\$1\" \"\$2\"" _ "$name" "$project"
}

cmd_worktree() {
    [ $# -lt 2 ] && { echo "worker-cli worktree: need <name> <target-repo> [branch]" >&2; exit 2; }
    local name="$1"
    local target
    target=$(resolve_project_path "$2")
    local branch="${3:-$name}"
    if ! git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
        echo "worker-cli worktree: '$target' is not a git repo" >&2
        exit 1
    fi
    local wt_path="$target/.claude/worktrees/$name"
    if [ -d "$wt_path" ]; then
        echo "worker-cli worktree: worktree already exists at $wt_path" >&2
        exit 1
    fi
    if ! git -C "$target" worktree add ".claude/worktrees/$name" -b "$branch"; then
        echo "worker-cli worktree: failed to create worktree in $target" >&2
        exit 1
    fi
    sidecar_append "$name" "$target" "$branch"
    echo "$wt_path"
}

cmd_worktree_rm() {
    [ $# -lt 2 ] && { echo "worker-cli worktree-rm: need <target-repo> <name> [branch]" >&2; exit 2; }
    local target
    target=$(resolve_project_path "$1")
    local name="$2"
    local branch="${3:-$name}"
    git -C "$target" worktree remove --force ".claude/worktrees/$name" 2>/dev/null \
        && echo "  worktree removed" || echo "  worktree not found"
    git -C "$target" branch -D "$branch" 2>/dev/null \
        && echo "  branch '$branch' deleted" || echo "  branch '$branch' not found"
}

# cmd_sweep_logs [--dry-run] [--max-age-hours N] [LOG_DIR]
#   Retention sweep for the log DIRECTORY (WORKER_LOGGER_DIR / its default) — a
#   different concern from `janitor`, which sweeps stale tmux WORKER SESSIONS.
#   Deliberately not named or logged anywhere near "janitor" so the two can never be
#   conflated: this one deletes old files by mtime, that one kills old sessions by
#   session_created age. See process-docs/worker_sweep_logs/ for the 2026-09-17
#   decision (destination move off Meta/blank + this sweep, in the same milestone).
#   sweep_stale_logs (src/spawn/worker_log_sidecar.sh) owns the actual default (72h) and the
#   wait_trace.log exclusion — this is a thin CLI delegate, same pattern as
#   `wait`/`revive`/`list`, so the auto-triggered call from `_start_worker_logger` and this
#   manual call share one implementation.
cmd_sweep_logs() {
    local dry_run=0 max_age_hours="" logdir_override=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run=1; shift ;;
            --max-age-hours) max_age_hours="${2:?worker-cli sweep-logs: --max-age-hours needs a value}"; shift 2 ;;
            --max-age-hours=*) max_age_hours="${1#--max-age-hours=}"; shift ;;
            *) logdir_override="$1"; shift ;;
        esac
    done
    local log_dir="${logdir_override:-${WORKER_LOGGER_DIR:-$HOME/Documents/ai/Meta/iterative-dev/src/logs}}"
    bash -c "source \"$SPAWN\" && sweep_stale_logs \"\$1\" \"\$2\" \"\$3\"" \
        _ "$log_dir" "$max_age_hours" "$dry_run"
}
