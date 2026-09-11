---
name: iterative-dev-doccheck
description:
---

# Doc & Structure Check

## Core Rules

**§ Documentation Hierarchy is the sole standard, and it wins over the project's current state.**
- An existing structure is never a "project convention" that excuses a deviation.
   - A consistent deviation is still a deviation.

**Volume is never a scope argument.**
- Never sample, shortcut, or do only part; every rule-driven fix is carried through in full.

**Each Phase edits only its own surface.**
- Phase 1 process-docs, Phase 2 dev, Phase 3 DOCS.md, Phase 4 skills, Phase 5 issues.
- A finding that belongs to another surface waits for that surface's Phase.

## Workflow

### Phase 0 — Contact-layer check (Main only, once)

**Ask the user one question before Phase 1.**
- The question: "Besides this chat, does the project have a user-facing contact layer?"

**No means every directory is in scope.**

**Yes means the named directory is excluded from every Phase.**
- Never relocate, rename, translate, reframe, or reformat anything inside it.

**A worker never asks this.**
- Main passes any excluded path in the worker's prompt.
- The worker excludes exactly what the prompt names, nothing more.

### Phase 1 — process-docs

**Check every `process-docs/` folder and entry against every block of § process docs, and enforce.**
- The section's blocks are the checklist; nothing is repeated here.
- Every `process-docs/<area>/` folder gets an explicit verdict.
   - Verdict forms: `valid: <driving question>`, `folded into X`, `split into X+Y`, `dissolved`.
- A rename propagates to `dev/<area>/`.

**Check `.rag-docs.json` at the project root.**
- `include` covers every `DOCS.md` and `process-docs/**/*.md`, and every pattern matches at least one file on disk.
- `collection` follows `<Project>-docs` naming.
- No manifest present: flag in the report, do not create one.
- Do not run `rag-cli update_docs` here; index sync is a session-recap action.

### Phase 2 — dev

**Check every `dev/` folder and file against every block of § dev and the dev convention, and enforce.**
- The blocks are the checklist; nothing is repeated here.

**Placements the rules do not carry.**
- A maintenance or utility script goes in its thematic `dev/<area>/`; there is no exempt catch-all folder.
- A loose `.md` in `dev/` that no script produces is not a dev report.
   - It belongs in `process-docs/` if still relevant, or is deleted if stale.
- A folder whose contents span multiple areas is split, each part into its own `dev/<area>/`.

**Report versus data is decided by content.**
- A report is a readable analysis; a JSON analysis output counts and goes to `md/`.
- Data is the run's raw payload, like scraped corpora, raw dumps, or cached job data.

**Cumulative logs stay.**
- An append-only log tracked and compared across runs is not a report; leave it in place.

**A self-contained sub-suite gets its own `md/`.**
- Folders like `garbage_eval/` or `browser_eval/` hold their own `md/`, not the parent area's.

### Phase 3 — DOCS

**Check every `DOCS.md` against every block of § docs, and enforce.**
- The blocks are the checklist; nothing is repeated here.
- Use heredoc or `/tmp` scripts; do not read every `DOCS.md` by hand.

**Root files.**
- A root `README.md` is flagged for removal.
- A root `DOCS.md` that is a project overview is flagged for removal.
- A root `CLAUDE.md` documenting project-only interactive working areas is allowed.

**References resolve.**
- Every file a `DOCS.md` names exists on disk.
- A reference to a nonexistent file is deleted from the `DOCS.md`.

**Cut salvage before cutting.**
- Everything removed to reach the format goes verbatim into the author's own process-docs file, under one `## Salvage from <path>` heading per DOCS.md, before the cut.
- No coverage check, no per-cut triage; RAG makes the salvaged content findable.

### Phase 4 — skills (flag-only)

**Check every `skills/*/SKILL.md` against every block of § Artifact Density, and flag.**
- Findings here are collected, never fixed.

**Frontmatter: `description:` is present and empty.**
- A non-empty `description` is flagged.

**Flag WHY-content by signature.**

| Signature | Example | Action |
|---|---|---|
| Justification clause | "raw and maximal — content not captured is gone for good" | cut clause, keep instruction |
| Cause / mechanism | "the plugin cache has NO venv, so a plugin-relative path fails" | cut |
| Rationale section | a "Why X matters" section | delete section |
| Historical / evidence note | "(verified on 278 files)", "previous runs failed here" | cut |
| Illustrative "what happens otherwise" | "the same anchor just returns the same top sources" | cut |
| `because` / `so that` / `in order to` / `which means` | any clause led by these | cut clause |

**Never flag:**
- Commands, paths, thresholds, output formats, parameter tables, ordering rules, prohibitions, behavior facts the procedure depends on, decision-examples.

### Phase 5 — issues (Main only)

**A worker skips this Phase entirely.**

**Bring every open issue into the Issue Format of § GitHub Issues via `update_issue --body`.**
- The `Area:` line names the area per the post-audit folder structure.

### Phase 6 — Hand off

**Report the findings.**
- Per `process-docs/<area>/` folder its verdict and every entry that moved.
- Every fix applied in Phases 1-3, the Phase 4 flags, the Phase 5 rewrites.

**Main commits the doc fixes; workers are dispatched by volume, not by file type.**
- A surface too large to bring into line in one session goes to workers, one worktree per surface block.
- Each worker gets the concrete findings for its block in its prompt.
- Review and merge each worker's branch.
- Do not sync RAG here; the RAG sync is a session-recap action on the final merged state.

**As worker, you are done; no spawn.**
