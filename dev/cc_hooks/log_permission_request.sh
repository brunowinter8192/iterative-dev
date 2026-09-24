#!/bin/bash
INPUT=$(cat)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="/tmp/permission_request_log.jsonl"

echo "{\"timestamp\":\"$TIMESTAMP\",\"input\":$INPUT}" >> "$LOG_FILE"

exit 0
