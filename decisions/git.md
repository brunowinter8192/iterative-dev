# Git Automation

## Status Quo (IST)

Three-phase git workflow used by the `git-committer` agent:

**Phase 1 — check.py (Pre-Commit):**
- Parses `git status --porcelain` into staged/unstaged/untracked/skipped
- SKIP_PATTERNS: `.beads/`, `.DS_Store`, `.env`, `credentials`, `.claude/worktrees/`
- Detects new imports in unstaged files (potential missing module warnings)
- Checks pre-commit hook for known broken patterns (e.g., `bd sync` → should be `bd export`)
- Outputs structured report with sections: STAGED, UNSTAGED, UNTRACKED, SKIP, IMPORT WARNINGS, DIFF SUMMARY, HOOK STATUS

**Phase 2 — staged.py (Staging Verification):**
- Confirms all relevant files are staged (same SKIP_PATTERNS)
- Reports COMPLETE/INCOMPLETE status
- Provides `git diff --cached --stat` summary for commit message generation

**Phase 3 — post.py (Post-Commit):**
- Confirms working tree is clean after commit
- Shows last commit hash + message
- Reports CLEAN/DIRTY with remaining uncommitted changes (excluding SKIP_PATTERNS)

**Usage:** `python3 -m src.git.<module> <repo-path>`

**Files:** `src/git/check.py`, `src/git/staged.py`, `src/git/post.py`

## Recommendation (SOLL)

Pending — needs evaluation.

## Offene Fragen

- SKIP_PATTERNS duplicated across all 3 files — could be extracted to shared constant.
- `run()` helper duplicated across all 3 files — same extraction candidate.
