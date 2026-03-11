"""
Staging verification: confirms all relevant files are staged, provides diff summary for commit message.
Usage: python3 -m src.git.staged <repo-path>
"""

# INFRASTRUCTURE

import subprocess
import sys

SKIP_PATTERNS = [".beads/", ".DS_Store", ".env", "credentials", ".claude/worktrees/"]


# ORCHESTRATOR

def staged_workflow(repo_path: str) -> None:
    status_lines = parse_status(repo_path)
    staged, unstaged, untracked = classify_files(status_lines)
    diff_summary = get_diff_summary(repo_path)
    complete = not unstaged and not untracked
    print_report(staged, unstaged, untracked, complete, diff_summary)


# FUNCTIONS

# Run git command and return stdout
def run(cmd: list, cwd: str) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    return result.stdout.strip()


# Parse git status --porcelain output
def parse_status(repo_path: str) -> list[tuple[str, str]]:
    raw = run(["git", "status", "--porcelain"], repo_path)
    lines = []
    for line in raw.splitlines():
        if line.strip():
            lines.append((line[:2], line[3:]))
    return lines


# Classify into staged/unstaged/untracked (excluding SKIP)
def classify_files(lines: list[tuple[str, str]]) -> tuple[list, list, list]:
    staged, unstaged, untracked = [], [], []
    for xy, path in lines:
        if any(p in path for p in SKIP_PATTERNS):
            continue
        x, y = xy[0], xy[1]
        if xy == "??":
            untracked.append(path)
        else:
            if x not in (" ", "?"):
                staged.append((xy, path))
            if y not in (" ", "?"):
                unstaged.append((xy, path))
    return staged, unstaged, untracked


# Get staged diff summary for commit message generation
def get_diff_summary(repo_path: str) -> str:
    return run(["git", "diff", "--cached", "--stat"], repo_path)


# Print staging report
def print_report(staged, unstaged, untracked, complete, diff_summary):
    print("=== STAGING STATUS ===")
    if complete:
        print("  COMPLETE: all relevant files staged")
    else:
        print("  INCOMPLETE — stage these files before committing:")
        for xy, p in unstaged:
            print(f"    {xy}  {p}  [UNSTAGED]")
        for p in untracked:
            print(f"    ??  {p}  [UNTRACKED]")

    print("\n=== STAGED FILES ===")
    if staged:
        for xy, p in staged:
            print(f"  {xy}  {p}")
    else:
        print("  (none)")

    if diff_summary:
        print("\n=== DIFF SUMMARY — use this for commit message ===")
        print(diff_summary)
    else:
        print("\n=== DIFF SUMMARY ===")
        print("  (nothing staged)")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 -m src.git.staged <repo-path>")
        sys.exit(1)
    staged_workflow(sys.argv[1])
