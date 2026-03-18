Spawn a Sonnet worker that checks all automation files for redundancy, symlink integrity, and project structure compliance. Opus reviews the report with the user.

Input: $ARGUMENTS
Format: `<project_path>` (optional, defaults to current project)
Example: `/rules-check-spawn ~/Documents/ai/Meta/ClaudeCode/MCP/RAG`

If $ARGUMENTS is empty, use the current working directory.

PLUGIN_DIR: the iterative-dev plugin root (resolve from this command's path: go up one level from commands/)

---

## Phase 1: Spawn Worker

Write the worker prompt to `/tmp/spawn-worker-rules-check.md`:

```markdown
# Task: Rules Redundancy & Structure Check

## FIRST ACTION
1. Run /iterative-dev:worker-rules
2. Run /iterative-dev:rules-check

**CRITICAL:** This is an autonomous run. Execute all phases without interruption. You ARE allowed to read files outside the project directory (global rules, shared-rules, plugin cache). Write ONLY RULES_REPORT.md in the project root — do NOT edit any other files.

## Instructions

1. Follow the rules-check skill phases 1-5 autonomously
2. Read ALL automation files listed in Phase 1 of the skill
3. Analyze for redundancy, symlink issues, structure compliance
4. Write RULES_REPORT.md with complete findings
5. Do NOT commit anything — the report is a process artifact

Project path: PROJECT_PATH
```

**Before writing the prompt file:** Replace `PROJECT_PATH` with the resolved project path.

Spawn the worker:

```bash
source $PLUGIN_DIR/src/spawn/tmux_spawn.sh
spawn_claude_worker_from_file "workers" "rules-check" "<project_path>" "sonnet" "/tmp/spawn-worker-rules-check.md"
```

Report: "Worker rules-check gestartet. Analysiert alle Automation Files auf Redundanz."

**STOP.** Wait for worker completion notification.

---

## Phase 2: Review Report

When worker completes:

1. Read `RULES_REPORT.md` from the project root
2. Present findings to user grouped by severity:
   - **DUPLICATE** — exact copies, safe to remove
   - **OVERLAP** — similar rules, needs user decision which to keep
   - **MISPLACED** — content in wrong file, clear fix
   - **STALE** — references to nonexistent paths, safe to remove
   - **Symlink issues** — mechanical fixes
   - **Structure issues** — template compliance
3. For each finding: propose the fix, wait for user GO
4. After user approves: execute fixes (edit files, fix symlinks)
5. Delete RULES_REPORT.md when done
