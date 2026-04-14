# Feature: Effort Parameter Display in Metadata Pane

**Effort:** S
**Value:** medium
**Sources:** sources/Effort.md

## What

The `output_config.effort` field in API requests controls Claude's token spend level: `max`, `high` (default), `medium`, `low`. Monitor_CC's Metadata Pane should extract this field from `raw_payload` and display it alongside existing config like model, max_tokens, and thinking type.

## Why

From Effort.md: "Recommended effort levels for Sonnet 4.6: Set effort explicitly to avoid unexpected latency. At high (default) effort, Claude almost always thinks deeply." This means CC sessions on Sonnet 4.6 may have unexpectedly high latency and token consumption if effort is implicitly `high`. Currently there is no way to see the effort level in Monitor_CC — a user debugging slow sessions would have no visibility into this lever.

Effort is also directly relevant to interpreting token counts:
- `high` or `max` → more thinking tokens, more tool calls, verbose output
- `medium` or `low` → fewer thinking tokens, faster, terser

Without seeing effort, Token Pane numbers are harder to interpret across sessions.

## How — Implementation Plan

1. **`src/proxy/addon.py`** or **`src/proxy_display/parser.py`** — In `_extract_raw_payload_fields()` (in `monitor.py`), extract `raw_payload.get("output_config", {}).get("effort", None)`. Return as `effort_level`. If absent, it defaults to `"high"` per API docs.

2. **`src/metadata_format.py`** — In the config section rendering (where model, max_tokens, thinking are shown), add an `effort` line:
   ```
   effort: medium
   ```
   If effort is absent from raw_payload (defaults to `high`), show `effort: high (default)` in dim color.
   If effort is `max` or `high`, show in normal color. If `medium` or `low`, show in green (saves tokens).

3. **`src/constants.py`** — No new constants needed (reuse existing color scheme). Optionally add `EFFORT_COLORS = {"max": COLOR_WARNING, "high": COLOR_NORMAL, "medium": COLOR_GREEN, "low": COLOR_GREEN}`.

4. **`src/proxy_display/format.py`** — In the proxy entry header, show effort alongside model name: `claude-sonnet-4-6 | effort: medium`. This is particularly useful for Proxy Pane since effort affects what goes on the wire.

5. **`src/DOCS.md`** — Update `metadata_format.py` and `metadata_pane.py` entries to document effort display.

## Risk / Edge Cases

- **Effort absence:** When `output_config` is absent entirely (e.g. older requests, requests without thinking), effort defaults to `"high"`. Display as `high (default)` to make the default visible.
- **`output_config` vs old `budget_tokens`:** On Opus 4.5 and earlier, effort coexists with `thinking.budget_tokens`. On Opus 4.6/Sonnet 4.6, `budget_tokens` is deprecated. If both are present, show both: `effort: medium, budget_tokens: 8000 (deprecated)`.
- **Proxy live-copy:** Extracting effort from `raw_payload` in `_extract_raw_payload_fields()` in `monitor.py` does NOT require a proxy change — it reads from the already-logged `raw_payload` field. No proxy restart needed.
- **Effort affects grammar caching (Structured Outputs):** No direct interaction — effort and structured outputs are independent fields.

## Verification

1. Run two CC sessions: one with explicit `effort: medium` in the request, one without.
2. Screenshot Metadata Pane for both.
3. Verify: first session shows `effort: medium`, second shows `effort: high (default)`.
4. Test with `low` and `max` to confirm color differentiation.
5. Grep proxy log: `jq 'select(.raw_payload.output_config.effort != null) | .raw_payload.output_config.effort' src/logs/api_requests_*.jsonl` to find requests with explicit effort.
