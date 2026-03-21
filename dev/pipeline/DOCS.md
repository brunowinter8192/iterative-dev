# Pipeline Dev Scripts

Scripts for auditing and evaluating the session pipeline (`src/pipeline/`).

## Working Directory

**CRITICAL:** All commands assume CWD = project root (blank/)

## Scripts

### audit_error_patterns.py

Scans all Claude Code session JSONLs for error patterns in tool_result blocks.

**Purpose:** Produce evidence for `is_tool_error()` design decisions. Separates hard errors (`is_error=True`) from soft errors (no flag but error content in first 500 chars).

**Usage:**
```bash
python3 dev/pipeline/audit_error_patterns.py
python3 dev/pipeline/audit_error_patterns.py path/to/specific.jsonl
```

**Output:** `dev/pipeline/reports/error_patterns_<timestamp>.md`

**Key Finding (2026-03-21):** 40364 tool_results across 1442 sessions. All 1996 hard errors have `is_error=True`. 88 soft errors without flag (65x Traceback, 9x SyntaxError, 8x FileNotFoundError) — all from Bash tool, not MCP. MCP errors return "successfully" with error content, not detectable by flag or pattern alone. Led to `[suspicious: N chars]` marker design in `format_summary_table()`.
