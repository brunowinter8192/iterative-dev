# dev/cc_hooks/

## Role

Claude Code hook-input inspection helpers — install as a CC hook to log raw hook payloads for debugging.

## Modules

### log_permission_request.sh (8 LOC)

**Purpose:** Log Claude Code PermissionRequest hook input to file for inspection.
**Usage:** install as hook in `~/.claude/settings.json` under `hooks.PermissionRequest`; output `/tmp/permission_request_log.jsonl`
