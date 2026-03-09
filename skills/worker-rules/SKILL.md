---
name: worker-rules
description: Mandatory rules for workers spawned in git worktrees. Covers worktree isolation (never commit to main) and worker report (WORKER_REPORT.md handoff artifact).
---

# Worker Rules — Worktree Isolation & Report

These rules are MANDATORY for every worker session running in a git worktree.

## 1. Worktree Isolation

You are running in a git worktree — an isolated copy of the repo on a dedicated branch.

### Pre-Edit Check (ONCE, before your first file edit)

```bash
pwd
git branch --show-current
```

- `pwd` must show a path containing `.claude/worktrees/`
- `git branch --show-current` must show your worker branch name (NOT `main`)
- If EITHER check fails: **STOP IMMEDIATELY.** Do not edit any files. Report the error.

### Rules

1. ALL file reads and edits MUST use paths under your worktree directory.
2. NEVER use absolute paths to the main repo (the parent of `.claude/worktrees/`).
3. NEVER checkout, switch to, or commit on `main`.
4. Commit only to YOUR branch.

### Pre-Commit Check (EVERY commit)

Before every `git commit`:

```bash
git branch --show-current
```

- Expected: your worker branch name
- If it shows `main` or anything unexpected: **DO NOT COMMIT.** Something is wrong — stop and report.

## 2. Worker Report (MANDATORY)

Before your **final commit**, create `WORKER_REPORT.md` in the worktree root.

### Template

```markdown
# Worker Report: <worker-name>

## Task
<1-2 sentence summary of what was asked>

## Results
<Concrete findings, what was built/changed/discovered — no vague summaries>

## Files Changed
<List of files created or modified, with one-line description each>

## Open Issues
<Anything that didn't work, needs follow-up, or was out of scope. "None" if clean.>
```

### Rules

- The report is a handoff artifact — the parent session reads it to understand what you did.
- Be concrete: file paths, endpoint URLs, error codes, not "explored various approaches".
- Include the report in your final commit.
