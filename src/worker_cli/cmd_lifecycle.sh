#!/usr/bin/env bash

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
    session=$(_worker_session_name "$project" "$name")
    echo "Killing worker: $session"
    bash -c "source \"$SPAWN\" && _stop_worker_logger \"\$1\"" _ "$name"
    tmux kill-session -t "$session" 2>/dev/null && echo "  tmux session: killed" || echo "  tmux session: not found"
    git -C "$project" worktree remove --force ".claude/worktrees/$name" 2>/dev/null && echo "  worktree: removed" || echo "  worktree: not found"
    git -C "$project" branch -D "$name" 2>/dev/null && echo "  branch: deleted" || echo "  branch: not found"
    bash -c "source \"$SPAWN\" && _orchestrator_signal_delete \"$session\""
    _kill_cross_project_worktrees "$name"
    registry_delete "$name"
    echo "  registry: removed"
}

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
    local model="${4:-}"
    local worktree_flag=""
    [ "${5:-}" = "--no-worktree" ] && worktree_flag="--no-worktree"
    cd "$PLUGIN" && python3 -m src.spawn.spawn "$name" "$prompt_file" "$project" "$model" $worktree_flag
    registry_write "$name" "$project"
    _spawn_install_death_hook "$name" "$project"
}

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
    local session
    session=$(_worker_session_name "$project" "$name")
    tmux set-hook -t "$session" pane-died \
        "run-shell 'echo \"\$(date -Iseconds) worker=$name session=#{session_name} status=#{pane_dead_status} signal=#{pane_dead_signal}\" >> $death_log'"
}

cmd_revive() {
    [ $# -lt 1 ] && { echo "worker-cli revive: need <name> [project_path]" >&2; exit 2; }
    local name="$1"
    local override="${2:-}"
    local project
    project=$(resolve_worker_project "$name" "$override")
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
