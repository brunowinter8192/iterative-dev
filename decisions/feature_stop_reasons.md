# Feature: Complete Stop Reason Set — Parser + Display

**Effort:** S
**Value:** medium
**Sources:** sources/Stop-Verhalten1.md, sources/Stop-Verhalten2.md, sources/Stop-Verhalten3.md, sources/Stop-Verhalten4.md, sources/Stop-Verhalten5.md

## What

The Anthropic API has expanded its `stop_reason` set since Monitor_CC was built. New additions: `refusal` (streaming classifier intervention), `model_context_window_exceeded` (context window hit, distinct from `max_tokens`), `compaction` (compaction summary generated with `pause_after_compaction`), `pause_turn` (server-side loop iteration limit reached). Monitor_CC should extract `stop_reason` from session JSONL and display it per-request in the Token Pane with color-coding for non-standard values.

## Why

`stop_reason` is currently parsed from JSONL but not displayed per-request in the Token Pane. Missing it means:
- A `refusal` mid-session looks like a normal request from the token counts alone
- A `pause_turn` (server-side loop hit limit, needs continuation) is invisible — the user would see a stalled session without explanation
- A `model_context_window_exceeded` (different cost/behavior from `max_tokens`) looks identical to `max_tokens` in the display
- A `compaction` pause (waiting for continuation message) is invisible

From Stop-Verhalten1.md: "When you receive `stop_reason: refusal`, you must reset the conversation context by removing or updating the turn that was refused before continuing. Attempting to continue without resetting will result in continued refusals."

This is actionable diagnostic information that should be visible at a glance.

## How — Implementation Plan

1. **`src/jsonl_extractors.py`** — Extract `stop_reason` from the session JSONL response message object (`message["stop_reason"]`). This field is already present in the JSONL — verify that it's being returned in the extraction pipeline.

2. **`src/token_format.py`** / **`src/token_pane.py`** — In the per-request row rendering, show `stop_reason` as a compact badge after the token counts:
   ```
   [end_turn]       → dim/omit (most common, noise)
   [tool_use]       → neutral blue
   [max_tokens]     → yellow  ⚠
   [pause_turn]     → yellow  ⚠ (server loop limit)
   [refusal]        → red     ✗ (classifier blocked)
   [compaction]     → blue    📦 (compaction fired)
   [model_ctx_exceeded] → orange ⚠ (context window hit)
   [stop_sequence]  → neutral green
   ```
   Only show non-standard stop reasons by default; `end_turn` is omitted (too common). Option to show all with a toggle.

3. **`src/constants.py`** — Add color constants if missing:
   - `COLOR_STOP_REFUSAL` (red, e.g. `\033[38;5;196m`)
   - `COLOR_STOP_WARNING` (yellow, e.g. `\033[38;5;220m`)
   - `COLOR_STOP_COMPACTION` (blue — may reuse `COLOR_COMPACTION` from compaction feature)
   - `COLOR_STOP_CTX` (orange, e.g. `\033[38;5;208m`)

4. **`src/warnings_pane.py`** — When `stop_reason == "refusal"` occurs, add an entry to the warnings pane: "REFUSAL at REQ#N — conversation context must be reset". This is actionable.

5. **`src/DOCS.md`** — Update `token_format.py` entry to document stop_reason display.

## Risk / Edge Cases

- **`stop_reason` vs streaming chunks:** Session JSONL contains multiple streaming chunks per request. Deduplication (by input signature) already picks the final chunk which has the correct `stop_reason`. No change needed to deduplication logic.
- **`stop_reason: null` in intermediate chunks:** The initial `message_start` event has `stop_reason: null`. The final assembled message has the real `stop_reason`. Verify that the JSONL parser is reading from the final deduplicated entry.
- **Compaction stop_reason:** Only fires when `pause_after_compaction: true`. Regular compaction (without pause) has `stop_reason: end_turn` on the final message and the compaction block is internal. Display logic must check for both: `stop_reason == "compaction"` AND `content contains type:"compaction"`.
- **`refusal` and streaming:** From Streaming_Refusals.md — when `stop_reason: refusal` occurs, some partial content may have been generated. The session JSONL should reflect the actual generated content + refusal stop reason.

## Verification

1. Craft a test JSONL entry with `stop_reason: "refusal"`.
2. Inject into a monitored session file.
3. Screenshot Token Pane: verify red `[refusal]` badge appears on that request row.
4. Verify `end_turn` requests do NOT show a badge (omitted for cleanliness).
5. Test `pause_turn`: use a web search tool that exhausts 10 iterations. Token Pane should show `[pause_turn]` yellow badge.
6. Grep: `jq 'select(.stop_reason != "end_turn") | {req: .request_id, stop: .stop_reason}' ~/.claude/projects/*/*.jsonl` to find non-standard stop reasons in existing sessions.
