# src/git/

## Role

Three-phase git workflow utilities for pre-commit checks, staging, and post-commit verification. Touch this package when modifying how files are classified before staging, how hook health is detected, or how the working tree is verified after a commit. Do NOT touch for project-specific commit conventions — those live in the `tool-use` skill (`#### Git CLI` subsection).

## Public Interface

`__init__.py` is empty. Modules are invoked as `python3 -m src.git.<module>` entry points. Active entry path: `~/.local/bin/git-check` → `python3 -m src.git.check`.

## Modules

### check.py (199 LOC)

**Purpose:** Pre-commit analysis + optional auto-staging. Classifies files into staged/unstaged/untracked/skipped, detects new imports in unstaged .py files, checks hook health.
**Reads:** Repository files, git status/diff output, `.git/hooks/pre-commit` content.
**Writes:** stdout (structured report: STAGED, UNSTAGED, UNTRACKED, SKIP, IMPORT WARNINGS, DIFF SUMMARY, HOOK STATUS). With `--auto-stage`: git index via `git add`.
**Called by:** `~/.local/bin/git-check`.
**Calls out:** subprocess (git commands).

---

### staged.py (108 LOC)

**Purpose:** Staging verification — confirms all relevant files are staged, provides diff summary for commit message.
**Reads:** git status --porcelain, git diff --cached output.
**Writes:** stdout (COMPLETE/INCOMPLETE status + staged file list + diff summary).
**Called by:** Retained as fallback; no active caller after migration to `check.py --auto-stage`.
**Calls out:** subprocess (git commands).

---

### post.py (71 LOC)

**Purpose:** Post-commit verification — confirms working tree is clean after commit.
**Reads:** git log, git status output.
**Writes:** stdout (last commit hash + CLEAN/DIRTY status with remaining changes).
**Called by:** No active caller (git-committer.md agent removed).
**Calls out:** subprocess (git commands).

---

## Usage

```bash
python3 -m src.git.check <repo-path>                # analysis only
python3 -m src.git.check <repo-path> --auto-stage   # analysis + stage all (normal flow)
python3 -m src.git.staged <repo-path>               # manual staging verification (fallback)
python3 -m src.git.post <repo-path>
```
