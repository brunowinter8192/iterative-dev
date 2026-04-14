# Feature: KNOWN_MESSAGE_TYPES Batch Update

**Effort:** S
**Value:** high
**Sources:** sources/Compaction1.md, sources/ToolSearch2.md, sources/Search_results1.md, sources/Tools3.md, sources/Streaming_Messages5.md, sources/Citations3.md

## What

Audit `KNOWN_MESSAGE_TYPES` and `KNOWN_IGNORED_TYPES` in `src/constants.py` against all new content block types introduced since the last audit. Add missing types to stop warnings pane noise. This is a prerequisite housekeeping task for all other display features in this catalog.

## Why

Monitor_CC's warnings pane is designed to surface genuinely unknown or unexpected message types — it should be a signal, not noise. Currently it fires on every iterative-dev session due to ToolSearch block types. When additional features are added (compaction, context editing, search results), more types will be missing.

A polluted warnings pane means:
- Real unexpected types are buried in noise
- Users learn to ignore warnings pane → important signals are missed

This is a < 1-hour task with high ongoing value. It should be done BEFORE any other display feature implementation, because it clears the baseline.

## How — Implementation Plan

### Step 1: Audit current KNOWN_MESSAGE_TYPES

Read `src/constants.py` and list all entries in `KNOWN_MESSAGE_TYPES` and `KNOWN_IGNORED_TYPES`.

### Step 2: Verify against live session JSONL

Run this grep across existing sessions to find all distinct `type` values currently appearing:
```bash
jq -r '.. | objects | .type // empty' ~/.claude/projects/*/*.jsonl 2>/dev/null | sort | uniq -c | sort -rn | head -40
```

Also check proxy JSONL for block types that only appear in requests:
```bash
jq -r '.. | objects | .type // empty' src/logs/api_requests_*.jsonl 2>/dev/null | sort | uniq -c | sort -rn | head -40
```

### Step 3: Add missing types

Based on sources scan, the following types likely need to be added (verify each is actually absent before adding):

**Tool Search (ToolSearch1-3.md):**
- `"tool_search_tool_result"` — server-side tool search result block
- `"tool_reference"` — reference to a deferred tool (auto-expanded by API)
- `"tool_search_tool_search_result"` — nested content type inside tool_search_tool_result

**Compaction (Compaction1-3.md):**
- `"compaction"` — compaction summary block in assistant response

**Code Execution (Tools3.md, Tools5-6.md):**
- `"bash_code_execution_tool_result"` — result of code_execution_20250825 bash tool
- `"text_editor_code_execution_tool_result"` — result of text_editor tool in code execution
- `"code_execution_tool_result"` — outer wrapper for all code execution results
- `"bash_code_execution_result"` — inner result block (stdout, stderr, return_code)
- `"container_upload"` — file reference for code execution input

**Search Results (Search_results1.md):**
- `"search_result"` — RAG search result block with source + title + content

**Web Search (Streaming_Messages5.md):**
- `"web_search_tool_result"` — verify if already present (used in main pane)

**Citations (Citations3.md, streaming):**
- `"citations_delta"` — streaming delta event type for citation additions

**Context Management (ContextEditing3.md):**
- No new block types — `context_management` is a response field, not a content block type

### Step 4: Categorize each new type

For each type being added, decide placement:
- `KNOWN_MESSAGE_TYPES` — if Monitor_CC handles/displays it (or will handle it)
- `KNOWN_IGNORED_TYPES` — if it's a known type that Monitor_CC intentionally ignores

General rule: types that are server_tool results or wrapper types → `KNOWN_IGNORED_TYPES`. Types that carry content to display → `KNOWN_MESSAGE_TYPES` with a display handler (or add the display handler in the same PR).

### Step 5: Run warnings pane baseline test

After updating constants.py:
1. Start monitor on a recent iterative-dev session JSONL.
2. `tmux capture-pane -t monitor_cc_global:3.0 -p | grep "unknown"` → should return 0 results for the types added above.
3. Screenshot warnings pane: confirm clean baseline.

## Risk / Edge Cases

- **Overly broad silencing.** Adding types to `KNOWN_IGNORED_TYPES` without handlers means future bugs in those types won't surface. Prefer `KNOWN_MESSAGE_TYPES` with a minimal display handler.
- **Type collision.** Some type names may be reused across different block structures (e.g. `"text"` is used in many contexts). The audit is specifically about top-level `type` values on content blocks, not nested ones.
- **Dynamic types.** Some server-side result types have versioned names (e.g. `code_execution_20250825` is a tool TYPE, not a block type). These appear in the tools array, not in content blocks. Don't confuse tool `type` with content block `type`.
- **New types from future API updates.** This audit is a point-in-time fix. Re-run the grep quarterly to catch new types as Anthropic adds features.

## Verification

```bash
# Before: count unknown type warnings across recent sessions
./venv/bin/python workflow.py --project ~/.claude/projects/some-project &
sleep 5
WARNINGS=$(tmux capture-pane -t monitor_cc_global:3.0 -p | grep -c "unknown")
echo "Unknown type warnings before: $WARNINGS"
tmux kill-session -t monitor_cc_global

# Apply constants.py changes

# After: same test
./venv/bin/python workflow.py --project ~/.claude/projects/some-project &
sleep 5
WARNINGS=$(tmux capture-pane -t monitor_cc_global:3.0 -p | grep -c "unknown")
echo "Unknown type warnings after: $WARNINGS"
tmux kill-session -t monitor_cc_global
```

Expected: warnings count drops to 0 for types added. Any remaining warnings are genuinely new/unexpected.
