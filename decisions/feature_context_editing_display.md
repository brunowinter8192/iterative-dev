# Feature: Context Editing Response Display in Token Pane

**Effort:** S
**Value:** medium
**Sources:** sources/ContextEditing1.md, sources/ContextEditing3.md

## What

Parse the `context_management.applied_edits` field from session JSONL responses and display an annotation in the Token Pane when server-side context editing fires — showing what was cleared and how many tokens were saved.

*See also: `feature_context_editing.md` for the full API behavior context.*

## Why

Context editing is applied server-side — CC never sees the cleared content, and the Monitor never sees a diff. Without parsing `context_management`, a `clear_tool_uses` event manifests in the Token Pane as:
- A sudden drop in `D` (input_tokens) and/or `CC` — unexplained
- Possibly a high CC spike (cache invalidated by tool result clearing)

From ContextEditing3.md, the response includes:
```json
"context_management": {
  "applied_edits": [
    {"type": "clear_tool_uses_20250919", "cleared_tool_uses": 8, "cleared_input_tokens": 50000}
  ]
}
```

This data is present in the session JSONL response — it just needs to be extracted.

## How — Implementation Plan

1. **`src/jsonl_extractors.py`** — In `extract_usage()` or a new `extract_context_management()` function, check `response_obj.get("context_management", {}).get("applied_edits", [])`. For each edit, extract:
   - `edit["type"]` → strategy name (shorten: `"clear_tool_uses_20250919"` → `"tool_results"`, `"clear_thinking_20251015"` → `"thinking"`)
   - `edit.get("cleared_tool_uses", 0)` → count
   - `edit.get("cleared_thinking_turns", 0)` → count
   - `edit.get("cleared_input_tokens", 0)` → tokens cleared
   Return as `context_edits: list[dict]`.

2. **`src/token_pane.py`** — Pass `context_edits` through to the viewport data structure for each request entry.

3. **`src/token_format.py`** — In request row rendering, if `context_edits` is non-empty, append annotation line(s) below the token bar:
   ```
   ✂ 8 tool results cleared (50k tokens)
   ✂ 3 thinking turns cleared (15k tokens)
   ```
   Use dim gray color (`\033[38;5;244m`) to keep it unobtrusive.

4. **`src/constants.py`** — No new constants needed (use existing dim color or add `COLOR_CONTEXT_EDIT = \033[38;5;244m`).

5. **`decisions/cache_rebuild_cases.md`** — Add new case: "`clear_tool_uses` fired → cache invalidated at cleared position → high CC on next request. Visible in Token Pane as ✂ annotation followed by high CC."

## Risk / Edge Cases

- **`context_management` field absence (all normal requests).** Must not crash. Use `.get()` with empty dict fallback at every level.
- **Cache spike correlation.** `clear_tool_uses` invalidates the cache. The same request may show: annotation `✂ 8 tool results cleared (50k)` AND high `CC` in the token bar. The combination tells the full story. Document this in the Token Pane DOCS.
- **`clear_thinking_20251015` preserves cache** when thinking blocks are kept. If `cleared_thinking_turns == 0` (nothing actually cleared), the annotation should not appear even if the strategy is listed in `applied_edits`.
- **Multiple strategies.** Both strategies can fire in the same request. The annotation should list both, one line each.
- **Streaming.** `context_management` appears in the final `message_delta` event for streaming responses. Session JSONL deduplication captures the final assembled message including this field.

## Verification

1. Craft test JSONL entry with `context_management.applied_edits`:
   ```json
   {"context_management": {"applied_edits": [{"type": "clear_tool_uses_20250919", "cleared_tool_uses": 8, "cleared_input_tokens": 50000}]}}
   ```
2. Inject into monitored session file.
3. Screenshot Token Pane: verify `✂ 8 tool results cleared (50k tokens)` annotation visible.
4. Verify normal requests (without `context_management`) show no annotation.
5. Test both strategies in same request — verify two annotation lines.
