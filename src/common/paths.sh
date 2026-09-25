#!/usr/bin/env bash

# FUNCTIONS

resolve_project_path() {
    local dir="${1:-$(pwd)}"
    case "$dir" in c|.|'') dir="$(pwd)" ;; esac
    [[ "$dir" != /* ]] && dir="$(pwd)/$dir"
    if [[ "$dir" == */.claude/worktrees/* ]]; then
        dir="${dir%%/.claude/worktrees/*}"
    fi
    local d="$dir"
    while [[ "$d" != "/" && -n "$d" ]]; do
        [[ -e "$d/.git" ]] && { echo "$d"; return 0; }
        d="$(dirname "$d")"
    done
    echo "$dir"
}

encode_worktree_path() {
    local p="$1"
    p="${p//\//-}"; p="${p//\./-}"; p="${p//_/-}"
    echo "$p"
}

_worker_project_name() {
    local project_path="$1"
    if [[ "$project_path" == */.claude/worktrees/* ]]; then
        basename "$(echo "$project_path" | sed 's|/.claude/worktrees/.*||')"
    else
        basename "$project_path"
    fi
}

_worker_session_name() {
    local project_path="$1"
    local name="$2"
    local project
    project=$(_worker_project_name "$project_path")
    echo "worker-${project}-${name}"
}
