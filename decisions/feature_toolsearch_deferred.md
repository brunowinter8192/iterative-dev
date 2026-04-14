# Feature: ToolSearch Deferred Loading — Cache & Display Awareness

**Effort:** S (display) / M (full)
**Value:** high
**Sources:** sources/ToolSearch1.md, sources/ToolSearch2.md, sources/ToolSearch3.md

## What

Tools marked `defer_loading: true` are excluded from the system-prompt prefix — they don't consume prefix tokens and don't invalidate the cache when added. When Claude discovers them via tool search, they appear inline as `tool_reference` blocks in the conversation without touching the prefix. Monitor_CC should: (a) stop warning about `tool_search_tool_result` and `tool_reference` block types, (b) display ToolSearch events in the main pane (query + discovered tools), and (c) show `tool_search_requests` count from `usage.server_tool_use` in the Token Pane.

## Why

The iterative-dev plugin already uses ToolSearch in production — it sends hundreds of deferred tool definitions and uses the `tool_search_tool_bm25_20251119` or `tool_search_tool_regex_20251119` tool to discover them on demand. This means:

- `tool_search_tool_result` blocks appear in live sessions TODAY and cause warnings pane noise on every session
- `tool_reference` blocks (expanded deferred tools) are not recognized
- `tool_search_requests` in `usage.server_tool_use` is not extracted

The key cache insight: deferred tools do NOT go into the system-prompt prefix. This is why adding new iterative-dev tools (via `activate_plugin`) doesn't always cause a full cache rebuild — the deferred tools are appended inline, not in the prefix. This distinction is currently invisible in Monitor_CC.

## How — Implementation Plan

1. **`src/constants.py`** — Add to `KNOWN_MESSAGE_TYPES` or `KNOWN_IGNORED_TYPES`:
   - `"tool_search_tool_result"` (server-side tool search result block)
   - `"tool_reference"` (reference to a deferred tool, auto-expanded by API)
   - `"server_tool_use"` (if not already present — used for tool search invocations)

2. **`src/jsonl_extractors.py`** — Extract `usage.server_tool_use.tool_search_requests` from session JSONL response. Return alongside existing token counts. If absent, default to 0.

3. **`src/token_format.py`** / **`src/token_pane.py`** — In the per-request row rendering, if `tool_search_requests > 0`, show a compact indicator:
   ```
   🔍 2 tool searches
   ```
   Append to the existing token line or as a sub-line. Use `COLOR_SERVER_TOOL` constant.

4. **`src/formatter.py`** / **`src/formatter_events.py`** — For `server_tool_use` blocks where `name` is `tool_search_tool_regex` or `tool_search_tool_bm25`, render a special event line:
   ```
   🔍 TOOL SEARCH query="weather" → found: get_weather, search_files
   ```
   Extract the query from `input.query` and the discovered tool names from the `tool_search_tool_result.content.tool_references[*].tool_name` array.

5. **`src/constants.py`** — Add `COLOR_SERVER_TOOL` (e.g. `\033[38;5;33m` — blue) if not already present.

6. **`src/DOCS.md`** — Update `jsonl_extractors.py` entry to document `tool_search_requests` extraction.

## Risk / Edge Cases

- **`tool_reference` auto-expansion:** The API automatically expands `tool_reference` blocks into full tool definitions before showing them to Claude. In the session JSONL, these may appear as full tool definitions in the conversation history. Need to verify whether `tool_reference` appears literally in the JSONL or only the expanded form.
- **`server_tool_use` naming conflicts:** `server_tool_use` is used for ALL server-side tool invocations (web_search, code_execution, tool_search). The ToolSearch display must filter specifically for tool_search tool names.
- **Cache implication:** Deferred tools appended as `tool_reference` do NOT invalidate the prefix. The Proxy Pane's `⚠ TOOLS CHANGED` warning may fire when new tools are discovered (because `tools_count` in `sent_meta` increases). This is expected behavior, not a bug — but the annotation should distinguish "new deferred tool loaded" from "prefix changed".
- **BM25 vs Regex:** Both variants use different query formats (natural language vs Python regex). The display should show the raw query string without trying to interpret the variant.

## Verification

1. Start monitor on a project that uses iterative-dev plugin (which has ToolSearch).
2. Run a CC session, trigger a task that causes ToolSearch to fire (e.g. call `bead_list`).
3. Screenshot main pane: `./venv/bin/python dev/display/screenshot_panes.py`
4. Verify: ToolSearch event visible in main pane with query and discovered tool names.
5. Grep warnings pane: `tmux capture-pane -t monitor_cc_global:3.0 -p | grep "unknown"` → no `tool_search_tool_result` or `tool_reference` entries.
6. In Token Pane: verify `🔍 N tool searches` appears on requests where ToolSearch fired.
