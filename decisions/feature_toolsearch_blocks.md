# Feature: ToolSearch Block Types in Parser & Display

**Effort:** S (silence warnings) / M (full display)
**Value:** high
**Sources:** sources/ToolSearch1.md, sources/ToolSearch2.md, sources/ToolSearch3.md

## What

Add ToolSearch block types to `KNOWN_MESSAGE_TYPES` to stop warnings pane noise (S — immediate fix), then implement display of ToolSearch events in the main pane and Token Pane (M — full feature). This affects live sessions with the iterative-dev plugin today.

*See also: `feature_toolsearch_deferred.md` for cache preservation context.*

## Why

The iterative-dev plugin uses ToolSearch in production. Every session that calls `bead_list`, `activate_plugin`, or other tools that are deferred produces:
- `server_tool_use` blocks (for tool search invocations)
- `tool_search_tool_result` blocks (with discovered tools)
- `tool_reference` blocks (the referenced tool definitions)

All of these are currently unrecognized by `jsonl_parser.py` → warnings pane noise on every iterative-dev session. This is the most persistent current bug for users of Monitor_CC with iterative-dev.

Additionally, `usage.server_tool_use.tool_search_requests` is not extracted → invisible in Token Pane. This counter is the only way to see how many times CC had to "search" for tools in a given request.

## How — Implementation Plan

### Phase 1: Silence warnings (S — do this immediately)

1. **`src/constants.py`** — Add to `KNOWN_MESSAGE_TYPES` or `KNOWN_IGNORED_TYPES`:
   - `"tool_search_tool_result"` 
   - `"tool_reference"`
   - Verify `"server_tool_use"` is already present (used for web_search etc.)
   - Verify `"web_search_tool_result"` is already present

### Phase 2: Display (M — full feature)

2. **`src/jsonl_extractors.py`** — Detect `server_tool_use` blocks where `name` contains `tool_search_tool`. Extract:
   - `input.query` → search query string
   - Paired `tool_search_tool_result` block (same turn, adjacent) → `tool_references[*].tool_name` → list of discovered tool names

3. **`src/jsonl_extractors.py`** — Extract `usage.server_tool_use.get("tool_search_requests", 0)` per request.

4. **`src/formatter.py`** / **`src/formatter_events.py`** — In the main pane event rendering, for `server_tool_use` blocks where the tool is a tool_search tool, render:
   ```
   🔍 TOOL SEARCH (bm25) "activate plugin" → bead_list, activate_plugin, bead_create
   ```
   - Tool search variant (regex vs bm25) from the block's `name` field
   - Query from `input.query`
   - Discovered tools from the paired `tool_search_tool_result`
   
   Color: use `COLOR_SERVER_TOOL` or `COLOR_TOOLSEARCH` (dim blue).

5. **`src/token_format.py`** — If `tool_search_requests > 0`, show compact indicator in Token Pane per request: `🔍 2` (after existing server tool indicators, if any).

6. **`src/constants.py`** — Add `COLOR_TOOLSEARCH` (e.g. `\033[38;5;33m` — blue) if not already present.

7. **`src/DOCS.md`** — Update `jsonl_extractors.py` entry to document ToolSearch event extraction and `tool_search_requests` field.

## Risk / Edge Cases

- **Pairing `server_tool_use` with `tool_search_tool_result`:** The result block immediately follows the `server_tool_use` block in the same content array. Must be robust to other intervening blocks or missing result blocks.
- **`tool_reference` expansion:** The API auto-expands `tool_reference` blocks into full tool definitions. In the session JSONL, what actually appears may be the expanded tool definition rather than the raw `tool_reference` block. Need to verify with actual session JSONL from iterative-dev plugin. If already expanded: the `tool_reference` type may never appear in JSONL, only in proxy raw_payload.
- **`server_tool_use` naming:** Tool search is invoked as `tool_search_tool_regex` or `tool_search_tool_bm25`. Distinguish from other server tools (`web_search`, `code_execution`) by name prefix `"tool_search_tool"`.
- **Deferred tool counts:** `raw_payload.tools` shows all tools including deferred ones. `sent_meta.sent_tools_count` shows only the non-deferred tools in the prefix. The Metadata Pane should eventually show both counts — but that's scope for a separate feature.
- **No proxy changes needed** — all data comes from session JSONL (Phase 1 & 2) and existing proxy raw_payload (future metadata display).

## Verification

### Phase 1 (silence):
1. Start monitor on a project using iterative-dev plugin.
2. Run any CC session that triggers tool search.
3. `tmux capture-pane -t monitor_cc_global:3.0 -p | grep -c "unknown"` → 0 for tool_search types.

### Phase 2 (display):
4. Screenshot main pane during a session where ToolSearch fires.
5. Verify: `🔍 TOOL SEARCH (bm25) "bead_list" → bead_list, bead_create, bead_close` visible in main pane.
6. Verify Token Pane shows `🔍 N` indicator on requests with tool searches.
7. Grep session JSONL to find actual tool search events:
   ```bash
   jq 'select(.content[]?.type == "server_tool_use" and (.content[]?.name | test("tool_search")))' ~/.claude/projects/*/*.jsonl | head -5
   ```
