---
name: doc-review
description: Review and fix project documentation structure. Maps existing docs, identifies gaps, and dispatches workers to fix them.
---

# Documentation Structure Review

Phased review of project documentation against the documentation rules in `.claude/rules/documentation.md`.

**Prerequisite:** The project MUST have `.claude/rules/documentation.md` installed. If missing, STOP and inform the user.

---

## Phase 1: Read Rules

**Note for workers in worktrees:** `.claude/rules/` is gitignored and NOT available in worktrees. The main agent (Opus) MUST provide the absolute path to the rules file in the worker prompt:
```
Documentation rules: <absolute-project-path>/.claude/rules/documentation.md
```
Read the file at that path. If no path was provided and the file doesn't exist locally, write WORKER_REPORT.md with STOP: "No documentation rules path provided and .claude/rules/documentation.md not found."

1. Read the documentation rules file — this defines the standard
2. Confirm the rules are loaded. Summarize key rules to the user:
   - DOCS.md placement (multi-file dir → own DOCS, single-file dir → parent DOCS)
   - Documentation Tree requirement (only when sub-DOCS exist)
   - Module format (Purpose/Input/Output)
   - Directories exempt from DOCS

**STOP.** Wait for user to confirm before proceeding.

---

## Phase 2: Map Current State

1. Find all existing DOCS.md and README.md files:
   ```bash
   find . -name "DOCS.md" -o -name "README.md" | grep -v venv | grep -v .git/ | grep -v .beads | grep -v .claude | grep -v node_modules | sort
   ```

2. Find all directories with Python/Shell modules:
   ```bash
   for dir in $(find . -name "*.py" -o -name "*.sh" | grep -v venv | grep -v __pycache__ | grep -v .git | grep -v .beads | grep -v .claude | xargs -I{} dirname {} | sort -u); do
     count=$(find "$dir" -maxdepth 1 \( -name "*.py" -o -name "*.sh" \) | wc -l | tr -d ' ')
     has_docs=""
     [ -f "$dir/DOCS.md" ] && has_docs="DOCS.md "
     [ -f "$dir/README.md" ] && has_docs="${has_docs}README.md"
     [ -z "$has_docs" ] && has_docs="NO DOC"
     echo "$dir ($count files) → $has_docs"
   done
   ```

3. Present findings as a table:

| Directory | Module Count | Has Doc? | Expected Doc Location | Status |
|---|---|---|---|---|
| `src/module/` | 5 | DOCS.md | `src/module/DOCS.md` | OK |
| `dev/suite/` | 1 | README.md | Parent DOCS | WRONG TYPE + WRONG LOCATION |
| `dev/other/` | 3 | NO DOC | `dev/other/DOCS.md` | MISSING |

**Status categories:**
- **OK** — Correct type, correct location
- **WRONG TYPE** — Has README.md but content is module docs (should be DOCS.md)
- **WRONG LOCATION** — Single-file dir has own DOCS but should be in parent
- **MISSING** — No documentation at all
- **ORPHAN** — DOCS/README exists but no modules in directory (may be stale)

4. Check each existing DOCS.md for:
   - Does it have a Documentation Tree section? (only required if sub-DOCS exist below this dir)
   - Does it document all modules in the directory?
   - Are any documented modules missing from disk (stale entries)?
   - For dev/ directories: does the DOCS content match the documentation rules format?
     - **Suite modules** (benchmarks, evals): Purpose, Usage, CLI flags, Expected output
     - **Investigation modules** (bug/problem dirs): Problem, Investigation, Hypotheses, Scripts
     - **CRITICAL: Do NOT invent dev/ content.** If investigation sections (Problem, Hypotheses, External Research) are missing, flag as MISSING — do NOT hallucinate a narrative. Only document what is verifiable in the code and repo. Scripts without investigation context get the suite format (Purpose + Usage only).

5. Check CLAUDE.md Template Structure:
   - Has `## Sources` section with reference to `sources/sources.md` (NOT inline table)
   - Has `## Pipeline Components` section
   - Has `### Key Files` section (under Pipeline Components)
   - Has `## Project Structure` section with complete tree
   - NO behavioral rules in CLAUDE.md (flag `## Worker Rules`, `## Startup`, or similar)
   - Project Structure tree matches actual directories on disk

6. Check decisions/ (if directory exists):
   - For each decision file: does the documented configuration match the current code?
   - Compare claims in decisions/ against actual source files (settings.yml, *.py config constants)
   - Flag as DRIFT when decision file states X but code shows Y
   - Present drift findings in a table:

| Decision File | Claim | Actual (source file) | Status |
|---|---|---|---|
| search01_engines.md | "DDG weight=1" | settings.yml: DDG disabled | DRIFT |

7. Check sources/:
   - `sources/sources.md` exists
   - If project has `decisions/`: Sources table has `Pipeline Steps` column referencing decision file prefixes
   - CLAUDE.md Sources section is just a reference link, not an inline table

8. Check dev/ Convention:
   - No `debug/` directory at project root
   - If `decisions/` has files: dev/ sub-dirs are grouped by pipeline stage (match decisions/ prefixes)
   - Every decision file has at least one corresponding dev/ sub-directory
   - DOCS.md exists at pipeline-stage level dirs inside dev/

   Present dev/decisions mapping as a table:

   | Decision File | Expected dev/ Dir | Actual | Status |
   |---|---|---|---|
   | `index01_chunking.md` | `dev/indexing/chunking_eval/` | exists | OK |
   | `retrieval03_fusion.md` | `dev/retrieval/fusion/` | missing | MISSING |

10. Dead Structure Check — files and directories that don't belong anywhere:

   **Root-level files:** List all files at project root. Flag anything that is NOT one of the standard project files (CLAUDE.md, README.md, requirements.txt, pyproject.toml, Makefile, .gitignore, .env*, workflow.py/main.py/app.py, or files explicitly in CLAUDE.md Key Files). A file at root that doesn't appear in CLAUDE.md and isn't a standard entry point is a candidate.

   **Directories with no modules and no exempt status:** Find directories that contain no .py/.sh files, no DOCS.md, and are not in the exempt list (data/, decisions/, sources/, .claude/, .beads/, venv/, __pycache__, .git). These may be stale or abandoned.

   ```bash
   # Root-level .md files that aren't standard
   for f in *.md; do
     [[ "$f" == "CLAUDE.md" || "$f" == "README.md" || "$f" == "CHANGELOG.md" || "$f" == "CONTRIBUTING.md" ]] && continue
     echo "ROOT MD: $f — check if still relevant"
   done

   # Directories with no Python/shell modules and no exempt reason
   for dir in */; do
     dir="${dir%/}"
     [[ "$dir" =~ ^(venv|.git|.beads|.claude|__pycache__|node_modules|data|decisions|sources|not_working|repo)$ ]] && continue
     count=$(find "$dir" -name "*.py" -o -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')
     [ "$count" -eq 0 ] && echo "EMPTY DIR: $dir — no modules, check if still needed"
   done
   ```

   **Flag criteria:**
   - **ORPHANED FILE** — Root-level .md file not referenced in CLAUDE.md and not a standard doc
   - **ORPHANED DIR** — Directory with no modules, not in exempt list, no clear ongoing purpose
   - **STALE REFERENCE** — A directory or file mentioned in DOCS/CLAUDE.md that no longer exists on disk

   Present as a table:

   | Item | Type | Referenced In | Status |
   |------|------|---------------|--------|
   | `AGENTS.md` | Root file | nowhere | ORPHANED FILE |
   | `scratch/` | Directory | nowhere | ORPHANED DIR |

   **Do NOT delete anything** — flag for user decision only.

9. Check shared rules symlinks:
   ```bash
   # Find broken symlinks
   find .claude/rules -type l ! -exec test -e {} \; -print 2>/dev/null

   # Check expected symlinks exist
   for f in code-organization.md code-standards.md documentation.md decisions.md dev-convention.md; do
     readlink ".claude/rules/$f" 2>/dev/null || echo "NOT SYMLINK: $f"
   done

   # MCP projects also need:
   for f in mcp-integration.md server-pattern.md testing.md tool-design.md; do
     readlink ".claude/rules/$f" 2>/dev/null || echo "NOT SYMLINK: $f"
   done
   ```
   - Flag broken symlinks
   - Flag shared rules files that are local copies instead of symlinks

**STOP.** Present full findings to user. Wait for confirmation before proceeding.

---

## Phase 3: Plan Fixes

Based on Phase 2 findings, create a fix plan:

### Actions to take:

1. **CREATE** — New DOCS.md files for undocumented directories
2. **RENAME** — README.md → DOCS.md where wrong type is used for module docs
3. **MOVE** — Content from single-file-dir DOCS to parent DOCS
4. **DELETE** — Old README.md files after content migrated to parent DOCS
5. **UPDATE** — Existing DOCS.md missing modules, missing tree sections, stale entries
6. **UPDATE CLAUDE.md** — Missing sections, inline sources, behavioral rules to extract, stale project structure tree
7. **CREATE sources/** — Missing `sources/sources.md`
8. **CREATE decisions/** — Missing `decisions/` directory
9. **CREATE dev/** — Missing dev/ sub-dirs for decision files
10. **FIX SYMLINKS** — Broken or missing shared rules symlinks
11. **EXTRACT** — Behavioral rules from CLAUDE.md to `.claude/rules/` with appropriate `paths:` trigger

Write the plan to `.claude/plans/` as a plan file.

**STOP.** Wait for user approval.

---

## Phase 4: Execute

Dispatch a worker for the doc changes. The worker prompt MUST include:
- Full list of files to create/rename/delete/update
- For each new DOCS.md: which .py files to read for Purpose/Input/Output
- The documentation format rules (from Phase 1)
- Reference to existing DOCS.md files that follow the correct pattern

**Glue work (Opus after merge):**
- Update `.claude/rules/documentation.md` if the review revealed rule gaps
- Update `CLAUDE.md` project structure

---

## Phase 5: Verify

After worker merge, verify:

```bash
# Every multi-file dir has own DOCS.md
for dir in $(find . -name "*.py" -o -name "*.sh" | grep -v venv | grep -v __pycache__ | grep -v .git | grep -v .beads | grep -v .claude | xargs -I{} dirname {} | sort -u); do
  count=$(find "$dir" -maxdepth 1 \( -name "*.py" -o -name "*.sh" \) | wc -l | tr -d ' ')
  if [ "$count" -gt 1 ]; then
    [ ! -f "$dir/DOCS.md" ] && echo "MISSING: $dir ($count files, no DOCS.md)"
  fi
done

# No README.md with module docs in dev/
find dev/ -name "README.md" -exec echo "CHECK: {}" \;

# Every DOCS.md has a Documentation Tree section
find . -name "DOCS.md" -not -path '*/venv/*' -not -path '*/.git/*' | while read f; do
  grep -q "Documentation Tree" "$f" || echo "NO TREE: $f"
done
```

Report results to user.

---

## Autonomous Mode

When invoked from a worker prompt (e.g., docs-review command), ignore all STOP markers. Execute Phases 1→2→3→4→5 without interruption:

1. Read rules (Phase 1)
2. Map current state (Phase 2)
3. Write findings to WORKER_REPORT.md (Phase 2 output format)
4. If NEEDS FIXES: implement all fixes immediately (Phase 4)
5. Update WORKER_REPORT.md with final results
6. Commit all changes (not WORKER_REPORT.md)

**Key:** In autonomous mode, the worker does review AND fix in one pass. No separate fix worker needed.
