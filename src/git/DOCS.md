# src/git/

## Role

Git workflow utilities: pre-commit classification and staging, and one-call commit. Touch when changing how files are classified before staging or how hook health is detected. Do not touch for project-specific commit conventions; those live in the `tool-use` skill.

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

### commit.py (77 LOC)

**Purpose:** One-call stage-all plus commit, worktree-correct. Reuses the status parsing, classification and staging of `check.py`, keeping one source for the skip list.
**Reads:** git status output (via `check.py`).
**Writes:** git index, git commit; stdout (summary or abort message).
**Called by:** `~/.local/bin/gcommit`.
**Calls out:** subprocess (git commands); `src/git/check.py`.

## State

No shared mutable state. `commit.py` imports the status parsing, classification and staging from `check.py`; nothing else is shared.
