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

tmux_scan_project() {
    local name="$1"
    local count
    count=$(tmux ls 2>/dev/null | grep -cE "^worker-[^:]+-${name}:" || echo 0)
    if [ "$count" -eq 0 ]; then
        return 1
    fi
    if [ "$count" -gt 1 ]; then
        echo "worker-cli: multiple tmux sessions match worker name '$name':" >&2
        tmux ls 2>/dev/null | grep -oE "^worker-[^:]*-${name}[^:]*" >&2
        return 1
    fi
    local session
    session=$(tmux ls 2>/dev/null | grep -oE "^worker-[^:]*-${name}:" | head -1)
    session="${session%:}"
    local middle="${session#worker-}"
    local proj_basename="${middle%-${name}}"
    local found=""
    while IFS= read -r d; do
        if [ -e "$d/.git" ]; then
            found="$d"
            break
        fi
    done < <(find ~/Documents/ai -maxdepth 6 -type d -name "$proj_basename" 2>/dev/null)
    if [ -n "$found" ]; then
        registry_write "$name" "$found"
        echo "$found"
        return 0
    fi
    return 1
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
    local from_tmux
    from_tmux=$(tmux_scan_project "$name" 2>&1) || true
    if [ -n "$from_tmux" ] && [[ "$from_tmux" != *"worker-cli:"* ]]; then
        echo "$from_tmux"
        return 0
    fi
    echo "worker-cli: worker '$name' not found in registry or tmux" >&2
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
    if status=$(bash -c "source \"$SPAWN\" && worker_status \"\$1\" \"\$2\"" _ "$name" "$project" 2>/dev/null); then
        echo "$status"
        return 0
    fi
    local session="worker-$(basename "$project")-$name"
    if tmux has-session -t "$session" 2>/dev/null; then
        echo "working"
    else
        echo "dead"
    fi
}
