#!/usr/bin/env bash

# FUNCTIONS

cmd_merge() {
    require_arity merge "merge <name>" 1 1 "" "$@"
    local name="$1"
    local spawn_project targets
    spawn_project=$(resolve_worker_project "$name")
    targets=$(_merge_targets "$name" "$spawn_project")
    _merge_all "$name" "$targets"
}

_merge_targets() {
    local name="$1" spawn_project="$2"
    local sidecar="$REGISTRY_DIR/$name.worktrees"
    local repo branch
    {
        printf '%s\t%s\n' "$spawn_project" "$name"
        [ -f "$sidecar" ] && cat "$sidecar"
    } | while IFS=$'\t' read -r repo branch; do
        [ -z "$repo" ] && continue
        [ -z "$branch" ] && branch="$name"
        git -C "$repo" rev-parse --verify -q "refs/heads/$branch" >/dev/null || continue
        printf '%s\t%s\n' "$repo" "$branch"
    done | awk -F'\t' '!seen[$1]++'
    return 0
}

_merge_all() {
    local name="$1" targets="$2"
    if [ -z "$targets" ]; then
        echo "worker-cli merge: no repo holds a branch of worker '$name' (registry project and sidecar worktrees checked)" >&2
        exit 1
    fi
    local merged=0 repo branch
    while IFS=$'\t' read -r repo branch; do
        [ -z "$repo" ] && continue
        if _merge_repo "$name" "$repo" "$branch"; then
            merged=$((merged + 1))
        fi
    done <<< "$targets"
    if [ "$merged" -eq 0 ]; then
        echo "worker-cli merge: worker '$name' carried no commits in any of its repos ($(echo "$targets" | cut -f1 | tr '\n' ' ')) — merge was a no-op. Likely cause: the worker never committed." >&2
        exit 1
    fi
}

_merge_repo() {
    local name="$1" repo="$2" branch="$3"
    local current
    current=$(git -C "$repo" branch --show-current)
    echo "##### repo: $repo #####"
    if [ -z "$current" ]; then
        echo "worker-cli merge: $repo is on a detached HEAD, cannot merge" >&2
        exit 1
    fi
    if [ "$(git -C "$repo" rev-list --count "$current".."$branch")" -eq 0 ]; then
        echo "skipped: branch $branch carries no commits not in $current"
        echo
        return 1
    fi
    echo "=== Commits on branch $branch not in $current ==="
    git -C "$repo" log "$current".."$branch" --oneline -- || true
    echo
    echo "=== Merging $branch into $current ==="
    _merge_run "$repo" "$branch" "$name"
    _merge_verify "$repo"
    echo
    return 0
}

_merge_run() {
    local repo="$1" branch="$2" name="$3"
    local merge_out merge_rc
    set +e
    merge_out=$(git -C "$repo" merge "$branch" --no-ff -m "merge: worker $name")
    merge_rc=$?
    set -e
    echo "$merge_out"
    if [ "$merge_rc" -ne 0 ]; then
        echo "worker-cli merge: merge failed in $repo, stopping" >&2
        exit "$merge_rc"
    fi
}

_merge_verify() {
    local repo="$1"
    local files
    files=$(git -C "$repo" diff ORIG_HEAD --name-only)
    if [ -z "$files" ]; then
        echo "worker-cli merge: merge in $repo completed but brought in no file changes (git diff ORIG_HEAD --name-only was empty)" >&2
        exit 1
    fi
    echo
    echo "=== Files merged ==="
    echo "$files"
}

cmd_kill() {
    require_arity kill "kill <name>" 1 1 "" "$@"
    local name="$1"
    local project
    project=$(resolve_worker_project "$name")
    _kill_worker "$name" "$project"
}

_kill_worker() {
    local name="$1" project="$2"
    local session
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
    require_arity send "send <name> <message>" 2 2 "" "$@"
    local name="$1"
    local message="$2"
    local project
    project=$(resolve_worker_project "$name")
    _WORKER_MSG="$message" bash -c 'source "$1" && worker_send "$2" "$_WORKER_MSG" "$3"' \
        _ "$SPAWN" "$name" "$project"
}

cmd_spawn() {
    local form="spawn <name> <prompt_file> [--no-worktree]"
    local note="spawn takes no project_path and no model: the project is the current one, the model comes from the config."
    local worktree_flag="" positional=() arg
    for arg in "$@"; do
        case "$arg" in
            --no-worktree) worktree_flag="--no-worktree" ;;
            *)             positional+=("$arg") ;;
        esac
    done
    require_arity spawn "$form" 2 2 "$note" "${positional[@]}"
    local name="${positional[0]}"
    local prompt_file="${positional[1]}"; [[ "$prompt_file" != /* ]] && prompt_file="$(pwd)/$prompt_file"
    local project
    project=$(_spawn_resolve_project)
    cd "$PLUGIN" && python3 -m src.spawn.spawn "$name" "$prompt_file" "$project" $worktree_flag
    registry_write "$name" "$project"
    _spawn_install_death_hook "$name" "$project"
}

_spawn_resolve_project() {
    local project
    if [ -n "${PROXY_PROJECT_PATH:-}" ]; then
        resolve_project_path "$PROXY_PROJECT_PATH"
        return 0
    fi
    project=$(resolve_project_path "$(pwd)")
    if [ ! -e "$project/.git" ]; then
        echo "worker-cli spawn: current directory $(pwd) is not inside a git repo; run spawn from the project you want the worker in" >&2
        exit 1
    fi
    echo "$project"
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
    require_arity revive "revive <name>" 1 1 "" "$@"
    local name="$1"
    local project
    project=$(resolve_worker_project "$name")
    bash -c "source \"$SPAWN\" && worker_revive \"\$1\" \"\$2\"" _ "$name" "$project"
}

cmd_worktree() {
    require_arity worktree "worktree <name> <target_repo> [branch]" 2 3 "" "$@"
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
    require_arity worktree-rm "worktree-rm <target_repo> <name> [branch]" 2 3 "" "$@"
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
    local dry_run=0 max_age_hours="" positional=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run=1; shift ;;
            --max-age-hours) max_age_hours="${2:?worker-cli sweep-logs: --max-age-hours needs a value}"; shift 2 ;;
            --max-age-hours=*) max_age_hours="${1#--max-age-hours=}"; shift ;;
            *) positional+=("$1"); shift ;;
        esac
    done
    require_arity sweep-logs "sweep-logs [--dry-run] [--max-age-hours N] [logdir]" 0 1 "" "${positional[@]}"
    local log_dir="${positional[0]:-${WORKER_LOGGER_DIR:-$HOME/Documents/ai/Meta/iterative-dev/src/logs}}"
    bash -c "source \"$SPAWN\" && sweep_stale_logs \"\$1\" \"\$2\" \"\$3\"" \
        _ "$log_dir" "$max_age_hours" "$dry_run"
}
