#!/usr/bin/env bash
# notify_parent.sh WINDOW_ID WORKER_NAME
# Sends "Worker done" message to parent Ghostty terminal via AppleScript.
# Called automatically after worker's claude process exits.
# Silent fail if window no longer exists (2>/dev/null).

set -euo pipefail

WINDOW_ID="${1:?Usage: notify_parent.sh WINDOW_ID WORKER_NAME}"
WORKER_NAME="${2:?Usage: notify_parent.sh WINDOW_ID WORKER_NAME}"

osascript -e "
tell application \"Ghostty\"
    set w to window id \"$WINDOW_ID\"
    set t to selected tab of w
    set trm to terminal 1 of t
    input text \"Worker $WORKER_NAME ist fertig.\" to trm
    send key \"enter\" to trm
end tell
" 2>/dev/null || true
