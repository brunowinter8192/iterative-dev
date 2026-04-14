# Feature: Skills List Change Detection in Proxy Pane

**Effort:** S
**Value:** medium
**Sources:** sources/Skills1.md, sources/Skills5.md

## What

Changing the `container.skills` list between requests breaks the prompt cache (the skill metadata is injected into the system prompt prefix). The Proxy Pane should detect when `container.skills` changes between consecutive requests — similar to the existing `⚠ TOOLS CHANGED` warning — and display `⚠ SKILLS CHANGED` to explain an associated cache rebuild.

## Why

From Skills5.md: "Adding/removing Skills breaks cache — changing the Skills list in your container breaks the cache." If CC or a worker uses Agent Skills (pptx, xlsx, docx, pdf — or custom skills), any change to the skills list would cause a full cache rewrite. Currently the Proxy Pane has no awareness of `container.skills`, so this would appear as an unexplained `⚠ TOOLS CHANGED` or just a high CC value with no explanation.

The iterative-dev plugin already strips `system-reminders` that contain skill-related content. But the container.skills field in the raw_payload is separate from those reminders.

## How — Implementation Plan

1. **`src/proxy/addon.py`** — In `_build_entry()`, extract `raw_payload.get("container", {}).get("skills", [])`. Compute a hash of the sorted skill IDs + versions:
   ```python
   skills_hash = hashlib.md5(json.dumps(sorted(
       [(s["type"], s["skill_id"], s.get("version", "latest")) for s in skills]
   )).encode()).hexdigest()[:8] if skills else ""
   ```
   Add `skills_hash` and `skills_count` to the logged entry.

2. **`src/proxy/addon.py`** — In `sent_meta` building, compare current `skills_hash` with the previous request's hash (store in `ProxyAddon` state alongside `prev_messages_by_model`). If changed and non-empty, set `skills_changed: True` in the entry.

3. **`src/proxy_display/format.py`** — In `format_proxy_block()`, check `entry.get("skills_changed")`. If True, render `⚠ SKILLS CHANGED` warning line analogous to existing `⚠ TOOLS CHANGED`.

4. **`src/proxy_display/render_sections.py`** or **`format.py`** — Optionally show skills list in the expanded view: "skills: pptx@latest, xlsx@20251013".

5. **`src/DOCS.md`** (proxy) — Document `skills_hash`, `skills_count`, `skills_changed` fields in the proxy log entry format.

6. **`decisions/cache_rebuild_cases.md`** — Add new case: "Skills list changed during session → prefix invalidation".

## Risk / Edge Cases

- **proxy live-copy:** Changes to `addon.py` require a proxy restart (the live-copy mechanism isolates the running proxy). Test after proxy restart, not during a live session.
- **`container` field optional:** Many requests won't have `container.skills` at all. `skills_hash` should be empty string when absent; `skills_changed` should only fire when transitioning from non-empty to non-empty with different hash (not from absent to absent).
- **Skills + Tools combined:** If both tools AND skills change in the same request, both `⚠ TOOLS CHANGED` and `⚠ SKILLS CHANGED` should appear.
- **Version pinning:** Skills can be pinned to specific versions (date format for Anthropic skills, epoch timestamp for custom). The hash includes version, so upgrading a skill version would also fire `skills_changed`.

## Verification

1. Run a CC session with a skill in the first request, then send a second request with a different skill.
2. Proxy Pane should show `⚠ SKILLS CHANGED` on the second request.
3. Token Pane should show elevated CC (cache rebuild) on the same request.
4. Grep proxy log: `jq 'select(.skills_changed == true)' src/logs/api_requests_*.jsonl` → entry should appear.
5. Screenshot Proxy Pane to confirm warning display.
