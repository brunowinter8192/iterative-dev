# Feature: Streaming Refusal Detection and Display

**Effort:** S
**Value:** low
**Sources:** sources/Streaming_Refusals.md

## What

Detect `stop_reason: "refusal"` in session JSONL and surface it prominently in the Token Pane (red badge) and Warnings Pane (actionable entry). The `refusal` stop reason means a streaming classifier intervened — distinct from model-generated refusals which produce normal text output.

*This feature is a subset of `feature_stop_reason_display.md` — it focuses specifically on the `refusal` case and the Warnings Pane integration.*

## Why

From Streaming_Refusals.md: "When you receive `stop_reason: refusal`, you must reset the conversation context by removing or updating the turn that was refused before continuing. Attempting to continue without resetting will result in continued refusals."

This is the most actionable stop reason — it requires a specific recovery action. A `refusal` that goes unnoticed (because Monitor_CC doesn't surface it) means:
- The CC session may appear stalled without explanation
- The user doesn't know the recovery action

Also from Streaming_Refusals.md: "Refusal Type | Streaming classifier refusals → `stop_reason: refusal` during streaming when content violates policies"

The value is low (not medium) because CC rarely produces refusals in normal agentic workflows — but when it does, visibility matters.

## How — Implementation Plan

1. **`src/jsonl_extractors.py`** — Ensure `stop_reason` is extracted from session JSONL (see `feature_stop_reason_display.md` step 1 — same extraction).

2. **`src/token_format.py`** — Show `refusal ✗` badge in red on the Token Pane request row (see `feature_stop_reason_display.md` step 2 — same rendering).

3. **`src/warnings_pane.py`** — When processing a session JSONL entry with `stop_reason == "refusal"`, add a warnings pane entry:
   ```
   [REFUSAL] REQ#N — streaming classifier blocked response
             Action: reset conversation context (remove refused turn)
   ```
   Use `COLOR_ERROR` (red) for this entry. This is the one place where the required recovery action is documented for the user.

4. **No new constants needed** — reuse existing `COLOR_ERROR` or `COLOR_STOP_REFUSAL` (added in `feature_stop_reason_display.md`).

5. **No proxy changes.** `stop_reason` comes from session JSONL only.

## Risk / Edge Cases

- **Model-generated refusals vs. classifier refusals.** From Streaming_Refusals.md, there are three types: (1) streaming classifier → `stop_reason: refusal`, (2) API input validation → 400 error, (3) model-generated → standard text response with explanation. Only case (1) has `stop_reason: refusal`. Cases (2) and (3) have different handling. This feature targets only case (1).
- **Billing.** From Streaming_Refusals.md: "Usage metrics are still provided in the response for billing purposes, even when the response is refused. You will be billed for output tokens up until the refusal." This means the Token Pane token counts are valid even for refused responses.
- **Empty content.** A refused response may have very few output tokens and possibly empty or minimal content. The Token Pane should not crash on empty content blocks.
- **Warnings pane deduplication.** If the same session is re-read (file hasn't changed), the warnings pane should not duplicate the refusal warning. Use the request index as a deduplication key.

## Verification

1. Craft a test JSONL entry with `stop_reason: "refusal"` and minimal content.
2. Start monitor, screenshot Token Pane and Warnings Pane.
3. Verify: red `refusal ✗` badge in Token Pane on the refused request.
4. Verify: warnings pane shows the refusal entry with recovery action text.
5. Verify: normal `end_turn` requests are unaffected.
6. Check that token counts display correctly even for the refused (few-token) response.
