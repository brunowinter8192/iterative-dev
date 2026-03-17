Spawn a Sonnet worker that reviews the project's documentation structure, then Opus reviews the assessment and dispatches fixes if needed.

Input: $ARGUMENTS
Format: `<project_path>` (optional, defaults to current project)
Example: `/docs-review ~/Documents/ai/Trading/TradBot`

If $ARGUMENTS is empty, use the current working directory.

PLUGIN_DIR: the iterative-dev plugin root (resolve from this command's path: go up one level from commands/)

---

## Phase 1: Spawn Review Worker

Write the worker prompt to `/tmp/spawn-worker-docs-review.md`:

```markdown
# Task: Documentation Structure Review

## FIRST ACTION
1. Run /iterative-dev:worker-rules
2. Read .claude/rules/documentation.md — this defines the project's documentation standard

If .claude/rules/documentation.md does NOT exist, write WORKER_REPORT.md with:
STOP: No documentation rules found at .claude/rules/documentation.md. Cannot review without standard.
Then exit.

## Review Steps

### 1. Map Documentation Standard
Read .claude/rules/documentation.md fully. Extract:
- DOCS.md placement rules (multi-file vs single-file directories)
- Module documentation format
- Documentation Tree requirements
- Directories exempt from DOCS

### 2. Map Current State
Run these commands to build the full picture:

Find all doc files:
find . -name "DOCS.md" -o -name "README.md" | grep -v venv | grep -v .git/ | grep -v .beads | grep -v .claude | grep -v node_modules | sort

Find all directories with modules and their doc status:
for dir in $(find . \( -name "*.py" -o -name "*.sh" \) -not -path '*/venv/*' -not -path '*/__pycache__/*' -not -path '*/.git/*' -not -path '*/.beads/*' -not -path '*/.claude/*' -exec dirname {} \; | sort -u); do
  count=$(find "$dir" -maxdepth 1 \( -name "*.py" -o -name "*.sh" \) | wc -l | tr -d ' ')
  has_docs=""
  [ -f "$dir/DOCS.md" ] && has_docs="DOCS.md "
  [ -f "$dir/README.md" ] && has_docs="${has_docs}README.md"
  [ -z "$has_docs" ] && has_docs="NO DOC"
  echo "$dir ($count files) → $has_docs"
done

### 3. Evaluate Against Standard
For each directory with modules, check:
- [ ] Correct doc type (DOCS.md not README.md for module docs)
- [ ] Correct location (single-file dirs documented in parent, multi-file dirs have own DOCS)
- [ ] Module format correct (Purpose/Input/Output)
- [ ] Documentation Tree section present
- [ ] All modules documented (no missing entries)
- [ ] No stale entries (documented modules that no longer exist on disk)

For CLAUDE.md, check:
- [ ] References data/ and decisions/ with purpose (if they exist)
- [ ] Project Structure tree is complete and current

### 4. Write Assessment
Write WORKER_REPORT.md with:

# Worker Report: docs-review

## Task
Documentation structure review against .claude/rules/documentation.md

## Assessment

### Status: CLEAN / NEEDS FIXES

### Findings Table
| Directory | Module Count | Current Doc | Expected | Status | Issue |
|---|---|---|---|---|---|

### Files to CREATE
(list with expected content description)

### Files to RENAME
(README.md → DOCS.md conversions)

### Files to MOVE
(single-file-dir docs → parent docs)

### Files to DELETE
(old READMEs after migration)

### Files to UPDATE
(missing modules, missing trees, stale entries)

### CLAUDE.md Issues
(missing references, stale tree)

## Open Issues
None / list of ambiguities that need user decision
```

Spawn the worker:

```bash
source $PLUGIN_DIR/src/spawn/tmux_spawn.sh
spawn_claude_worker_from_file "workers" "docs-review" "<project_path>" "sonnet" "/tmp/spawn-worker-docs-review.md"
```

Report: "Worker docs-review gestartet. Warte auf Assessment."

**STOP.** Wait for worker completion notification.

---

## Phase 2: Review Assessment

When worker completes:

1. Read `WORKER_REPORT.md` from the worktree (or project dir if no worktree)
2. Verify key claims:
   - Spot-check 2-3 directories the worker flagged as MISSING or WRONG
   - Spot-check 1-2 directories the worker marked as OK
3. Present summary to user:
   - Status: CLEAN or NEEDS FIXES
   - Number of issues by category (CREATE/RENAME/MOVE/DELETE/UPDATE)
   - Any items you disagree with from the worker's assessment

If **CLEAN**: Report to user, cleanup worktree, done.

If **NEEDS FIXES**: Proceed to Phase 3.

---

## Phase 3: Dispatch Fix Worker

Build a fix prompt based on the verified assessment. Write to `/tmp/spawn-worker-docs-fix.md`:

The fix prompt MUST include:
- Exact list of files to create/rename/delete/update (from Phase 2 verified assessment)
- For each new DOCS.md: which .py/.sh files to read for Purpose/Input/Output content
- The module documentation format (from .claude/rules/documentation.md)
- Reference to an existing correct DOCS.md in the project as pattern example
- Documentation Tree format and rules

Spawn the fix worker:

```bash
source $PLUGIN_DIR/src/spawn/tmux_spawn.sh
spawn_claude_worker_from_file "workers" "docs-fix" "<project_path_or_worktree>" "sonnet" "/tmp/spawn-worker-docs-fix.md"
```

Report: "Worker docs-fix gestartet mit N Aenderungen."

**STOP.** Wait for worker completion.

---

## Phase 4: Verify & Merge

When fix worker completes:

1. Read WORKER_REPORT.md
2. Run verification:
   ```bash
   # Every multi-file dir has DOCS.md
   for dir in $(find . \( -name "*.py" -o -name "*.sh" \) -not -path '*/venv/*' -not -path '*/__pycache__/*' -not -path '*/.git/*' -exec dirname {} \; | sort -u); do
     count=$(find "$dir" -maxdepth 1 \( -name "*.py" -o -name "*.sh" \) | wc -l | tr -d ' ')
     [ "$count" -gt 1 ] && [ ! -f "$dir/DOCS.md" ] && echo "STILL MISSING: $dir"
   done

   # DOCS.md with sub-DOCS has Documentation Tree
   find . -name "DOCS.md" -not -path '*/venv/*' -not -path '*/.git/*' | while read f; do
     dir=$(dirname "$f")
     has_sub_docs=$(find "$dir" -mindepth 2 -name "DOCS.md" -not -path '*/venv/*' | head -1)
     if [ -n "$has_sub_docs" ]; then
       grep -q "Documentation Tree" "$f" || echo "NO TREE (has sub-DOCS): $f"
     fi
   done
   ```
3. If clean: merge worktree branch, cleanup
4. If issues remain: inform user, decide next steps

Glue work (Opus does directly, not via worker):
- Update .claude/rules/documentation.md if review revealed rule gaps
- Update CLAUDE.md project structure if needed
