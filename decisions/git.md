# Git Automation

## Status Quo (IST)

Three-phase git workflow used by the `git-committer` agent:

**Phase 1 — check.py (Pre-Commit + Auto-Stage):**
- Parses `git status --porcelain` into staged/unstaged/untracked/skipped
- SKIP_PATTERNS: `.beads/`, `.DS_Store`, `.env`, `credentials`, `.claude/worktrees/`
- Detects new imports in unstaged files (potential missing module warnings)
- Checks pre-commit hook for known broken patterns (e.g., `bd sync` → should be `bd export`)
- Outputs structured report with sections: STAGED, UNSTAGED, UNTRACKED, SKIP, IMPORT WARNINGS, DIFF SUMMARY, HOOK STATUS
- `--auto-stage`: stages all UNSTAGED + UNTRACKED (minus SKIP), outputs AUTO-STAGED + DIFF SUMMARY for commit message

**Phase 2 — staged.py (Staging Verification) — retained as fallback:**
- Confirms all relevant files are staged (same SKIP_PATTERNS)
- Reports COMPLETE/INCOMPLETE status
- Provides `git diff --cached --stat` summary for commit message generation
- Not called in normal flow (replaced by `check.py --auto-stage`)

**Phase 3 — post.py (Post-Commit):**
- Confirms working tree is clean after commit
- Shows last commit hash + message
- Reports CLEAN/DIRTY with remaining uncommitted changes (excluding SKIP_PATTERNS)

**Usage:** `python3 -m src.git.<module> <repo-path> [--auto-stage]`

**Files:** `src/git/check.py`, `src/git/staged.py`, `src/git/post.py`

## Recommendation (SOLL)

Auto-stage consolidation: `check.py --auto-stage` replaces manual `git add` + `staged.py` in the normal git-committer flow. Reduces agent tool calls from 6+N to 5-6 per repo. staged.py retained as fallback.

SKIP_PATTERNS + `run()` helper still duplicated across 3 files — acceptable for now (extraction adds complexity without functional benefit).

## Offene Fragen

- None currently.
