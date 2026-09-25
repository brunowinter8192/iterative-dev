# src/pipeline/

## Role

Session JSONL analysis utilities for eval workflows and subagent debugging: Markdown conversion, subagent listing, tool-call extraction. No active external callers; the former eval-agent skill is gone, modules stay available via `python3 -m`. Touch when changing those conversions.

## Public Interface

`__init__.py` is empty. Modules invoked as `python3 -m src.pipeline.<module>` (`jsonl_to_md --input <path> --output <path> [--dispatch]`, `list_agents --project <path> [--session latest]`, `extract_calls --input <path> --calls 1,3 [--output <path>]`). `jsonl_to_md` is the orchestrator/CLI and imports from `jsonl_parse`, `dispatch_context`, `markdown_format`; `list_agents` and `extract_calls` import directly from whichever of those three owns the symbol they need.

## Flow

JSONL path in → `jsonl_parse` loads + extracts tool calls → `dispatch_context` correlates the main session (optional) → `markdown_format` renders the summary/detail Markdown → stdout or `--output` file out.

## Modules

### jsonl_to_md.py (56 LOC)

**Purpose:** Orchestrates JSONL-to-Markdown conversion — tool call table, task prompt, final response, optional dispatch context via `--dispatch`.
**Reads:** Claude Code session JSONL files.
**Writes:** Markdown file via `--output` flag.
**Called by:** No caller — invoked directly as `python3 -m src.pipeline.jsonl_to_md`.
**Calls out:** `jsonl_parse`, `dispatch_context`, `markdown_format` (this package).

---

### jsonl_parse.py (127 LOC)

**Purpose:** JSONL loading and message/tool-call parsing primitives (text extraction, error detection, tool_use/tool_result pairing).
**Reads:** nothing directly — pure functions over parsed JSONL data.
**Writes:** nothing.
**Called by:** `jsonl_to_md.py`, `list_agents.py`, `extract_calls.py`, `dispatch_context.py`.
**Calls out:** stdlib json, re, pathlib.

---

### dispatch_context.py (127 LOC)

**Purpose:** Correlates a subagent JSONL back to its main session and extracts the dispatch prompt + surrounding context.
**Reads:** nothing directly — operates on already-loaded message lists.
**Writes:** nothing.
**Called by:** `jsonl_to_md.py`, `list_agents.py`, `markdown_format.py`.
**Calls out:** `jsonl_parse` (text extraction, system-reminder stripping).

---

### markdown_format.py (125 LOC)

**Purpose:** Renders tool calls, dispatch context, and session metadata into the final Markdown summary/detail output.
**Reads:** nothing directly.
**Writes:** the Markdown output file.
**Called by:** `jsonl_to_md.py`, `extract_calls.py`.
**Calls out:** `dispatch_context` (dispatch section formatting).

---

### list_agents.py (200 LOC)

**Purpose:** Lists subagent sessions for a project with agent type, timestamp, and size. Resolves agent type from main session (sync and async dispatch patterns).
**Reads:** `~/.claude/projects/<encoded_path>/`, where the project path has `/`, `.` and `_` replaced by `-`.
**Writes:** stdout (aligned table).
**Called by:** No active external caller.
**Calls out:** `jsonl_parse` (JSONL loading), `dispatch_context` (main session derivation).

---

### extract_calls.py (60 LOC)

**Purpose:** Extracts specific tool calls by number from a session JSONL. Supports listing all calls or extracting full input/output for selected calls.
**Reads:** Session JSONL path.
**Writes:** stdout or Markdown via `--output` flag.
**Called by:** No active external caller.
**Calls out:** `jsonl_parse` (JSONL loading, tool call extraction), `markdown_format` (formatting, output writing).

## State

No shared mutable state between modules — `jsonl_parse`, `dispatch_context`, and `markdown_format` are pure-function libraries operating on message lists passed in by the caller.
