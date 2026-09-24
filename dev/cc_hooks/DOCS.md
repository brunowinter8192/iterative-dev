# dev/cc_hooks/

## Role

Claude Code hook-input inspection helper. Install it as a hook to log raw hook payloads for debugging. Touch when a new hook payload needs inspecting.

## Public Interface

No `__init__.py`; installed by adding the script under the PermissionRequest hook in the Claude Code settings.

## Flow

Hook payload on stdin, appended with a timestamp to a log file, then passed through unchanged so the normal permission flow is not disturbed.

## Modules

### log_permission_request.sh (8 LOC)

**Purpose:** Logs the PermissionRequest hook input to a JSON-lines file for inspection and passes the payload through.
**Reads:** stdin (hook payload).
**Writes:** A JSON-lines log file under /tmp.
**Called by:** Claude Code, as a configured hook.
**Calls out:** None (shell builtins, date).

## State

None.
