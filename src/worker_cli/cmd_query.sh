#!/usr/bin/env bash

# FUNCTIONS

cmd_list() {
    require_arity list "list" 0 0 "" "$@"
    _print_registry_workers "(no known workers in registry)" 1
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
        require_arity status "status --all" 0 0 "" "$@"
        _print_registry_workers "(no active workers)" 0
        return 0
    fi
    require_arity status "status <name> | worker-cli status --all" 1 1 "" "$@"
    local name="$1"
    local project status
    project=$(resolve_worker_project "$name")
    status=$(_status_or_probe_error "$name" "$project")
    echo "${status}"
}

cmd_capture() {
    local raw=0 positional=() arg
    for arg in "$@"; do
        case "$arg" in
            --raw) raw=1 ;;
            *)     positional+=("$arg") ;;
        esac
    done
    require_arity capture "capture <name> [--raw]" 1 1 "" "${positional[@]}"
    local name="${positional[0]}"
    local project
    project=$(resolve_worker_project "$name")
    if [ "$raw" = "1" ]; then
        bash -c "source \"$SPAWN\" && worker_capture \"\$1\" \"\" \"\$2\"" \
            _ "$name" "$project"
    else
        bash -c "source \"$SPAWN\" && worker_capture_clean \"\$1\" \"\$2\"" \
            _ "$name" "$project"
    fi
}

cmd_response() {
    local form="response <name> [count]"
    require_arity response "$form" 1 2 "" "$@"
    local name="$1"
    local count=1
    if [ -n "${2:-}" ]; then
        [[ "$2" =~ ^[0-9]+$ ]] || arg_unexpected response "$form" "" "$2"
        count="$2"
    fi
    local project jsonl text
    project=$(resolve_worker_project "$name")
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
