# src/git/

## Role

Three-phase git workflow utilities for pre-commit checks, staging, and post-commit verification. Touch this package when modifying how files are classified before staging, how hook health is detected, or how the working tree is verified after a commit. Do NOT touch for project-specific commit conventions — those live in the `tool-use` skill (`#### Git CLI` subsection).

## Public Interface

`__init__.py` is empty. Modules are invoked as `python3 -m src.git.<module>` entry points. Active entry paths: `~/.local/bin/git-check` → `python3 -m src.git.check`; `~/.local/bin/gcommit` → `python3 -m src.git.commit`.

## Modules

### check.py (199 LOC)

**Purpose:** Pre-commit analysis + optional auto-staging. Classifies files into staged/unstaged/untracked/skipped, detects new imports in unstaged .py files, checks hook health.
**Reads:** Repository files, git status/diff output, `.git/hooks/pre-commit` content.
**Writes:** stdout (structured report: STAGED, UNSTAGED, UNTRACKED, SKIP, IMPORT WARNINGS, DIFF SUMMARY, HOOK STATUS). With `--auto-stage`: git index via `git add`.
**Called by:** `~/.local/bin/git-check`.
**Calls out:** subprocess (git commands).

---

### commit.py (61 LOC)

**Purpose:** One-call stage-all + commit, worktree-correct (no path resolution/stripping — `repo_path` used as-is, `git` itself resolves the right worktree branch). Reuses `parse_status`/`classify_files`/`stage_all` from `check.py` — single source of truth for `SKIP_PATTERNS`.
**Reads:** git status output (via `check.py` primitives).
**Writes:** git index via `stage_all`, git commit via `do_commit`. stdout (staged/skipped summary + git commit output).
**Called by:** `~/.local/bin/gcommit`.
**Calls out:** subprocess (git commands); `src/git/check.py` (`parse_status`, `classify_files`, `stage_all`).

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
python3 -m src.git.commit "<message>" [repo-path]   # stage-all + commit, one call
```

## Gotchas

`check.py`'s `resolve_project_path` (in the `bin/git-check` wrapper, not this module) strips `.claude/worktrees/…` back to the parent repo — worktree-hostile. `commit.py`'s wrapper (`bin/gcommit`) deliberately does NOT do this: `repo_path` defaults to the caller's `pwd` (captured before the wrapper `cd`s into the plugin root) and is passed through unresolved — `git` itself finds the correct worktree branch from `cwd`.
