# Feature: Search Results Block Type Recognition

**Effort:** S (silence) / M (full display)
**Value:** medium
**Sources:** sources/Search_results1.md, sources/Search_results2.md

## What

Add `search_result` to `KNOWN_MESSAGE_TYPES` in `constants.py` to stop unknown-type warnings. Optionally display search result blocks in the main pane with source URL, title, and content preview.

## Why

From Search_results1.md: "Search result content blocks enable natural citations with proper source attribution, bringing web search-quality citations to your custom applications. This feature is particularly powerful for RAG applications."

The iterative-dev plugin (or CC itself when using web search tools) may produce `search_result` blocks in user messages or as tool results. These blocks use a `type: "search_result"` content block that is currently unrecognized by Monitor_CC's `KNOWN_MESSAGE_TYPES` → warnings pane noise.

The `search_result` block schema:
```json
{
  "type": "search_result",
  "source": "https://example.com/article",
  "title": "Article Title",
  "content": [{"type": "text", "text": "..."}],
  "citations": {"enabled": true}
}
```

## How — Implementation Plan

### Phase 1: Silence (S — immediate)

1. **`src/constants.py`** — Add `"search_result"` to `KNOWN_IGNORED_TYPES` (if display is deferred) or `KNOWN_MESSAGE_TYPES` (if display is implemented simultaneously).

### Phase 2: Display (M)

2. **`src/formatter_events.py`** — Add a handler for `search_result` content blocks in user message content. When encountered, render:
   ```
   🔗 SEARCH RESULT: "Article Title" (example.com)
      "To configure the product, navigate to Settings..."
   ```
   Show source domain only (not full URL). Truncate content to 80 chars.

3. **`src/formatter_events.py`** — When a tool result contains `search_result` blocks (i.e., a tool returns search results), show in the tool result display:
   ```
   [tool_result: search_kb] → 2 results
     🔗 "Product Configuration Guide" (docs.company.com)
     🔗 "Troubleshooting Guide" (docs.company.com)
   ```

4. **`src/token_format.py`** — Optionally count search results per request: "🔗 2 results" in Token Pane, analogous to the ToolSearch indicator.

5. **`src/DOCS.md`** — Update `formatter_events.py` entry to document `search_result` handling.

## Risk / Edge Cases

- **`citations` field on `search_result` blocks.** The `citations.enabled` field controls whether Claude cites from these results. This is not relevant to Monitor_CC display — just show the result regardless.
- **Search results in tool results vs. top-level user messages.** From Search_results1.md: "Search results can be provided in two ways: From tool calls — as tool result content; As top-level content — directly in user messages." Handle both locations in `formatter_events.py`.
- **Large result sets.** If a tool returns 20 search results, the display would be very long. Apply the same `LONG_OUTPUT_THRESHOLD` truncation used elsewhere — show first N results with "... +N more" indicator.
- **`content` array in search result.** The content is an array of text blocks (not a single string). Join them when displaying the preview.
- **Web search tool results vs. custom search results.** `web_search_tool_result` (server-side web search) and custom `search_result` blocks are different types. Don't conflate them. Web search results have their own existing display (if implemented); custom `search_result` blocks need this new handler.

## Verification

1. Find a CC session that uses a search tool returning `search_result` blocks.
2. Screenshot main pane — verify search results display with title and source domain.
3. Grep session JSONL: `jq '.. | objects | select(.type == "search_result") | {source, title}' ~/.claude/projects/*/*.jsonl | head -5` — find existing search_result blocks.
4. Verify warnings pane: `tmux capture-pane -t monitor_cc_global:3.0 -p | grep "search_result"` → no unknown-type warnings.
