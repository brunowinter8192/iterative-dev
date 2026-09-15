# src/pipeline/

## Role

Session JSONL analysis utilities for eval workflows and subagent debugging. Touch this package when changing how agent sessions are converted to Markdown, how subagent lists are derived from project directories, or how individual tool calls are extracted. No active external callers in the current codebase — the eval-agent skill that previously invoked these modules has been removed. Modules remain available for ad-hoc eval work via direct `python3 -m` invocation.

## Public Interface

`__init__.py` is empty. Modules invoked as `python3 -m src.pipeline.<module>`. Inter-module dependency: `jsonl_to_md` is the orchestrator/CLI and imports from `jsonl_parse`, `dispatch_context`, `markdown_format`; `list_agents` and `extract_calls` import directly from whichever of those three owns the symbol they need (not from `jsonl_to_md`). Breaking changes in `jsonl_parse`/`dispatch_context`/`markdown_format` can propagate to any of the three consumer modules.

## Modules

### jsonl_to_md.py (43 LOC)

**Purpose:** Orchestrates JSONL-to-Markdown conversion — tool call table, task prompt, final response, optional dispatch context via `--dispatch`.
**Reads:** Claude Code session JSONL files.
**Writes:** Markdown file via `--output` flag.
**Called by:** No caller — invoked directly as `python3 -m src.pipeline.jsonl_to_md`.
**Calls out:** `jsonl_parse`, `dispatch_context`, `markdown_format` (this package).

---

### jsonl_parse.py (143 LOC)

**Purpose:** JSONL loading and message/tool-call parsing primitives (text extraction, error detection, tool_use/tool_result pairing).
**Reads:** nothing directly — pure functions over parsed JSONL data.
**Writes:** nothing.
**Called by:** `jsonl_to_md.py`, `list_agents.py`, `extract_calls.py`, `dispatch_context.py`.
**Calls out:** stdlib json, re, pathlib.

---

### dispatch_context.py (134 LOC)

**Purpose:** Correlates a subagent JSONL back to its main session and extracts the dispatch prompt + surrounding context.
**Reads:** nothing directly — operates on already-loaded message lists.
**Writes:** nothing.
**Called by:** `jsonl_to_md.py`, `list_agents.py`, `markdown_format.py`.
**Calls out:** `jsonl_parse` (text extraction, system-reminder stripping).

---

### markdown_format.py (136 LOC)

**Purpose:** Renders tool calls, dispatch context, and session metadata into the final Markdown summary/detail output.
**Reads:** nothing directly.
**Writes:** output file via `write_output`.
**Called by:** `jsonl_to_md.py`, `extract_calls.py`.
**Calls out:** `dispatch_context` (dispatch section formatting).

---

### list_agents.py (190 LOC)

**Purpose:** Lists subagent sessions for a project with agent type, timestamp, and size. Resolves agent type from main session (sync and async dispatch patterns).
**Reads:** `~/.claude/projects/<encoded_path>/*.jsonl` directory.
**Writes:** stdout (aligned table).
**Called by:** No active external caller.
**Calls out:** `jsonl_parse` (JSONL loading), `dispatch_context` (main session derivation).

---

### extract_calls.py (57 LOC)

**Purpose:** Extracts specific tool calls by number from a session JSONL. Supports listing all calls or extracting full input/output for selected calls.
**Reads:** Session JSONL path.
**Writes:** stdout or Markdown via `--output` flag.
**Called by:** No active external caller.
**Calls out:** `jsonl_parse` (JSONL loading, tool call extraction), `markdown_format` (formatting, output writing).

---

## Usage

```bash
python3 -m src.pipeline.jsonl_to_md --input <path> --output <path> [--dispatch]
python3 -m src.pipeline.list_agents --project <path> [--session latest]
python3 -m src.pipeline.extract_calls --input <path> --calls 1,3 [--output <path>]
```

## Gotchas

- No active external callers — these modules were invoked via the eval-agent skill which has been removed. Re-wire via a new skill or command if eval workflows are reactivated.
