# src/pipeline/

## Role

Session JSONL analysis utilities for eval workflows and subagent debugging. Touch this package when changing how agent sessions are converted to Markdown, how subagent lists are derived from project directories, or how individual tool calls are extracted. No active external callers in the current codebase — the eval-agent skill that previously invoked these modules has been removed. Modules remain available for ad-hoc eval work via direct `python3 -m` invocation.

## Public Interface

`__init__.py` is empty. Modules invoked as `python3 -m src.pipeline.<module>`. Inter-module dependency: `list_agents` and `extract_calls` import from `jsonl_to_md` for JSONL parsing, session derivation, and formatting. Breaking changes in `jsonl_to_md` propagate to both.

## Modules

### jsonl_to_md.py (437 LOC) ⚠️ refactor candidate

**Purpose:** Converts Claude Code subagent JSONL session logs to Markdown summary — tool call table, task prompt, final response. Optionally includes dispatch context from the main session via `--dispatch`.
**Reads:** Claude Code session JSONL files.
**Writes:** Markdown file via `--output` flag.
**Called by:** `src/pipeline/list_agents.py`, `src/pipeline/extract_calls.py` (both import from it). No external caller.
**Calls out:** stdlib json, argparse, pathlib.

---

### list_agents.py (189 LOC)

**Purpose:** Lists subagent sessions for a project with agent type, timestamp, and size. Resolves agent type from main session (sync and async dispatch patterns).
**Reads:** `~/.claude/projects/<encoded_path>/*.jsonl` directory.
**Writes:** stdout (aligned table).
**Called by:** No active external caller.
**Calls out:** `jsonl_to_md` (JSONL parsing and session derivation).

---

### extract_calls.py (56 LOC)

**Purpose:** Extracts specific tool calls by number from a session JSONL. Supports listing all calls or extracting full input/output for selected calls.
**Reads:** Session JSONL path.
**Writes:** stdout or Markdown via `--output` flag.
**Called by:** No active external caller.
**Calls out:** `jsonl_to_md` (JSONL parsing and formatting).

---

## Usage

```bash
python3 -m src.pipeline.jsonl_to_md --input <path> --output <path> [--dispatch]
python3 -m src.pipeline.list_agents --project <path> [--session latest]
python3 -m src.pipeline.extract_calls --input <path> --calls 1,3 [--output <path>]
```

## Gotchas

- `jsonl_to_md.py` at 437 LOC is a refactor candidate (>300 LOC threshold). Extract helpers: tool call row formatting and truncation logic belong in a separate module.
- No active external callers — these modules were invoked via the eval-agent skill which has been removed. Re-wire via a new skill or command if eval workflows are reactivated.
