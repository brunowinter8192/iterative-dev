# Feature: Compaction Block Type in JSONL Parser

**Effort:** M
**Value:** high
**Sources:** sources/Compaction1.md, sources/Compaction2.md, sources/Compaction3.md

## What

Add `compaction` to `KNOWN_MESSAGE_TYPES` in `constants.py` and implement JSONL extraction for compaction blocks. Display compaction events in the Token Pane as a special row with before/after token counts and summary preview. Parse `usage.iterations` for accurate token attribution when compaction fires.

*See also: `feature_compaction_serverside.md` for the full context on why this matters (token accounting, cache behavior, stop_reason).*

## Why

If CC enables the `compact_20260112` beta header (GA on Opus 4.6/Sonnet 4.6), Monitor_CC has two concrete bugs today:

1. **Unknown block type warning:** `compaction` blocks in session JSONL are unrecognized → warnings pane noise on every compacted request.
2. **Incorrect token totals:** When compaction fires, `usage.input_tokens` at the top level of the response does NOT include the compaction iteration's token costs (per Compaction4.md: "top-level input_tokens and output_tokens do not include compaction iteration usage"). Token Pane would silently show understated totals.

Bug 2 is a data integrity issue — silence is worse than showing the wrong number.

## How — Implementation Plan

1. **`src/constants.py`** — Add `"compaction"` to `KNOWN_MESSAGE_TYPES`. This alone fixes the warnings pane noise immediately.

2. **`src/jsonl_extractors.py`** — In `extract_usage()`, check for `usage.get("iterations")`. If present:
   ```python
   total_in = sum(it["input_tokens"] for it in usage["iterations"])
   total_out = sum(it["output_tokens"] for it in usage["iterations"])
   compaction_in = sum(it["input_tokens"] for it in usage["iterations"] if it["type"] == "compaction")
   compaction_out = sum(it["output_tokens"] for it in usage["iterations"] if it["type"] == "compaction")
   ```
   Return `compaction_in`, `compaction_out` alongside normal usage fields. Use `total_in`/`total_out` as the authoritative token counts (not top-level `usage.input_tokens`).

3. **`src/jsonl_extractors.py`** — In content block extraction, detect `content[i]["type"] == "compaction"`. Extract:
   - `content[i]["content"]` → summary text
   Store as `compaction_summary` string (truncate to 120 chars for display).

4. **`src/token_pane.py`** — In `run_tokens_loop()`, after calling `accumulate_tokens()`, check if the current entry has `compaction_in > 0`. If so, insert a special separator row in the viewport above the regular token bar:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   📦 COMPACTION  before: 180k  →  after: 23k tokens
   "The user requested help building a web scraper..."
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

5. **`src/token_format.py`** — Add `format_compaction_row()` helper that renders the separator above. Use `COLOR_COMPACTION = \033[38;5;75m` (light blue).

6. **`src/constants.py`** — Add `COLOR_COMPACTION`.

7. **`src/DOCS.md`** — Update `jsonl_extractors.py` entry: document `compaction_summary`, `compaction_in`, `compaction_out` fields, and the `usage.iterations` fallback logic.

## Risk / Edge Cases

- **`usage.iterations` only present when new compaction triggered.** When a compaction block is passed back in subsequent requests (no new compaction), top-level `usage` is accurate and `iterations` is absent. Code must handle this: `if "iterations" in usage → use iterations; else → use top-level`.
- **Multiple compactions in one session.** The session JSONL may have multiple requests each triggering compaction. Each is independent. The `compaction_summary` shown should be from the most recent compaction block in that request's content.
- **compaction block in streaming chunks.** Session JSONL deduplication picks the final assembled message. The final assembled content should contain the complete compaction block. Verify with a test JSONL.
- **`stop_reason: "compaction"` vs `stop_reason: "end_turn"`.** Regular compaction (no pause) has `stop_reason: "end_turn"` on the final message. `stop_reason: "compaction"` only occurs with `pause_after_compaction: true`. Both cases should show the compaction row in Token Pane; the stop reason badge (from `feature_stop_reason_display.md`) differentiates them.

## Verification

1. Create test JSONL:
   ```json
   {"type":"assistant","content":[{"type":"compaction","content":"Summary: user wanted web scraper..."}],"stop_reason":"end_turn","usage":{"input_tokens":23000,"output_tokens":1000,"iterations":[{"type":"compaction","input_tokens":180000,"output_tokens":3500},{"type":"message","input_tokens":23000,"output_tokens":1000}]}}
   ```
2. Start monitor on session containing this entry.
3. Screenshot Token Pane: `./venv/bin/python dev/display/screenshot_panes.py`
4. Verify: compaction separator row visible, before/after counts correct, summary shown.
5. Verify warnings pane silent: `tmux capture-pane -t monitor_cc_global:3.0 -p | grep -c "unknown"` → 0.
6. Verify token total: Token Pane should show 23k+1k (message iteration), not 180k+23k+1k (wrong) and not just 23k+1k from top-level (which would miss the compaction iteration).
