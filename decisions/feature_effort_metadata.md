# Feature: Effort Parameter Display in Metadata Pane

**Effort:** S
**Value:** medium
**Sources:** sources/Effort.md

## What

Extract `output_config.effort` from the proxy `raw_payload` and display it in the Metadata Pane config section alongside model, max_tokens, and thinking type.

*See also: `feature_effort_parameter.md` for the full API behavior context.*

## Why

Effort directly controls how many tokens Claude spends — on text, tool calls, and thinking. Sonnet 4.6 defaults to `high` effort, which means "almost always thinks deeply." A user debugging unexpectedly high token consumption or latency on Sonnet 4.6 has no way to see the effort level from Monitor_CC today.

From Effort.md: "Recommended effort levels for Sonnet 4.6: Set effort explicitly to avoid unexpected latency: Medium effort (recommended default): Best balance of speed, cost, and performance for most applications."

This is a one-field read from `raw_payload` — no additional data pipeline work.

## How — Implementation Plan

1. **`src/monitor.py`** — In `_extract_raw_payload_fields()`, add:
   ```python
   effort = raw_payload.get("output_config", {}).get("effort")
   # fall back to deprecated field
   if effort is None:
       effort = raw_payload.get("output_config", {}).get("budget_tokens") and "budget_tokens_mode"
   ```
   Store as `effort_level` (string or None).

2. **`src/metadata_format.py`** — In the config section rendering (the block that shows model, max_tokens, thinking), add an `effort` line:
   ```
   effort: medium
   ```
   If `effort_level` is None (field absent in request), show `effort: high (default)` in dim color — making the default visible.
   
   Color by value:
   - `max`: orange/yellow (maximum spend)
   - `high`: normal color
   - `high (default)`: dim
   - `medium`: green (efficient)
   - `low`: bright green (most efficient)

3. **`src/constants.py`** — No new constants needed if reusing existing color scheme. Optionally add:
   ```python
   EFFORT_COLORS = {
       "max": COLOR_WARNING,
       "high": COLOR_NORMAL,
       "medium": COLOR_GREEN,
       "low": COLOR_GREEN,
   }
   ```

4. **`src/DOCS.md`** — Update `metadata_format.py` entry to document `effort_level` field and its display logic.

## Risk / Edge Cases

- **`output_config` absent entirely.** Common for older requests or simple CC requests. Default display: `effort: high (default)`. No crash.
- **`budget_tokens` (deprecated on Opus 4.6/Sonnet 4.6).** If `budget_tokens` is present but `effort` is not, show `budget_tokens: N (deprecated)` in dim color. This helps diagnose if CC is using the old parameter.
- **`output_config.format` (structured outputs).** The same `output_config` block may also contain `format`. Extract both independently. See `feature_structured_outputs.md`.
- **Proxy raw_payload timing.** `effort_level` is extracted from `raw_payload` in `monitor.py` — this runs in the monitor process, not the proxy process. No proxy restart needed.
- **Effort field is a string.** Values are `"max"`, `"high"`, `"medium"`, `"low"`. No numeric parsing needed.

## Verification

1. Find or create a CC session request with explicit `effort: medium` in the payload.
   - Can craft test proxy log entry with `"output_config": {"effort": "medium"}`.
2. Start monitor, screenshot Metadata Pane.
3. Verify: `effort: medium` visible in config section, green color.
4. Compare with a request without `effort` field — should show `effort: high (default)` in dim.
5. Grep proxy log for requests with explicit effort: `jq 'select(.raw_payload.output_config.effort != null)' src/logs/api_requests_*.jsonl | head -3`.
