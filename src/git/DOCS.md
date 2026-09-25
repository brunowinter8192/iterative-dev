# src/git/

## Role

Git workflow utility: pre-commit classification and staging. Touch when changing how files are classified before staging or how hook health is detected. Do not touch for project-specific commit conventions; those live in the `tool-use` skill.

## Public Interface

`__init__.py` is empty. Modules are invoked as `python3 -m src.git.<module>` entry points. Active entry path: `~/.local/bin/git-check` → `python3 -m src.git.check`.

## Flow

`repo_path` in → `git status --porcelain[-z]` parsed and classified into staged/unstaged/untracked/skipped → optional staging (`check.py --auto-stage`) → structured report out (stdout, git index).

## Modules

### check.py (225 LOC)

**Purpose:** Pre-commit analysis + optional auto-staging. Classifies files into staged/unstaged/untracked/skipped, detects new imports in unstaged `.py` files, checks hook health.
**Reads:** Repository files, git status/diff output, the target repo's pre-commit hook file (.git/hooks/pre-commit) if present.
**Writes:** stdout (structured report). With `--auto-stage`: git index via `git add`.
**Called by:** `~/.local/bin/git-check`.
**Calls out:** subprocess (git commands).

---

## State

No shared mutable state.
