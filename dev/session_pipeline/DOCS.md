# dev/session_pipeline/

## Role

Scripts for auditing and evaluating the session pipeline in src/pipeline. All commands assume the project root as working directory.

## Public Interface

No `__init__.py`; run manually: `python3 dev/session_pipeline/audit_error_patterns.py [path/to/specific.jsonl]`.

## Flow

Session JSONL paths in (argument, or all of the Claude Code projects directory by default), scan of tool results and classification into hard and soft errors, Markdown report to md/ and a summary on stdout.

## Modules

### audit_error_patterns.py (222 LOC)

**Purpose:** Scans Claude Code session JSONLs for error patterns in tool results, as evidence for the tool-error classifier design.
**Reads:** Claude Code session JSONL files.
**Writes:** A timestamped report under md/; stdout summary.
**Called by:** Run manually.
**Calls out:** Nothing (standard library only).

## State

None.
