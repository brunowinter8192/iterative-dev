---
description: Cancel active auto-loop
allowed-tools: Bash
---

Cancel the active auto-loop by removing the state file.

```bash
if [ -f .claude/auto-loop.local.md ]; then
  ITERATION=$(sed -n 's/^iteration: *//p' .claude/auto-loop.local.md)
  rm .claude/auto-loop.local.md
  echo "✅ Auto-loop cancelled (was at iteration $ITERATION)"
else
  echo "ℹ️  No active auto-loop found"
fi
```
