# src/git/

## Role

Git workflow utilities: pre-commit classification and staging, staging verification, post-commit verification. Touch when changing how files are classified before staging or how hook health is detected. Do not touch for project-specific commit conventions; those live in the `tool-use` skill.

## Public Interface

`__init__.py` is empty. Modules are invoked as `python3 -m src.git.<module>` entry points. Active entry paths: `~/.local/bin/git-check` → `python3 -m src.git.check`; `~/.local/bin/gcommit` → `python3 -m src.git.commit`.

## Flow

`repo_path` in → `git status --porcelain[-z]` parsed and classified into staged/unstaged/untracked/skipped → optional staging (`check.py --auto-stage`, `commit.py` always) → structured report or commit out (stdout, git index, git commit).

## Modules

### check.py (225 LOC)

**Purpose:** Pre-commit analysis + optional auto-staging. Classifies files into staged/unstaged/untracked/skipped, detects new imports in unstaged `.py` files, checks hook health.
**Reads:** Repository files, git status/diff output, the target repo's pre-commit hook file (.git/hooks/pre-commit) if present.
**Writes:** stdout (structured report). With `--auto-stage`: git index via `git add`.
**Called by:** `~/.local/bin/git-check`.
**Calls out:** subprocess (git commands).

---

### commit.py (64 LOC)

**Purpose:** One-call stage-all plus commit, worktree-correct. Reuses the status parsing, classification and staging of `check.py`, keeping one source for the skip list.
**Reads:** git status output (via `check.py`).
**Writes:** git index, git commit; stdout (summary or abort message).
**Called by:** `~/.local/bin/gcommit`.
**Calls out:** subprocess (git commands); `src/git/check.py`.

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

The skip list and the git-invocation and status-parsing helpers are duplicated across `check.py`, `staged.py` and `post.py` rather than shared; `staged.py` and `post.py` keep older non-`-z` copies whose skip lists lack the venv entries. `commit.py` is the only module importing from `check.py`. No runtime-shared state otherwise.
