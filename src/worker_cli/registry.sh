#!/usr/bin/env bash

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

registry_write() {
    local name="$1" project="$2"
    mkdir -p "$REGISTRY_DIR"
    echo "$project" > "$REGISTRY_DIR/$name"
}

registry_read() {
    local name="$1"
    local f="$REGISTRY_DIR/$name"
    [ -f "$f" ] && cat "$f" || echo ""
}

registry_delete() {
    local name="$1"
    rm -f "$REGISTRY_DIR/$name"
}

sidecar_append() {
    local name="$1" target="$2" branch="$3"
    mkdir -p "$REGISTRY_DIR"
    printf '%s\t%s\n' "$target" "$branch" >> "$REGISTRY_DIR/$name.worktrees"
}

sidecar_delete() {
    local name="$1"
    rm -f "$REGISTRY_DIR/$name.worktrees"
}

resolve_worker_project() {
    local name="$1"
    local override="${2:-}"
    if [ -n "$override" ]; then
        resolve_project_path "$override"
        return 0
    fi
    local from_registry
    from_registry=$(registry_read "$name")
    if [ -n "$from_registry" ]; then
        echo "$from_registry"
        return 0
    fi
    echo "worker-cli: worker '$name' not found in registry" >&2
    exit 1
}

encode_worktree_path() {
    local p="$1"
    p="${p//\//-}"; p="${p//\./-}"; p="${p//_/-}"
    echo "$p"
}

_status_or_probe_error() {
    local name="$1" project="$2"
    local status
    if status=$(bash -c "source \"$SPAWN\" && worker_status \"\$1\" \"\$2\"" _ "$name" "$project"); then
        echo "$status"
        return 0
    fi
    local session="worker-$(basename "$project")-$name"
    local fallback
    if tmux has-session -t "$session" 2>/dev/null; then
        fallback="working"
    else
        fallback="dead"
    fi
    echo "worker-cli: status probe failed for $name, reporting $fallback" >&2
    echo "$fallback"
}
