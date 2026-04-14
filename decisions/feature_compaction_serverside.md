# Feature: Server-side Compaction Detection & Display

**Effort:** M
**Value:** high
**Sources:** sources/Compaction1.md, sources/Compaction2.md, sources/Compaction3.md, sources/Compaction4.md

## What

When Claude Code enables the `compact_20260112` beta header, the API may return a `compaction` content block mid-session containing a summary of the conversation. Monitor_CC should detect this event in the session JSONL, display it prominently in the Token Pane as a special row (showing tokens before/after + summary preview), and parse the `usage.iterations` array to accurately attribute token costs across compaction vs message iterations.

## Why

Compaction is GA on Opus 4.6 and Sonnet 4.6 (beta header `compact-2026-01-12`). If CC ever enables it — which is increasingly likely for long sessions — Monitor_CC currently has no handling for it:
- `compaction` block type is unknown → warnings pane noise
- `usage.iterations` not parsed → top-level `input_tokens`/`output_tokens` UNDERCOUNTS actual cost (per the API: "top-level input_tokens and output_tokens do not include compaction iteration usage")
- Token Pane shows no indication that context was summarized → silent discontinuity in token history

This is a silent data-integrity issue, not just cosmetic.

## How — Implementation Plan

1. **`src/constants.py`** — Add `"compaction"` to `KNOWN_MESSAGE_TYPES`. Add `"compaction"` to `KNOWN_IGNORED_TYPES` as a fallback so it doesn't pollute warnings pane while display is not yet implemented.

2. **`src/jsonl_extractors.py`** — In `extract_usage()` (or wherever usage tokens are extracted from session JSONL), detect the presence of `usage.iterations` in the response object. If present, compute correct totals by summing all entries in `iterations` (both `type: "compaction"` and `type: "message"`). Extract `compaction_input_tokens` and `compaction_output_tokens` separately for display. The top-level `usage.input_tokens` is NOT sufficient when compaction fires.

3. **`src/jsonl_extractors.py`** — In content block extraction, detect `type: "compaction"` blocks. Extract: `content` field (summary text), `stop_reason: "compaction"` from the message. Return these as a new `CompactionEvent` named tuple or dict alongside the normal usage extraction.

4. **`src/token_pane.py` / `src/token_format.py`** — In `run_tokens_loop()`, after processing each session JSONL request, check if a compaction event was detected. If so, render a special row between the request rows:
   ```
   ━━━ COMPACTION ━━━ before: 180k → after: 23k (saved: 157k) ━━━
   Summary: "The user requested help building a web scraper..."
   ```
   Use a distinct color (blue/cyan from `constants.py`) to distinguish from normal request rows.

5. **`src/constants.py`** — Add color constant `COLOR_COMPACTION` (pastel blue, e.g. `\033[38;5;75m`) for compaction row styling.

6. **`src/jsonl_parser.py`** — Ensure `KNOWN_MESSAGE_TYPES` check passes for `compaction` type blocks without raising unknown-type warnings.

7. **`src/DOCS.md`** — Update `jsonl_extractors.py` entry to document `CompactionEvent` extraction and `usage.iterations` handling.

## Risk / Edge Cases

- **`usage.iterations` only present when compaction triggers in that request.** When re-using a previous compaction block (pass-through), the API docs say "top-level usage fields remain accurate." Extract `iterations` only when key exists; fall back to top-level `usage` otherwise.
- **Multiple compactions in one session** — `usage.iterations` can have multiple compaction entries if the context grows again. Sum all of them.
- **Streaming + compaction** — The compaction block streams differently: `content_block_start` → single `content_block_delta` with complete summary → `content_block_stop`. The session JSONL already deduplicates streaming chunks, so the final assembled message should contain the full compaction block.
- **`pause_after_compaction`** — If enabled, `stop_reason: "compaction"` appears before the actual response. The next request contains the continuation. Token Pane should show `stop_reason: compaction` on that row (see `feature_stop_reason_display.md`).
- **No proxy impact** — This is session JSONL parsing only. The proxy live-copy is not affected.

## Verification

1. Enable compaction in a test CC session (or craft a test JSONL file with a `compaction` block and `usage.iterations`):
   ```json
   {"type": "assistant", "content": [{"type": "compaction", "content": "Summary text..."}], "usage": {"iterations": [{"type": "compaction", "input_tokens": 180000, "output_tokens": 3500}, {"type": "message", "input_tokens": 23000, "output_tokens": 1000}]}}
   ```
2. Start monitor: `python3 workflow.py --project <project>`
3. Screenshot Token Pane: `./venv/bin/python dev/display/screenshot_panes.py`
4. Verify: compaction row visible in Token Pane with correct before/after token counts, no warnings in warnings pane for `compaction` block type.
5. Grep warnings pane output: `tmux capture-pane -t monitor_cc_global:3.0 -p | grep -i "unknown"` → should be empty for compaction-related entries.
