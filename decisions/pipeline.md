# Session Pipeline

## Status Quo (IST)

Utilities for analyzing Claude Code session JSONL logs. Used by the eval workflow (RAG plugin) and for debugging subagent behavior.

**jsonl_to_md.py (JSONL to Markdown):**
- Loads JSONL session file, extracts task prompt (first user message) and final response (last assistant text)
- Extracts all tool_use/tool_result pairs with timestamps
- Strips `<system-reminder>` tags from all content
- Outputs summary markdown: tool call table (one line per call with timestamp, tool name, params, output size or error marker)
- Error detection: `is_tool_error()` checks `is_error` flag, `<tool_use_error>` tags, and "No such tool available" in tool_result content. Failed calls marked as `[✗ error text]` in summary. Audit over 40364 tool_results (1442 sessions) confirmed: all hard errors have `is_error=True` — string patterns are redundant safety net. Evidence: `dev/pipeline/reports/error_patterns_20260321_203616.md`
- Suspicious output detection: MCP tool calls (name starts with `mcp__`) with output < 500 chars marked `[suspicious: N chars]` in summary. Flags calls that returned "successfully" but with error content (404, "No content extracted", broken HTML). Built-in tools (Bash, Read, Grep) excluded — short output is normal for them. Not an error classification — signal for eval reviewer to extract and verify content. Evidence: `dev/pipeline/reports/error_patterns_20260321_203616.md`
- Input truncation: `format_input_params()` truncates values to 100 chars, replaces newlines with spaces (single-line guarantee). File-content params (`content`, `file_content`, `new_string`, bash heredoc) show `[N chars]` instead of content.
- Optional `--dispatch` flag: traces back to main session, extracts dispatch context (pre-dispatch messages, Agent tool_use prompt, post-dispatch response)
- Dispatch context derivation: finds `progress` message with matching agentId, walks backwards to find Agent tool_use block

**list_agents.py (Subagent Listing):**
- Scans `~/.claude/projects/<escaped-path>/*/subagents/agent-*.jsonl`
- For each subagent: extracts agent_type from main session (sync via progress anchor, async via tool_result text matching)
- Graceful per-agent error handling: agents with parse errors (RuntimeError, FileNotFoundError) are included as `UNKNOWN (parse error)` instead of crashing the entire listing
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

**MCP Wrappers (server.py):**
- `eval_list_agents(project_path, session?)`: wraps `list_agents_workflow()` + `format_table()`. Returns formatted agent table + JSONL paths.
- `eval_extract(jsonl_path, calls?)`: without `calls` wraps `convert_workflow()` with dispatch=True (returns summary content directly). With `calls` wraps `extract_workflow()` (returns extracted tool calls).

**Cross-Plugin:** jsonl_to_md is used by RAG plugin's eval workflow for converting subagent sessions to readable markdown.

**Files:** `src/pipeline/jsonl_to_md.py`, `src/pipeline/list_agents.py`, `src/pipeline/extract_calls.py`

## Recommendation (SOLL)

- `is_tool_error()`: Keep (no change needed). Hard errors fully covered by `is_error` flag. MCP soft errors handled via suspicious marker + eval review — programmatic classification not feasible for content-based errors.
- `format_summary_table()`: Keep current `[suspicious: N chars]` threshold at 500 chars. Consistent with eval-agent skill (MCP Content Volume Check).
- `format_input_params()`: Keep current content detection + newline sanitization.

## Offene Fragen

- jsonl_to_md is the shared dependency — list_agents and extract_calls both import from it. Breaking change in jsonl_to_md affects both.
- CC session JSONL format is undocumented — structure derived by reverse-engineering. Format changes in CC updates could break parsing.
