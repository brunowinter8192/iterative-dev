#!/usr/bin/env bash

# FUNCTIONS

cmd_list() {
    if [ $# -eq 0 ]; then
        _print_registry_workers "(no known workers in registry)" 1
    else
        local project
        project=$(resolve_project_path "$1")
        bash -c "source \"$SPAWN\" && worker_list \"\$1\"" _ "$project"
    fi
}

_print_registry_workers() {
    local empty_message="$1" with_path="$2"
    if [ ! -d "$REGISTRY_DIR" ] || [ -z "$(ls -A "$REGISTRY_DIR" 2>/dev/null)" ]; then
        echo "$empty_message"
        return 0
    fi
    local f wname proj status
    for f in "$REGISTRY_DIR"/*; do
        [ -f "$f" ] || continue
        [[ "$f" == *.worktrees ]] && continue
        wname=$(basename "$f")
        proj=$(cat "$f")
        status=$(_status_or_probe_error "$wname" "$proj")
        if [ "$with_path" = "1" ]; then
            echo "${wname}: ${status}  (${proj})"
        else
            echo "${wname}: ${status}"
        fi
    done
}

cmd_status() {
    if [ "${1:-}" = "--all" ]; then
        shift
        _status_all "$@"
    else
        [ $# -lt 1 ] && { echo "worker-cli status: need <name> [project_path]" >&2; exit 2; }
        local name="$1"
        local override="${2:-}"
        local project status
        project=$(resolve_worker_project "$name" "$override")
        status=$(_status_or_probe_error "$name" "$project")
        echo "${status}"
    fi
}

_status_all() {
    if [ $# -ge 1 ]; then
        _status_all_in_project "$1"
    else
        _print_registry_workers "(no active workers)" 0
    fi
}

_status_all_in_project() {
    local project names wname status
    project=$(resolve_project_path "$1")
    names=$(bash -c "source \"$SPAWN\" && worker_list \"\$1\"" _ "$project" \
        | awk '{print $1}')
    if [ -z "$names" ]; then
        echo "(no active workers)"
        return 0
    fi
    while IFS= read -r wname; do
        status=$(_status_or_probe_error "$wname" "$project")
        echo "${wname}: ${status}"
    done <<< "$names"
}

cmd_capture() {
    [ $# -lt 1 ] && { echo "worker-cli capture: need <name> [--raw] [project_path]" >&2; exit 2; }
    local name="$1"; shift
    local raw=0 override=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --raw) raw=1 ;;
            *)     override="$1" ;;
        esac
        shift
    done
    local project
    project=$(resolve_worker_project "$name" "$override")
    if [ "$raw" = "1" ]; then
        bash -c "source \"$SPAWN\" && worker_capture \"\$1\" \"\" \"\$2\"" \
            _ "$name" "$project"
    else
        bash -c "source \"$SPAWN\" && worker_capture_clean \"\$1\" \"\$2\"" \
            _ "$name" "$project"
    fi
}

cmd_response() {
    [ $# -lt 1 ] && { echo "worker-cli response: need <name> [count] [project_path]" >&2; exit 2; }
    local name="$1"
    local count=1
    local override=""
    if [ -n "${2:-}" ]; then
        if [[ "$2" =~ ^[0-9]+$ ]]; then
            count="$2"
            override="${3:-}"
        else
            override="$2"
        fi
    fi
    local project jsonl text
    project=$(resolve_worker_project "$name" "$override")
    jsonl=$(_response_find_jsonl "$name" "$project")
    text=$(_response_extract_text "$jsonl" "$count")
    if [ -z "$text" ]; then
        echo "worker-cli response: no assistant text message found in $jsonl" >&2
        exit 5
    fi
    echo "=== response from $name (last $count, ${#text} chars) ==="
    echo "$text"
}

_response_find_jsonl() {
    local name="$1" project="$2"
    local worktree="$project/.claude/worktrees/$name"
    if [ ! -d "$worktree" ]; then
        echo "worker-cli response: no worktree for $name at $worktree" >&2
        exit 2
    fi
    local projects_dir="$HOME/.claude/projects"
    if [ ! -d "$projects_dir" ]; then
        echo "worker-cli response: ~/.claude/projects not found" >&2
        exit 3
    fi
    local encoded_dir="$projects_dir/$(encode_worktree_path "$worktree")"
    local jsonl
    jsonl=$(ls -t "$encoded_dir"/*.jsonl 2>/dev/null | head -1)
    if [ -z "$jsonl" ]; then
        echo "worker-cli response: no session JSONL found for $name at $encoded_dir" >&2
        exit 4
    fi
    echo "$jsonl"
}

_response_extract_text() {
    local jsonl="$1" count="$2"
    jq -rs --argjson n "$count" '[.[] | select(.type == "assistant" and (.message.content // [] | map(select(.type == "text")) | length > 0))] | if length == 0 then "" else (.[-($n):] | length as $L | to_entries | map("=== msg \(.key + 1)/\($L) ===\n" + (.value.message.content | map(select(.type == "text")) | map(.text) | join("\n\n"))) | join("\n\n")) end' "$jsonl"
}
