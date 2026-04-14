# Feature: Server-side Context Editing Response Parsing

**Effort:** S
**Value:** medium
**Sources:** sources/ContextEditing1.md, sources/ContextEditing2.md, sources/ContextEditing3.md, sources/ContextEditing4.md, sources/ContextEditing5.md

## What

When Claude Code enables the `context-management-2025-06-27` beta header, the API's response object may include a `context_management.applied_edits` field listing what was automatically cleared (tool results, thinking blocks, token counts). Monitor_CC should parse this field from session JSONL and annotate the affected request in the Token Pane: "✂ CONTEXT EDIT: cleared 8 tool results (50k tokens)".

## Why

Context editing clears content server-side before the prompt reaches Claude — the client (CC) never sees the cleared content. From Monitor_CC's perspective, this manifests as an unexplained drop in `cache_creation_input_tokens` or `input_tokens` between requests. Without parsing `context_management`, there is no way to explain this drop to the user.

The two strategies:
- `clear_tool_uses_20250919`: clears old tool results, **invalidates cache** (CC would show a spike in CC tokens)
- `clear_thinking_20251015`: clears thinking blocks, **preserves cache** if blocks are kept

CC doesn't enable this today, but as sessions grow longer (1M context window on Opus/Sonnet 4.6), this becomes an increasingly likely strategy for CC itself or for workers.

## How — Implementation Plan

1. **`src/jsonl_extractors.py`** — In the function that extracts usage/metadata from a session JSONL entry, check for `context_management.applied_edits` in the response object. If present, extract:
   - Per edit: `type` (strategy name), `cleared_tool_uses`, `cleared_thinking_turns`, `cleared_input_tokens`
   - Return as a list of dicts alongside the normal usage extraction.

2. **`src/jsonl_parser.py`** — Pass the extracted `context_management` list through to the token pane data structure. Add a `context_edits` field to whatever named tuple / dict is used to represent a parsed request.

3. **`src/token_format.py`** — In the request row rendering, check if `context_edits` is non-empty. If so, append an annotation line below the token bar:
   ```
   ✂ clear_tool_uses: 8 tool results, 50k tokens cleared
   ```
   Use a distinct dim color (e.g. `\033[38;5;244m` — gray) to avoid competing with the main token bars.

4. **`src/constants.py`** — Add `COLOR_CONTEXT_EDIT` constant for the annotation color.

5. **No proxy changes needed** — this is session JSONL response parsing only.

## Risk / Edge Cases

- **Field absence:** `context_management` only appears in the response when edits were applied. Code must tolerate its absence without error. Check `response.get("context_management", {}).get("applied_edits", [])`.
- **Tool result clearing + cache spike:** If `clear_tool_uses` fires, the Proxy Pane will show high CC on the same request. The annotation in Token Pane would explain WHY. Document this correlation in `decisions/cache_rebuild_cases.md` as a new case.
- **Streaming responses:** For streaming, `context_management` appears in the final `message_delta` event. The session JSONL deduplication already captures the final assembled message, so it should be present correctly.
- **Multiple strategies combined:** `clear_thinking_20251015` must be listed before `clear_tool_uses_20250919` in the API. Both can appear in `applied_edits`. Render both annotations.

## Verification

1. Craft a test JSONL entry with `context_management.applied_edits`:
   ```json
   {"context_management": {"applied_edits": [{"type": "clear_tool_uses_20250919", "cleared_tool_uses": 8, "cleared_input_tokens": 50000}]}}
   ```
2. Inject into a test session file the monitor is watching.
3. Screenshot Token Pane: `./venv/bin/python dev/display/screenshot_panes.py`
4. Verify: annotation line visible below the request row in Token Pane.
5. Verify no crash when `context_management` is absent (normal requests): existing session should render identically.
