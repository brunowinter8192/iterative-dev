"""
Post-commit verification: confirms working tree is clean after commit.
Usage: python3 -m src.git.post <repo-path>
"""

# INFRASTRUCTURE

import logging
import subprocess
import sys

logger = logging.getLogger(__name__)

SKIP_PATTERNS = [".beads/", ".DS_Store", ".env", "credentials", ".claude/worktrees/"]


# ORCHESTRATOR

def post_workflow(repo_path: str) -> None:
    logger.info("post_workflow repo=%s", repo_path)
    commit_hash = get_last_commit(repo_path)
    remaining = get_remaining_changes(repo_path)
    print_report(commit_hash, remaining)


# FUNCTIONS

# Run git command and return stdout
def run(cmd: list, cwd: str) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    return result.stdout.strip()


# Get last commit hash and message
def get_last_commit(repo_path: str) -> str:
    return run(["git", "log", "--oneline", "-1"], repo_path)


# Get remaining uncommitted changes (excluding SKIP)
def get_remaining_changes(repo_path: str) -> list[str]:
    raw = run(["git", "status", "--porcelain"], repo_path)
    remaining = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        path = line[3:]
        if not any(p in path for p in SKIP_PATTERNS):
            remaining.append(line)
    return remaining


# Print post-commit status report
def print_report(commit_hash: str, remaining: list[str]):
    print("=== POST-COMMIT STATUS ===")

    if commit_hash:
        print(f"  Last commit: {commit_hash}")

    if not remaining:
        print("  CLEAN: nothing to commit, working tree clean")
    else:
        print("  DIRTY: uncommitted changes remain — stage and commit these:")
        for line in remaining:
            print(f"    {line}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 -m src.git.post <repo-path>")
        sys.exit(1)
    post_workflow(sys.argv[1])
