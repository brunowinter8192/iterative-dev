# Dev Scripts

Development scripts for testing, debugging, and experimentation related to the iterative-dev plugin.

## Documentation Tree

- [pipeline/DOCS.md](pipeline/DOCS.md) — Session pipeline audit scripts

## debug/

### log_permission_request.sh

**Purpose:** Log Claude Code PermissionRequest hook input to file for inspection.
**Usage:**
```bash
# Install as hook in ~/.claude/settings.json under hooks.PermissionRequest
# Output: /tmp/permission_request_log.jsonl
```

## spawn/

### test_direct_command.sh

**Purpose:** Verify tmux session inherits env vars (GH_TOKEN, PATH) when using direct command arg.
**Usage:**
```bash
bash dev/spawn/test_direct_command.sh
```

### test_status_detection.sh

**Purpose:** Verify tmux `#{pane_dead}` transitions from 0→1 after process exits (remain-on-exit mode).
**Usage:**
```bash
bash dev/spawn/test_status_detection.sh
```
