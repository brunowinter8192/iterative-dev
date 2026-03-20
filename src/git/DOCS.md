# src/git/

Three-phase git workflow for the git-committer agent.

## check.py

**Purpose:** Pre-commit analysis — classifies files into staged/unstaged/untracked/skipped, detects new imports, checks hook health.
**Input:** Repository path.
**Output:** Structured report (STAGED, UNSTAGED, UNTRACKED, SKIP, IMPORT WARNINGS, DIFF SUMMARY, HOOK STATUS).

## staged.py

**Purpose:** Staging verification — confirms all relevant files are staged, provides diff summary for commit message.
**Input:** Repository path.
**Output:** COMPLETE/INCOMPLETE status + staged file list + diff summary.

## post.py

**Purpose:** Post-commit verification — confirms working tree is clean after commit.
**Input:** Repository path.
**Output:** Last commit hash + CLEAN/DIRTY status with remaining changes.

## Usage

```bash
python3 -m src.git.check <repo-path>
python3 -m src.git.staged <repo-path>
python3 -m src.git.post <repo-path>
```
