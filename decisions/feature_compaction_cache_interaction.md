# Feature: Compaction + Prompt Caching Interaction (Knowledge Capture)

**Effort:** —
**Value:** low
**Sources:** sources/Compaction3.md

## What

When server-side compaction fires, the compaction summary becomes new content requiring a fresh cache write. If the system prompt has a `cache_control` breakpoint, the system prompt stays cached while only the compaction summary needs to be written. Monitor_CC's existing BP1-sys placement already handles this optimally.

## Why

This is a decision record confirming that the existing proxy design is already correct for the compaction case — no code change is needed.

From Compaction3.md: "To maximize cache hit rates, add a `cache_control` breakpoint at the end of your system prompt. This keeps the system prompt cached separately from the conversation, so when compaction occurs: The system prompt cache remains valid and is read from cache. Only the compaction summary needs to be written as a new cache entry."

Monitor_CC's BP1-sys (placed on the system prompt) does exactly this. When compaction fires:
- BP1-sys → system prompt stays cached (CR hit expected)
- The compaction block + subsequent messages → new CC write (expected, not a regression)

This means compaction events will show moderate CC (summary-sized) rather than full-session CC, which is the correct behavior.

## How — Implementation Plan

No implementation. Document in `decisions/pipe05_proxy_cache.md`:

> **Compaction compatibility (2026-07-16):** BP1-sys placement is compatible with server-side compaction. When compaction fires, the system prompt prefix remains cached via BP1-sys; only the compaction summary is written as a new CC entry. This is consistent with the Anthropic recommendation to "add a cache_control breakpoint at the end of your system prompt" for compaction use cases.

## Risk / Edge Cases

- If BP1-sys is ever removed or moved (e.g. if proxy is updated to use only BP2-tools and BP3-messages), compaction would cause a full cache rebuild of the system prompt. The pipe05 documentation update serves as a guard against this.
- If compaction fires and the resulting summary is larger than the 20-block lookback window (unlikely but theoretically possible for very long summaries), BP3-messages would need to be recalibrated. This is a theoretical edge case.

## Verification

No verification needed — this is a decision NOT to implement and a documentation update only.

Confirm via Proxy Pane: after a compaction event (when CC enables it), verify BP1-sys is still present in `sent_meta.sent_cache_breakpoints` and that CR shows a cache hit for the system prompt portion.
