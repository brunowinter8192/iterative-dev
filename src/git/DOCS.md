# src/git/

## Role

Three-phase git workflow utilities for pre-commit checks, staging, and post-commit verification. Touch this package when modifying how files are classified before staging, how hook health is detected, or how the working tree is verified after a commit. Do NOT touch for project-specific commit conventions — those live in the `tool-use` skill (`#### Git CLI` subsection).

## Public Interface

`__init__.py` is empty. Modules are invoked as `python3 -m src.git.<module>` entry points. Active entry paths: `~/.local/bin/git-check` → `python3 -m src.git.check`; `~/.local/bin/gcommit` → `python3 -m src.git.commit`.

## Flow

`repo_path` in → `git status --porcelain[-z]` parsed and classified into staged/unstaged/untracked/skipped → optional staging (`check.py --auto-stage`, `commit.py` always) → structured report or commit out (stdout, git index, git commit).

## Modules

### check.py (223 LOC)

**Purpose:** Pre-commit analysis + optional auto-staging. Classifies files into staged/unstaged/untracked/skipped, detects new imports in unstaged `.py` files, checks hook health.
**Reads:** Repository files, git status/diff output, `.git/hooks/pre-commit` content.
**Writes:** stdout (structured report). With `--auto-stage`: git index via `git add`.
**Called by:** `~/.local/bin/git-check`.
**Calls out:** subprocess (git commands).

---

### commit.py (64 LOC)

**Purpose:** One-call stage-all + commit, worktree-correct. Reuses `parse_status`/`classify_files`/`stage_all` from `check.py` — single source of truth for `SKIP_PATTERNS`.
**Reads:** git status output (via `check.py` primitives).
**Writes:** git index via `stage_all`, git commit via `do_commit`; stdout (summary or abort message).
**Called by:** `~/.local/bin/gcommit`.
**Calls out:** subprocess (git commands); `src/git/check.py` (`parse_status`, `classify_files`, `stage_all`).

---

### staged.py (97 LOC)

**Purpose:** Staging verification — confirms all relevant files are staged, provides diff summary for commit message.
**Reads:** git status --porcelain, git diff --cached output.
**Writes:** stdout (COMPLETE/INCOMPLETE status + staged file list + diff summary).
**Called by:** Retained as fallback; no active caller after migration to `check.py --auto-stage`.
**Calls out:** subprocess (git commands).

---

### post.py (62 LOC)

**Purpose:** Post-commit verification — confirms working tree is clean after commit.
**Reads:** git log, git status output.
**Writes:** stdout (last commit hash + CLEAN/DIRTY status with remaining changes).
**Called by:** No active caller (git-committer.md agent removed).
**Calls out:** subprocess (git commands).

## State

`SKIP_PATTERNS` and the `run()`/`parse_status()`/`classify_files()` primitives are duplicated across `check.py`, `staged.py`, and `post.py` (`staged.py`/`post.py` keep their own non-`-z` copies) rather than shared — `commit.py` is the one module that imports `check.py`'s copies directly. No runtime-shared state otherwise.
