# Session Pipeline

## Status Quo (IST)

Utilities for analyzing Claude Code session JSONL logs. Used by the eval workflow (RAG plugin) and for debugging subagent behavior.

**jsonl_to_md.py (JSONL to Markdown):**
- Loads JSONL session file, extracts task prompt (first user message) and final response (last assistant text)
- Extracts all tool_use/tool_result pairs with timestamps
- Strips `<system-reminder>` tags from all content
- Outputs summary markdown: tool call table (one line per call with timestamp, tool name, params, output size or error marker)
- Error detection: `is_tool_error()` checks for `<tool_use_error>` tags and "No such tool available" in tool_result content. Failed calls marked as `[✗ error text]` in summary instead of `[X chars]`
- Input truncation: `format_input_params()` truncates values to 100 chars in summary table (prevents Write-calls with full file content from flooding the summary)
- Optional `--dispatch` flag: traces back to main session, extracts dispatch context (pre-dispatch messages, Agent tool_use prompt, post-dispatch response)
- Dispatch context derivation: finds `progress` message with matching agentId, walks backwards to find Agent tool_use block

**list_agents.py (Subagent Listing):**
- Scans `~/.claude/projects/<escaped-path>/*/subagents/agent-*.jsonl`
- For each subagent: extracts agent_type from main session (sync via progress anchor, async via tool_result text matching)
- Outputs aligned table: agent_id, agent_type, timestamp, size
- `--session latest` filter for most recent session only
- Imports from jsonl_to_md: `load_jsonl`, `derive_main_session`, `find_task_anchor`

**extract_calls.py (Tool Call Extraction):**
- Extracts specific tool calls by number from a session JSONL
- `--list` mode: prints summary table of all calls
- `--calls 1,3,7` mode: extracts full input/output for selected calls
- Imports from jsonl_to_md: `load_jsonl`, `extract_tool_calls`, `format_tool_call`, `write_output`, `format_summary_table`

**Usage:**
- `python3 -m src.pipeline.jsonl_to_md --input <path> --output <path> [--dispatch]`
- `python3 -m src.pipeline.list_agents --project <path> [--session latest]`
- `python3 -m src.pipeline.extract_calls --input <path> --calls 1,3 [--output <path>]`

**Cross-Plugin:** jsonl_to_md is used by RAG plugin's eval workflow for converting subagent sessions to readable markdown.

**Files:** `src/pipeline/jsonl_to_md.py`, `src/pipeline/list_agents.py`, `src/pipeline/extract_calls.py`

## Recommendation (SOLL)

Pending — needs evaluation.

## Offene Fragen

- jsonl_to_md is the shared dependency — list_agents and extract_calls both import from it. Breaking change in jsonl_to_md affects both.
- CC session JSONL format is undocumented — structure derived by reverse-engineering. Format changes in CC updates could break parsing.
