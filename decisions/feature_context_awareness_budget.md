# Feature: Context Awareness Token Budget Warnings

**Effort:** —
**Value:** low
**Sources:** sources/ContextWindow.md

## What

Claude Sonnet 4.6, Sonnet 4.5, and Haiku 4.5 receive automatic `<budget:token_budget>` and `<system_warning>Token usage: X/Y; Z remaining</system_warning>` blocks from the model during sessions. These are model-injected additions to user messages after each tool call.

## Why

No Monitor_CC change is recommended. The Token Pane already shows exact token counts more precisely than these budget warnings. The `<system_warning>` blocks are injected into user messages by the model itself — they appear in the API requests (outgoing from CC), not in the API responses (session JSONL). They would only be visible in the Proxy Pane's raw_payload message content, where they already appear naturally as part of the message text.

From ContextWindow.md: "After each tool call, Claude receives an update on remaining capacity: `<system_warning>Token usage: 35000/1000000; 965000 remaining</system_warning>`"

These warnings serve Claude (so it knows how much context is left), not the human developer. Monitor_CC's Token Pane and Proxy Pane already provide better and more accurate context window information than these injected warnings.

## How — Implementation Plan

No implementation needed.

Observation: these `<system_warning>` blocks inflate message content slightly in the proxy JSONL (they appear in message[N] text). They don't affect token counting because they're counted as part of the message. The proxy's `_strip_system_reminder()` function should NOT strip these (they're in user messages, not system reminders) — no change needed.

## Risk / Edge Cases

- **False positive in content stripping:** The proxy's `content_strip.py` must not accidentally strip `<system_warning>` blocks that appear in user message content. These are legitimate message content injected by the model to maintain context awareness. Verify that the strip logic targets only `<system-reminder>` blocks in the system prompt, not `<system_warning>` blocks in user messages.
- **Token counting accuracy:** The `<budget:token_budget>` injection happens once at conversation start and is a fixed-size block. It adds ~5-10 tokens. This is visible in the `D` (input_tokens) count but not specifically called out. No action needed.

## Verification

No verification needed — this is a decision NOT to implement.

To observe the budget blocks: Proxy Pane → expand a request → look at message content for requests after tool calls. You should see `<system_warning>` text in user messages on Sonnet 4.5+ sessions.
