# Feature: Server Tool Usage Counters in Token Pane

**Effort:** S
**Value:** medium
**Sources:** sources/ToolSearch3.md, sources/Tools6.md, sources/Streaming_Messages5.md

## What

Extract `usage.server_tool_use` from session JSONL responses and display server-side tool usage counts in the Token Pane per request. Three counters: `web_search_requests`, `code_execution_requests`, `tool_search_requests`.

## Why

Server-side tools have their own pricing beyond input/output tokens — web search charges per query, code execution per run. Currently these costs are invisible in Monitor_CC's Token Pane. A session with 10 web searches shows the same token display as a session with 0 — even though the web searches cost extra.

From Streaming_Messages5.md, a web search response includes:
```json
"usage": {
  "input_tokens": 10682,
  "output_tokens": 510,
  "server_tool_use": {"web_search_requests": 1}
}
```

From Tools6.md, code execution:
```json
"usage": {
  "server_tool_use": {"code_execution_requests": 1}
}
```

From ToolSearch3.md, tool search:
```json
"usage": {
  "server_tool_use": {"tool_search_requests": 2}
}
```

All three are in the same `usage.server_tool_use` object — one extraction handles all of them.

## How — Implementation Plan

1. **`src/jsonl_extractors.py`** — In `extract_usage()`, add extraction of `server_tool_use`:
   ```python
   server_tool_use = usage.get("server_tool_use", {})
   web_searches = server_tool_use.get("web_search_requests", 0)
   code_execs = server_tool_use.get("code_execution_requests", 0)
   tool_searches = server_tool_use.get("tool_search_requests", 0)
   ```
   Return these as additional fields on the per-request usage dict.

2. **`src/token_format.py`** — In the request row rendering, after the CR/CC/D/Out token bar, add a compact server tool indicator line if any counter > 0:
   ```
   🌐 3 searches  ⚡ 1 code_exec  🔍 2 tool_searches
   ```
   Only show non-zero counters. Use short icons to keep it compact.

3. **`src/constants.py`** — Add icon constants or inline them in `token_format.py`. No new color constants needed unless specific colors are desired.

4. **`src/token_pane.py`** — Pass the new server tool usage fields through to the rendering pipeline (add to the per-request data structure that feeds `token_format.py`).

5. **`src/DOCS.md`** — Update `jsonl_extractors.py` entry to document `web_searches`, `code_execs`, `tool_searches` fields.

## Risk / Edge Cases

- **`server_tool_use` object absent (most requests).** The vast majority of CC requests use only client-side tools (bash, text_editor, Grep, etc.). `server_tool_use` is absent from `usage` in those cases. Code uses `.get()` with 0 defaults — no crash.
- **Future new server tool types.** If Anthropic adds new server tools (e.g. `memory_requests`), they would appear in `server_tool_use` with a new key. The display would silently ignore them. Periodically audit new server tool types to update the extraction.
- **Counter semantics.** `code_execution_requests` counts individual container runs, not requests to the messages API. A single messages API call may trigger multiple code executions. The count can be > 1 per request.
- **Tool search counter overlap.** `tool_search_requests` is also extracted in `feature_toolsearch_blocks.md`. Ensure these two features use the same extraction point — don't extract the same field twice from different places.
- **Web search cost.** The actual cost of web searches is not in the session JSONL (it depends on CC's API plan). Monitor_CC can show the count but not the dollar cost.

## Verification

1. Run a CC session that triggers a web search (ask Claude about a current event).
2. Screenshot Token Pane.
3. Verify: `🌐 1 searches` appears on the request that triggered the web search.
4. Check that requests without server tools show no indicator (no `🌐 0`).
5. Test with tool search: run an iterative-dev session, verify `🔍 N tool_searches` appears.
6. Grep for sessions with web searches: `jq 'select(.usage.server_tool_use.web_search_requests > 0)' ~/.claude/projects/*/*.jsonl | jq '{req: .id, searches: .usage.server_tool_use.web_search_requests}' | head -5`.
