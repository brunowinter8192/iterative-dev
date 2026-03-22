---
description: Start autonomous plan execution loop
arguments:
  - name: plan_file
    description: Path to the plan file
    required: true
  - name: max_iterations
    description: "Max iterations (default: 20)"
    required: false
allowed-tools: Bash
---

Start the auto-loop for autonomous plan execution.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-auto-loop.sh" "$ARGUMENTS_PLAN_FILE" $([[ -n "${ARGUMENTS_MAX_ITERATIONS:-}" ]] && echo "--max-iterations $ARGUMENTS_MAX_ITERATIONS")
```
