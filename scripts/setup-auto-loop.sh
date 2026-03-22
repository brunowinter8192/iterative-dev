#!/bin/bash

# Auto-Loop Setup Script
# Creates state file for autonomous plan execution loop.

set -euo pipefail

PLAN_FILE=""
MAX_ITERATIONS=20

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Auto-Loop Setup - Autonomous plan execution

USAGE:
  setup-auto-loop.sh <plan-file> [OPTIONS]

ARGUMENTS:
  plan-file    Path to the plan file (.claude/plans/...)

OPTIONS:
  --max-iterations <n>  Maximum iterations (default: 20)
  -h, --help            Show this help

EXAMPLES:
  setup-auto-loop.sh .claude/plans/my-plan.md
  setup-auto-loop.sh .claude/plans/my-plan.md --max-iterations 30
HELP_EOF
      exit 0
      ;;
    --max-iterations)
      if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "❌ --max-iterations requires a positive integer" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    *)
      if [[ -z "$PLAN_FILE" ]]; then
        PLAN_FILE="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$PLAN_FILE" ]]; then
  echo "❌ No plan file provided" >&2
  echo "   Usage: setup-auto-loop.sh <plan-file> [--max-iterations N]" >&2
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "❌ Plan file not found: $PLAN_FILE" >&2
  exit 1
fi

mkdir -p .claude

cat > .claude/auto-loop.local.md <<EOF
---
active: true
iteration: 1
max_iterations: $MAX_ITERATIONS
completion_promise: "ALL_DELIVERABLES_COMPLETE"
plan_file: "$PLAN_FILE"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

🔨 IMPLEMENT

Continue working on the plan at $PLAN_FILE.

Read the plan file. Check which deliverables are still open. Work on the next open deliverable.
After completing a deliverable, move to the next one.

When ALL deliverables are complete and verified:
Output <promise>ALL_DELIVERABLES_COMPLETE</promise>

Rules:
- Do NOT output the promise until ALL deliverables are genuinely complete
- Do NOT lie to exit the loop
- Work systematically through the plan
- Verify each deliverable before moving on
EOF

cat <<EOF
🔄 Auto-loop activated!

Plan file: $PLAN_FILE
Max iterations: $MAX_ITERATIONS
Completion promise: ALL_DELIVERABLES_COMPLETE

The stop hook will keep Claude working on the plan until all deliverables
are complete or max iterations are reached.

To cancel: /cancel-loop
To monitor: head -10 .claude/auto-loop.local.md
EOF
