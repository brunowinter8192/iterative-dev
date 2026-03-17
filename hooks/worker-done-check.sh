#!/usr/bin/env bash
# worker-done-check.sh — PostToolUse hook for worker-done notifications.
# Checks for /tmp/worker-*.done signal files on every tool call.
# If found: returns systemMessage with worker names, deletes signal files.
# If not found: exits silently (zero overhead).

set -euo pipefail

done_files=(/tmp/worker-*.done)

# No .done files → silent exit
if [[ ! -e "${done_files[0]}" ]]; then
    exit 0
fi

# Collect finished worker names
messages=()
for f in "${done_files[@]}"; do
    name=$(basename "$f" .done | sed 's/^worker-//')
    messages+=("Worker $name ist fertig.")
    rm -f "$f"
done

# Return systemMessage as JSON
msg=$(printf '%s ' "${messages[@]}")
printf '{"systemMessage": "%s"}' "$msg"
