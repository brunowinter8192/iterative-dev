#!/bin/bash

# Auto-Loop Stop Hook
# Keeps Claude going when auto-loop is active.
# Fires "continue" until completion promise is detected or max iterations reached.

set -euo pipefail

HOOK_INPUT=$(cat)

STATE_FILE=".claude/auto-loop.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Parse YAML frontmatter
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')
SESSION_TRANSCRIPT=$(echo "$FRONTMATTER" | grep '^session_transcript:' | sed 's/session_transcript: *//' | sed 's/^"\(.*\)"$/\1/' || echo "")

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "Auto-loop: State file corrupted (iteration: '$ITERATION')" >&2
  rm "$STATE_FILE"
  exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Auto-loop: State file corrupted (max_iterations: '$MAX_ITERATIONS')" >&2
  rm "$STATE_FILE"
  exit 0
fi

# Check max iterations
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "Auto-loop: Max iterations ($MAX_ITERATIONS) reached."
  rm "$STATE_FILE"
  exit 0
fi

# Get transcript path from hook input
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "Auto-loop: Transcript not found ($TRANSCRIPT_PATH)" >&2
  rm "$STATE_FILE"
  exit 0
fi

# Session scoping: bind loop to the session that started it
if [[ -z "$SESSION_TRANSCRIPT" ]]; then
  TEMP_FILE="${STATE_FILE}.tmp.$$"
  awk -v st="session_transcript: \"$TRANSCRIPT_PATH\"" 'NR>1 && /^---$/ && !done {print st; done=1} {print}' "$STATE_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$STATE_FILE"
elif [[ "$SESSION_TRANSCRIPT" != "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# Check completion promise in last assistant message
if grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1)

  if [[ -n "$LAST_LINE" ]]; then
    LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '
      .message.content |
      map(select(.type == "text")) |
      map(.text) |
      join("\n")
    ' 2>/dev/null || echo "")

    if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$LAST_OUTPUT" ]]; then
      PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")

      if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
        echo "Auto-loop: All deliverables complete. Loop ended."
        rm "$STATE_FILE"
        exit 0
      fi
    fi
  fi
fi

# Continue loop
NEXT_ITERATION=$((ITERATION + 1))

# Update iteration counter (atomic)
TEMP_FILE="${STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

SYSTEM_MSG="Auto-loop iteration $NEXT_ITERATION/$MAX_ITERATIONS"

jq -n \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": "continue",
    "systemMessage": $msg
  }'

exit 0
