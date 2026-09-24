#!/usr/bin/env bash
# registry.sh — project/worker resolution, registry and sidecar helpers for worker-cli. Sourced by bin/worker-cli.

# Resolve project path — accepts absolute path, relative path, or 'c' / '.' / empty.
# Strips /.claude/worktrees/<name> suffix if present, then walks up to nearest .git root.
# NOTE: stops at first .git found — does not traverse into submodules.
resolve_project_path() {
    local dir="${1:-$(pwd)}"
    case "$dir" in c|.|'') dir="$(pwd)" ;; esac
    # Relative path → make absolute
    [[ "$dir" != /* ]] && dir="$(pwd)/$dir"
    # Strip worktree suffix to land at project root directly
    if [[ "$dir" == */.claude/worktrees/* ]]; then
        dir="${dir%%/.claude/worktrees/*}"
    fi
    # Walk up to nearest .git (covers both git dirs and worktree .git files)
    local d="$dir"
    while [[ "$d" != "/" && -n "$d" ]]; do
        [[ -e "$d/.git" ]] && { echo "$d"; return 0; }
        d="$(dirname "$d")"
    done
    echo "$dir"
}

# --- Registry helpers ---

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

# --- Sidecar helpers (cross-project worktrees) ---
# File: $REGISTRY_DIR/<name>.worktrees — one "<target-repo>\t<branch>" per line

sidecar_append() {
    local name="$1" target="$2" branch="$3"
    mkdir -p "$REGISTRY_DIR"
    printf '%s\t%s\n' "$target" "$branch" >> "$REGISTRY_DIR/$name.worktrees"
}

sidecar_delete() {
    local name="$1"
    rm -f "$REGISTRY_DIR/$name.worktrees"
}

# Tmux scan fallback: derive project_path from session name pattern worker-<basename>-<name>.
# Searches ~/Documents/ai/ (3 levels deep) for dir named <basename> containing .git.
# Writes result to registry and returns it. Returns 1 if not found.
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
    # Extract basename: strip "worker-" prefix and "-<name>" suffix
    local middle="${session#worker-}"
    local proj_basename="${middle%-${name}}"
    # Scan ~/Documents/ai/ up to 6 levels for dir named proj_basename containing .git
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

# Resolve project path for a named worker.
# Resolution order: explicit override → registry → tmux scan fallback → error.
# If override is non-empty, treat it as the project_path (backwards compat).
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

# Encode an absolute path to the ~/.claude/projects/ dir name: replace /, ., _ with -.
encode_worktree_path() {
    local p="$1"
    p="${p//\//-}"; p="${p//\./-}"; p="${p//_/-}"
    echo "$p"
}

# _status_or_probe_error NAME PROJECT_PATH
#   Wraps a `worker_status` call for the display-only commands (list, status, status --all).
#   worker_status itself already returns "dead" cleanly (exit 0) for a genuinely gone
#   session — a FAILURE of this outer call means the probe itself broke (source error,
#   bash spawn failure), not a worker state. Recover the best answer we can: genuinely
#   gone session -> dead, anything else -> working (the safe default; a failed probe
#   cannot prove any other state).
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
