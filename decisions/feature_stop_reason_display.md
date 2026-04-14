# Feature: Stop Reason Display in Token Pane

**Effort:** S
**Value:** medium
**Sources:** sources/Stop-Verhalten1.md, sources/Stop-Verhalten2.md, sources/Stop-Verhalten3.md, sources/Stop-Verhalten4.md, sources/Stop-Verhalten5.md

## What

Display `stop_reason` as a color-coded badge per request in the Token Pane. Suppress `end_turn` (too common, visual noise) but prominently show non-standard values: `refusal` (red), `pause_turn` (yellow), `max_tokens` (yellow), `compaction` (blue), `model_context_window_exceeded` (orange).

*See also: `feature_stop_reasons.md` for the complete set of stop reasons and their API semantics.*

## Why

`stop_reason` is extracted from session JSONL but currently not surfaced per-request in the Token Pane. A user watching a stalled CC session has no way to distinguish "session paused because server loop hit iteration limit (`pause_turn`)" from "session completed normally". Similarly, a `refusal` looks identical to a normal `end_turn` in the Token Pane today.

This is a one-field extraction with no additional API calls — purely display logic on already-available data.

## How — Implementation Plan

1. **`src/jsonl_extractors.py`** — Verify that `stop_reason` is extracted from the session JSONL response message. If not already extracted, add it to the per-request data structure. The field is in the final deduplicated message object: `message["stop_reason"]`.

2. **`src/token_format.py`** — In request row rendering, after the token bar, append a `stop_reason` badge:
   ```python
   STOP_REASON_STYLES = {
       "end_turn": None,           # omit — too common
       "tool_use": None,           # omit — expected
       "stop_sequence": (COLOR_DIM, "stop_seq"),
       "max_tokens": (COLOR_WARN_YELLOW, "max_tokens ⚠"),
       "pause_turn": (COLOR_WARN_YELLOW, "pause_turn ⚠"),
       "refusal": (COLOR_STOP_REFUSAL, "refusal ✗"),
       "compaction": (COLOR_COMPACTION, "compaction 📦"),
       "model_context_window_exceeded": (COLOR_STOP_CTX, "ctx_limit ⚠"),
   }
   ```
   Only non-None entries render a badge. Badge appears at the end of the request row, right-aligned or appended after the token numbers.

3. **`src/constants.py`** — Add missing color constants:
   - `COLOR_STOP_REFUSAL = \033[38;5;196m` (red)
   - `COLOR_WARN_YELLOW = \033[38;5;220m` (yellow) — may already exist
   - `COLOR_STOP_CTX = \033[38;5;208m` (orange)
   - `COLOR_COMPACTION = \033[38;5;75m` (light blue) — also needed by `feature_compaction_parser.md`

4. **`src/warnings_pane.py`** — For `stop_reason == "refusal"`, additionally add an entry to the warnings pane (not just Token Pane). `refusal` means the conversation history must be reset — it's actionable and important enough to surface in warnings.

5. **No proxy changes.** Stop reason comes from session JSONL only.

## Risk / Edge Cases

- **`stop_reason: null` in streaming chunks.** The initial `message_start` event has `stop_reason: null`. Session JSONL deduplication picks the final assembled message which has the real `stop_reason`. Verify deduplication produces correct `stop_reason` in the token accumulation logic.
- **`tool_use` stop reason flood.** If `tool_use` stop reason is shown, multi-tool-call sessions would show a badge on every tool call request. Suppress it (same as `end_turn`).
- **`compaction` stop reason edge case.** Only fires with `pause_after_compaction: true`. Regular compaction has `stop_reason: "end_turn"` on the final message (the compaction block is returned alongside the text). Badge must check BOTH `stop_reason` AND content for compaction blocks (see `feature_compaction_parser.md`).
- **Badge width.** Badges must fit in the terminal width without wrapping. Keep badge text ≤ 12 chars. Use abbreviations if needed.

## Verification

1. Craft test JSONL entries with various stop reasons (`refusal`, `max_tokens`, `pause_turn`).
2. Screenshot Token Pane for each.
3. Verify: `end_turn` requests show no badge, `refusal` shows red `✗ refusal` badge.
4. Verify warnings pane shows entry for `refusal` stop reason.
5. Check existing sessions: `jq 'select(.stop_reason != null and .stop_reason != "end_turn")' ~/.claude/projects/*/*.jsonl | jq -r .stop_reason | sort | uniq -c` — find all non-standard stop reasons in existing data.
