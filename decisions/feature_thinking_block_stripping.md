# Feature: Thinking Block Stripping Annotation in Token Pane

**Effort:** S
**Value:** low
**Sources:** sources/ContextWindow.md

## What

The Anthropic API automatically strips thinking blocks from previous turns before counting input tokens. This means the `input_tokens` value in session JSONL is lower than a naive sum of all message content would suggest. Monitor_CC could annotate requests in the Token Pane where thinking tokens were stripped, clarifying the discrepancy.

## Why

The value is low because no data is currently wrong — the Token Pane already shows the correct, already-stripped `input_tokens` from the session JSONL. The issue is purely explanatory: users who see thinking tokens in the pane may wonder why `D` (input_tokens) appears lower than expected given the visible thinking content.

The annotation would explain: "thinking blocks from N previous turns stripped from input (saves ~Xk tokens)".

This is cosmetic. The more important behavior to understand is that thinking blocks from the CURRENT turn DO count, and thinking blocks must be included when returning tool results — but those are CC's responsibility, not Monitor_CC's.

## How — Implementation Plan

1. **`src/jsonl_extractors.py`** — When extracting a request entry, check whether the current assistant turn contains thinking blocks (`type: "thinking"`) AND previous assistant turns in the conversation history also contained thinking blocks. If yes, note that stripping occurred. In practice: the JSONL only contains the response, not the full message history — so this is only partially detectable.

   Simpler approach: if `thinking.type` is enabled in the request (visible in raw_payload) AND the session has more than 1 request, annotate all requests after the first with "(thinking stripped from prior turns)".

2. **`src/token_format.py`** — Add a dim annotation line on requests where thinking is enabled and the request index > 0: `(thinking: N prev turns stripped)`.

3. **`src/constants.py`** — No new constants needed (reuse existing dim color).

Note: Step 1 requires access to the proxy raw_payload to know if thinking is enabled, OR reading the thinking config from the session JSONL response's `usage` (which doesn't directly expose thinking config). May need to correlate with Metadata Pane data.

Given this complexity and the low value, a simpler path: only show the annotation when the session JSONL response has `usage.cache_read_input_tokens > 0` AND thinking blocks are present in the response content. This is an approximation but covers the common case.

## Risk / Edge Cases

- **Tool-use exception:** When returning tool results that accompanied a thinking block, the thinking block MUST be included (not stripped). This case cannot be detected from Monitor_CC — it's CC's internal behavior.
- **Interleaved thinking (Claude Sonnet 4.6):** Multiple thinking blocks may appear between tool calls within a single turn. The stripping logic is per-turn, not per-block.
- **False annotation:** If the annotation fires incorrectly (thinking not actually stripped), it misleads the user. Better to not annotate than to annotate incorrectly.

## Verification

1. Run a session with `thinking: {type: "enabled"}` on Claude Sonnet 4.6.
2. Screenshot Token Pane after 3+ turns.
3. Verify annotation appears on turn 2+ only.
4. Verify no annotation on turn 1 (first request, nothing to strip yet).
