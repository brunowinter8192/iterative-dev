# src/pipeline/

Session JSONL analysis utilities. Used for eval workflows and subagent debugging.

## jsonl_to_md.py

**Purpose:** Converts Claude Code subagent JSONL session logs to Markdown summary (tool call table + task prompt + final response). Optionally includes dispatch context from main session.
**Input:** JSONL file path, output path, optional `--dispatch` flag.
**Output:** Markdown file with tool call summary (one line per call: timestamp, tool, params, output size or error marker). Error detection: tool_use_error results marked as `[✗ error text]`. Input params truncated to 100 chars in summary.

## list_agents.py

**Purpose:** Lists subagent sessions for a project with agent type, timestamp, and size. Resolves agent type from main session (sync and async dispatch patterns).
**Input:** Project path, optional `--session latest` filter.
**Output:** Aligned table of subagent sessions.

## extract_calls.py

**Purpose:** Extracts specific tool calls by number from a session JSONL. Supports listing all calls or extracting full input/output for selected calls.
**Input:** JSONL path, `--calls 1,3,7` or `--list` mode.
**Output:** Full tool call details (input + output) as Markdown, or summary table.

## Usage

```bash
python3 -m src.pipeline.jsonl_to_md --input <path> --output <path> [--dispatch]
python3 -m src.pipeline.list_agents --project <path> [--session latest]
python3 -m src.pipeline.extract_calls --input <path> --calls 1,3 [--output <path>]
```

## Dependencies

list_agents.py and extract_calls.py import from jsonl_to_md.py (JSONL parsing, session derivation, formatting). Breaking changes in jsonl_to_md affect both.
