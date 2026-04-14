# Feature: Automatic Prompt Caching (Top-level cache_control)

**Effort:** —
**Value:** low
**Sources:** sources/PromptCaching1.md

## What

The Anthropic API supports a top-level `cache_control` field on the request (not on individual content blocks) that enables automatic caching: the API moves the breakpoint to the last cacheable block automatically as conversations grow, without requiring clients to manage breakpoint placement manually.

## Why

No Monitor_CC change is needed or recommended here. Monitor_CC's proxy already uses explicit BP-Layout v2 (BP1-sys, BP2-tools, BP3-messages, BP4-tail), which is intentionally more granular than automatic caching. Automatic mode would replace the proxy's fine-grained control with a single auto-placed breakpoint — a regression for Monitor_CC's use case.

The value is low because:
- The proxy's existing BP-Layout v2 already achieves optimal caching
- Automatic mode would remove observability (no way to predict where the breakpoint lands)
- Switching to automatic mode could break the two-marker BP-Layout v2 logic (Tools Anchor + Tools End) introduced in commit `060ff07`

This feature is documented here as a "no-implement" decision record.

## How — Implementation Plan

No implementation. Existing proxy behavior is correct and preferable.

If CC itself ever switches to automatic caching mode (sending top-level `cache_control` instead of block-level), the proxy would need to detect this and either:
- Leave it as-is (allow automatic + proxy explicit markers to coexist), or
- Strip the top-level `cache_control` and rely entirely on the proxy's explicit BP-Layout

Monitor this by checking the raw_payload in Proxy Pane for `cache_control` at the top level (not inside content blocks).

## Risk / Edge Cases

- If Anthropic deprecates block-level `cache_control` in favor of top-level-only, the proxy would need significant rework. Unlikely in the near term.
- Top-level `cache_control` and block-level `cache_control` can coexist in the same request according to the docs — the top-level one applies to remaining blocks not covered by explicit markers.

## Verification

No verification needed — this is a decision NOT to implement.

To confirm the proxy is using explicit block-level breakpoints (and not top-level): check any Proxy Pane entry — `sent_meta.sent_cache_breakpoints` should show specific message indices, not "auto".
