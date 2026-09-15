# dev/session_pipeline/

## Role

Scripts for auditing and evaluating the session pipeline (`src/pipeline/`). All commands assume CWD = project root (iterative-dev/).

## Public Interface

Run manually, no importable interface: `python3 dev/session_pipeline/audit_error_patterns.py [path/to/specific.jsonl]`.

## Flow

JSONL paths in (arg, or all of `~/.claude/projects/` by default) → scans `tool_result` blocks, classifies hard/soft errors → Markdown report out (`md/error_patterns_<timestamp>.md`) + stdout summary.

## Modules

### audit_error_patterns.py (222 LOC)

**Purpose:** Scans Claude Code session JSONLs for error patterns in `tool_result` blocks — evidence for `is_tool_error()` design decisions.
**Reads:** Claude Code session JSONL files (arg, or all of `~/.claude/projects/`).
**Writes:** `dev/session_pipeline/md/error_patterns_<timestamp>.md`; stdout summary.
**Called by:** run manually.
**Calls out:** nothing (stdlib only).
