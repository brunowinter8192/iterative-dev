Spawn a Sonnet worker that reviews AND fixes the project's documentation structure. Opus verifies after completion.

Input: $ARGUMENTS
Format: `<project_path>` (optional, defaults to current project)
Example: `/docs-review ~/Documents/ai/Trading/TradBot`

If $ARGUMENTS is empty, use the current working directory.

PLUGIN_DIR: the iterative-dev plugin root (resolve from this command's path: go up one level from commands/)

---

## Phase 1: Spawn Worker

Write the worker prompt to `/tmp/spawn-worker-docs-review.md`:

```markdown
# Task: Documentation Structure Review & Fix

## FIRST ACTION
1. Run /iterative-dev:worker-rules
2. Run /iterative-dev:doc-review

**CRITICAL:** This is an autonomous run. Ignore all STOP markers in the doc-review skill. Execute all phases without interruption. You ARE allowed to create and edit DOCS.md files — the docs-review command overrides the default worker-rules prohibition.

## Instructions

1. Follow the doc-review skill phases 1-5 autonomously
2. Map the full documentation state
3. If NEEDS FIXES: implement ALL fixes (create, rename, move, delete, update DOCS.md files)
4. Read source files (*.py, *.sh) to extract Purpose/Input/Output for new DOCS.md entries
5. Use existing DOCS.md files in the project as pattern reference
6. Write WORKER_REPORT.md with findings table AND list of changes made
7. Commit all doc changes (NOT WORKER_REPORT.md)

Documentation rules path: DOCS_RULES_PATH
```

**Before writing the prompt file:** Replace `DOCS_RULES_PATH` with: `<project_path>/.claude/rules/documentation.md`

Spawn the worker:

```bash
source $PLUGIN_DIR/src/spawn/tmux_spawn.sh
spawn_claude_worker_from_file "workers" "docs-review" "<project_path>" "sonnet" "/tmp/spawn-worker-docs-review.md"
```

Report: "Worker docs-review gestartet. Arbeitet autonom durch Review + Fixes."

**STOP.** Wait for worker completion notification.

---

## Phase 2: Verify & Merge

When worker completes:

1. Read `WORKER_REPORT.md` from the worktree (or project dir)
2. Verify key claims:
   - Spot-check 2-3 directories the worker flagged
   - Spot-check 1-2 directories the worker marked as OK
3. Run verification:
   ```bash
   # Every multi-file dir has DOCS.md
   for dir in $(find . \( -name "*.py" -o -name "*.sh" \) -not -path '*/venv/*' -not -path '*/__pycache__/*' -not -path '*/.git/*' -not -path '*/.beads/*' -not -path '*/.claude/*' -exec dirname {} \; | sort -u); do
     count=$(find "$dir" -maxdepth 1 \( -name "*.py" -o -name "*.sh" \) | wc -l | tr -d ' ')
     [ "$count" -gt 1 ] && [ ! -f "$dir/DOCS.md" ] && echo "STILL MISSING: $dir"
   done

   # DOCS.md with sub-DOCS has Documentation Tree
   find . -name "DOCS.md" -not -path '*/venv/*' -not -path '*/.git/*' -not -path '*/.beads/*' -not -path '*/.claude/*' | while read f; do
     dir=$(dirname "$f")
     has_sub_docs=$(find "$dir" -mindepth 2 -name "DOCS.md" -not -path '*/venv/*' | head -1)
     if [ -n "$has_sub_docs" ]; then
       grep -q "Documentation Tree" "$f" || echo "NO TREE (has sub-DOCS): $f"
     fi
   done
   ```
4. If clean: merge worktree branch, cleanup
5. If issues remain: fix directly (Opus glue) or send worker additional instructions via `worker_send`

Glue work (Opus does directly, not via worker):
- Update .claude/rules/documentation.md if review revealed rule gaps
- Update CLAUDE.md project structure if needed
