# Feature: Fine-grained Tool Streaming (eager_input_streaming)

**Effort:** —
**Value:** low
**Sources:** sources/FineGrained1.md

## What

The `eager_input_streaming: true` per-tool flag enables streaming of tool input parameters character-by-character without buffering, reducing first-token latency for large parameters from ~15s to ~3s. This is an internal CC optimization for its own tools (e.g. Write, Edit).

## Why

No Monitor_CC change is recommended. This is a request-side configuration detail that affects latency but not the semantic content of tool calls. The session JSONL already contains the final assembled tool input after all deltas are accumulated — Monitor_CC never sees the partial streaming chunks.

If CC adds `eager_input_streaming` to a tool definition, the only visible effect in Monitor_CC would be that the `tools_bytes_hash` in `sent_meta` changes (because the tool schema now includes `eager_input_streaming: true`). This would show as `⚠ TOOLS CHANGED` in the Proxy Pane — correct behavior, not a bug.

From FineGrained1.md: "Fine-grained tool streaming is generally available on all models and all platforms." and "With fine-grained tool streaming, tool use chunks start streaming faster, and are often longer and contain fewer word breaks."

The Proxy Pane already shows tool definitions and would show `eager_input_streaming: true` in the tool schema if it appeared in the raw_payload.

## How — Implementation Plan

No implementation needed. Existing behavior is correct.

Optional documentation note: If CC starts adding `eager_input_streaming: true` to tool schemas, the resulting `⚠ TOOLS CHANGED` in the Proxy Pane is expected and not a cache bug. Add a note to `decisions/cache_rebuild_cases.md` if this causes user confusion.

## Risk / Edge Cases

- **Invalid JSON from streaming cutoff:** FineGrained1.md warns: "Because fine-grained streaming sends parameters without buffering or JSON validation, there is no guarantee that the resulting stream will complete in a valid JSON string. Particularly, if the stop reason max_tokens is reached, the stream may end midway through a parameter." This is CC's responsibility to handle, not Monitor_CC's.
- **`tools_bytes_hash` change:** If CC adds/removes `eager_input_streaming` from a tool mid-session, Proxy Pane will show `⚠ TOOLS CHANGED` — this is a genuine cache-invalidating change (the tool schema changed).

## Verification

No verification needed — this is a decision NOT to implement.

To confirm current behavior: run a CC session with Write tool calls, check Proxy Pane tool display, verify `eager_input_streaming` is NOT yet present in the tool schema. If it appears in the future, verify `⚠ TOOLS CHANGED` fires on the first request where it's added.
