#!/bin/bash

# INFRASTRUCTURE

LOG_FILE="/tmp/permission_request_log.jsonl"

# ORCHESTRATOR

log_permission_request_workflow() {
    local input
    input=$(_read_hook_input)
    _append_log_entry "$input"
}

# FUNCTIONS

_read_hook_input() {
    cat
}

_append_log_entry() {
    local input="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"timestamp\":\"$timestamp\",\"input\":$input}" >> "$LOG_FILE"
}

log_permission_request_workflow
exit 0
