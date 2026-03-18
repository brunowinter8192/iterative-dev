---
name: rules-check
description: Check automation files for redundancy, symlink integrity, and project structure compliance. Reads all rules, skills, and CLAUDE.md files, then writes a RULES_REPORT.md.
---

# Rules Redundancy & Structure Check

Systematic review of all automation files for redundancy, misplacement, and structural compliance.

---

## Phase 1: Collect All Automation Files

Read EVERY file listed below. Do NOT skip any.

### Global Layer
- `~/.claude/rules/*.md` — all files
- `~/.claude/CLAUDE.md`

### Shared Rules Layer
- `~/.claude/shared-rules/global/*.md` — all files
- `~/.claude/shared-rules/mcp/*.md` — all files

### Project Layer
- `<project>/.claude/rules/*.md` — follow symlinks, read actual content
- `<project>/CLAUDE.md`

### Skills Layer (iterative-dev plugin)
Read from plugin cache: `~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0/skills/`
- `iterative-dev/SKILL.md`
- `recap/SKILL.md`
- `worker-rules/SKILL.md`
- `doc-review/SKILL.md`
- `rules-check/SKILL.md` (this skill — check for self-redundancy too)

After reading all files, proceed to Phase 2.

---

## Phase 2: Check Content Redundancy

Compare every pair of files for overlapping rules. For each rule/instruction found in a file, check if the same or similar instruction exists in another file.

### Redundancy Types

**DUPLICATE** — Same rule stated in 2+ files, exact or near-identical wording.
Example: "NO comments inside function bodies" in both `code-standards.md` and project `CLAUDE.md`.

**OVERLAP** — Same topic covered in 2+ files with different wording or scope.
Example: Error handling rules in `code-standards.md` AND `verify-before-execution.md`.

**MISPLACED** — Behavioral rule in CLAUDE.md that belongs in `.claude/rules/` (CLAUDE.md should only contain: project description, Sources reference, Pipeline Components, Key Files, Project Structure).

**STALE** — Rule references files, paths, tools, or configurations that no longer exist in the project.

### How to Detect

For each rule/paragraph in each file:
1. Extract the core instruction (what Claude must do/not do)
2. Search all other files for the same instruction
3. If found: classify as DUPLICATE (same wording) or OVERLAP (different wording, same intent)
4. If rule is in CLAUDE.md and is behavioral: classify as MISPLACED
5. If rule references a specific file path: verify the path exists, else STALE

---

## Phase 3: Check Symlink Integrity

```bash
# List all symlinks and their targets
find <project>/.claude/rules -type l -exec sh -c 'echo "{} → $(readlink "{}")"' \;

# Find broken symlinks
find <project>/.claude/rules -type l ! -exec test -e {} \; -print

# Find local copies that should be symlinks
find <project>/.claude/rules -maxdepth 1 -type f -name "*.md" -exec basename {} \;
```

### Expected Symlinks

**All projects (global):**
- `code-organization.md` → `~/.claude/shared-rules/global/code-organization.md`
- `code-standards.md` → `~/.claude/shared-rules/global/code-standards.md`
- `documentation.md` → `~/.claude/shared-rules/global/documentation.md`
- `decisions.md` → `~/.claude/shared-rules/global/decisions.md`
- `dev-convention.md` → `~/.claude/shared-rules/global/dev-convention.md`
- `project-standards.md` → `~/.claude/shared-rules/global/project-standards.md`

**MCP projects (additional):**
- `mcp-integration.md` → `~/.claude/shared-rules/mcp/mcp-integration.md`
- `server-pattern.md` → `~/.claude/shared-rules/mcp/server-pattern.md`
- `testing.md` → `~/.claude/shared-rules/mcp/testing.md`
- `tool-design.md` → `~/.claude/shared-rules/mcp/tool-design.md`

**How to detect MCP project:** `server.py` exists at project root.

### Symlink Issues

- **BROKEN**: Symlink target does not exist
- **LOCAL_COPY**: File should be a symlink but is a regular file
- **MISSING**: Expected symlink not present at all
- **EXTRA**: Symlink to shared-rules that shouldn't be there (e.g., mcp/ symlinks in non-MCP project)

---

## Phase 4: Check Project Structure Compliance

### CLAUDE.md Template
Verify these sections exist (in order):
1. `# <Project Name>` + one-liner description
2. `## Sources` — must contain ONLY a reference: `See [sources/sources.md](sources/sources.md).`
   - If Sources section contains an inline table → MISPLACED (should be in sources/sources.md)
3. `## Pipeline Components` (can be empty heading)
4. `### Key Files` (under Pipeline Components, can be empty heading)
5. `## Project Structure` with directory tree

Flag any other `## ` sections as potential MISPLACED content.

### Directory Structure
- `sources/sources.md` exists
- `decisions/` directory exists
- No `debug/` directory at project root
- If `decisions/` has files: `dev/` exists with pipeline-grouped sub-dirs

---

## Phase 5: Write Report

Write `RULES_REPORT.md` in the project root with this format:

```markdown
# Rules Redundancy Report

**Project:** <project-name>
**Date:** <date>
**Files Analyzed:** <count>

## Redundancies

| # | Rule Topic | File A | File B | Type | Recommendation |
|---|------------|--------|--------|------|----------------|
| 1 | ... | ... | ... | DUPLICATE | Remove from File B |

## Symlink Issues

| File | Expected | Actual | Status |
|------|----------|--------|--------|
| code-organization.md | symlink → shared-rules/global/ | symlink ✅ | OK |
| server-pattern.md | symlink → shared-rules/mcp/ | local copy | LOCAL_COPY |

## Structure Issues

| Check | Status | Details |
|-------|--------|---------|
| CLAUDE.md template | ✅ / ❌ | ... |
| sources/sources.md | ✅ / ❌ | ... |
| decisions/ | ✅ / ❌ | ... |
| dev/ convention | ✅ / ❌ | ... |
| No debug/ at root | ✅ / ❌ | ... |

## Summary

- **Redundancies:** X found (Y DUPLICATE, Z OVERLAP, W MISPLACED, V STALE)
- **Symlink issues:** X found
- **Structure issues:** X found
- **Overall:** CLEAN / NEEDS FIXES
```

Do NOT commit RULES_REPORT.md — it is a process artifact for the main agent to review.
