# Feature: Citations Block Display

**Effort:** M
**Value:** low
**Sources:** sources/Citations1.md, sources/Citations2.md, sources/Citations3.md

## What

Parse and display citation blocks that appear in API responses when `citations.enabled: true` is set on document content. Response text blocks with citations contain a `citations` array with document references (char location, page number, or content block index). Display citation count in Token Pane and citation detail in main pane.

## Why

The value is low because CC does not currently use the citations API directly. CC's own responses are text-only without citations. The citations feature is relevant when CC sends document content with `citations.enabled: true` — which would require CC to explicitly send document blocks with the citations flag.

If CC (or an MCP plugin) ever enables citations, Monitor_CC would:
- Not recognize the changed response structure (text blocks now have `citations` arrays)
- Show the citation arrays as unknown structure in the formatter

From Citations1.md: "cited_text does not count towards your output tokens" and "When passed back in subsequent conversation turns, cited_text is also not counted towards input tokens." This is a token counting edge case — the session JSONL `output_tokens` may undercount actual text generated if citations are active, since cited text is excluded.

## How — Implementation Plan

1. **`src/constants.py`** — Add `"citations_delta"` to `KNOWN_MESSAGE_TYPES` (streaming event type for citations). Verify `"document"` content block type is already present.

2. **`src/formatter_events.py`** — In text block rendering, check `content_block.get("citations")`. If non-empty, append citation summary:
   ```
   "the grass is green" [1: chars 0-20]
   "the sky is blue" [1: chars 20-36]
   ```
   Or compact form: `(2 citations from "My Document")` if the full list is too verbose.

3. **`src/token_format.py`** — When a response contains citation blocks, annotate in Token Pane: "(cited_text excluded from token count)". This warns the user that `output_tokens` is slightly lower than the actual text content.

4. **`src/jsonl_extractors.py`** — When extracting content blocks, recognize `citations` arrays on text blocks. Count total citations per response for Token Pane summary.

5. **No proxy changes.** Citation blocks appear in session JSONL responses, not requests.

## Risk / Edge Cases

- **Three citation types:** `char_location` (plain text docs), `page_location` (PDFs), `content_block_location` (custom content docs). The formatter must handle all three display formats without crashing on unknown citation type.
- **`cited_text` token accounting.** `cited_text` is excluded from output_tokens billing. Monitor_CC cannot easily compute how many tokens this represents without re-encoding the cited text. A simple note "(cited_text excluded)" is sufficient — don't attempt to calculate the correction.
- **Citations + Structured Outputs incompatibility.** From Citations1.md: "Citations and Structured Outputs are incompatible." If a request has both `citations.enabled` on a document AND `output_config.format`, the API returns a 400 error. The Warnings Pane could flag this combination when it sees the error payload in `src/logs/api_error_payload_*.json`.
- **Performance.** Citations responses have more content blocks (each claim gets its own text block + citations array). A heavily-cited response could have 50+ text blocks. Formatter must not generate excessive output lines.

## Verification

1. Craft a test JSONL entry with citation blocks:
   ```json
   {"content": [{"type": "text", "text": "the grass is green", "citations": [{"type": "char_location", "cited_text": "The grass is green.", "document_index": 0, "document_title": "My Doc", "start_char_index": 0, "end_char_index": 20}]}]}
   ```
2. Inject into monitored session.
3. Screenshot main pane: verify citation summary visible (compact or full).
4. Verify `citations_delta` streaming type doesn't trigger warnings pane.
5. Verify Token Pane annotation appears when citations are present.
