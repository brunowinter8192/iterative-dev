# Feature: Programmatic Tool Calling Block Types

**Effort:** S (silence) / M (display)
**Value:** low
**Sources:** sources/ProgToolCalling1.md, sources/ProgToolCalling2.md, sources/ProgToolCalling3.md

## What

Handle new block types and fields introduced by programmatic tool calling (`code_execution_20260120`): `caller` field on `tool_use` blocks, `container` field in responses, and `code_execution_tool_result` / `bash_code_execution_tool_result` block types. Primarily: ensure these don't generate unknown-type warnings.

## Why

The value is low because Claude Code does not currently use programmatic tool calling (`code_execution_20260120`). CC uses `bash` and `text_editor` (Anthropic-schema tools) but not the code execution container for programmatic tool invocations.

However, `bash_code_execution_tool_result` and `code_execution_tool_result` may appear in sessions that use code execution tools (even without programmatic calling) — specifically `code_execution_20250825` which is the standard code execution tool. If any CC session uses code execution, these block types would appear in session JSONL.

From Tools6.md: `code_execution_requests` in `usage.server_tool_use` is already worth tracking (see `feature_server_tool_counters.md`).

## How — Implementation Plan

### Phase 1: Silence unknown type warnings (S)

1. **`src/constants.py`** — Audit `KNOWN_MESSAGE_TYPES` and add any missing code execution block types:
   - `"bash_code_execution_tool_result"` (result of `code_execution_20250825` bash execution)
   - `"text_editor_code_execution_tool_result"` (result of text editor tool in code execution)
   - `"code_execution_tool_result"` (legacy Python-only `code_execution_20250522`)
   - `"container_upload"` (file reference for code execution input)
   - `"server_tool_use"` (should already be present)

This alone fixes any unknown-type warnings from code execution tool results.

### Phase 2: Display caller field (M — deferred)

2. **`src/formatter.py`** — When rendering a `tool_use` block, check for `content.get("caller")`. If caller is `{"type": "code_execution_20260120", "tool_id": "..."}`, annotate the tool call with `(called from code)` to distinguish programmatic from direct invocations.

3. **`src/formatter.py`** / **`src/monitor_display.py`** — Show `container.id` and `container.expires_at` from the response when present. Helps track container lifecycle in long code-execution sessions.

Phase 2 is low priority and should only be implemented if CC starts using programmatic tool calling.

## Risk / Edge Cases

- **`bash_code_execution_tool_result` vs `code_execution_result` (nested).** The outer block is `bash_code_execution_tool_result` and its content contains a `bash_code_execution_result` with `stdout`, `stderr`, `return_code`. The formatter should handle the nesting.
- **`container_upload` in user messages.** When a file is uploaded to code execution via `container_upload: {file_id: "..."}`, this block appears in user message content. Must not crash when no matching tool result exists.
- **`code_execution_20260120` vs `code_execution_20250825`.** The newer version adds REPL state persistence and programmatic tool calling. The older version has standard Python/Bash execution only. Both produce similar result block types.
- **Phase 2 is spec-forward.** The `caller` field and `container` field in responses — verify these actually appear in session JSONL before implementing Phase 2. The session JSONL records responses, not requests, so `container` info would be in the response object.

## Verification

### Phase 1:
1. Run a CC session that uses a code execution tool (if any CC tool uses it).
2. Grep session JSONL: `jq '.. | objects | select(.type | test("code_execution"))' ~/.claude/projects/*/*.jsonl | jq -r '.type' | sort | uniq -c`.
3. For each found type, verify it's in `KNOWN_MESSAGE_TYPES`.
4. Screenshot warnings pane: no code_execution-related unknown-type warnings.

### Phase 2 (if implemented):
5. Find a session with programmatic tool calling (`caller.type == "code_execution_20260120"`).
6. Main pane shows `(called from code)` annotation on programmatic tool calls.
7. Container ID and expiry visible in response summary.
