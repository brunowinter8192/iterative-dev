# Feature: Structured Outputs Indicator in Metadata Pane

**Effort:** S
**Value:** low
**Sources:** sources/Structured_outputs.md, sources/Structured_outputs2.md, sources/Structured_outputs3.md, sources/Structured_outputs4.md

## What

When a request includes `output_config.format` (JSON outputs) or `strict: true` on tool definitions (strict tool use), the Metadata Pane should display an indicator: `output: json_schema` or `tools: strict`. This helps explain grammar compilation latency on the first request with a new schema.

## Why

From Structured_outputs3.md: "First request latency: The first time you use a specific schema, there is additional latency while the grammar compiles." And: "Cache invalidation: The cache is invalidated if you change the JSON schema structure or the set of tools in your request."

Currently, if CC uses structured outputs, the latency spike on first use and the cache invalidation on schema change are invisible. The value is low because CC rarely uses structured outputs directly in its tool calls — but it's a one-line extraction so the cost is minimal.

Also: changing `output_config.format` invalidates the prompt cache for that thread. If this happens mid-session, the Proxy Pane would show an unexplained CC spike. The structured outputs indicator would explain it.

## How — Implementation Plan

1. **`src/monitor.py`** — In `_extract_raw_payload_fields()`, extract:
   - `raw_payload.get("output_config", {}).get("format", {}).get("type")` → `output_format_type` (e.g. `"json_schema"`)
   - Any tool in `raw_payload.get("tools", [])` with `strict == True` → `has_strict_tools` (bool)

2. **`src/metadata_format.py`** — In the config section, add an `output` line if either field is set:
   ```
   output: json_schema         ← if output_config.format is set
   tools: strict (3)           ← if strict tools present (count)
   ```
   Show in dim color since this is uncommon.

3. **`src/proxy_display/format.py`** — Optionally show `[json]` badge next to the request in Proxy Pane header when structured outputs are active.

4. **No proxy changes needed** — data comes from already-logged `raw_payload`.

## Risk / Edge Cases

- **Grammar compilation latency:** The first request with a new schema is slower. This is not currently measurable in Monitor_CC (no request timing). The indicator alone (showing that structured outputs are active) is sufficient.
- **Structured outputs + citations incompatibility:** If both `output_config.format` AND document citations are in the same request, the API returns a 400 error. If this error appears in the Warnings Pane, the structured outputs indicator in Metadata Pane helps diagnose why.
- **`output_format` (deprecated) vs `output_config.format`:** The old `output_format` parameter still works during a transition period. Extract both: check `output_config.format` first, fall back to `output_format`.
- **Schema caching 24h:** The compiled grammar is cached 24h after last use. This is server-side; no Monitor_CC impact.

## Verification

1. Run a CC session that produces a `json_schema` response (rare in normal CC usage).
2. Screenshot Metadata Pane.
3. Verify `output: json_schema` line appears.
4. Verify absence on normal requests.
5. Test with a tool that has `strict: true` — verify `tools: strict` indicator appears.
