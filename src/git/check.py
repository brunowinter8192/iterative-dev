"""
Pre-commit check: staged/unstaged/untracked files, hook status, import warnings.
Usage: python3 -m src.git.check <repo-path>
"""

# INFRASTRUCTURE

import subprocess
import sys
import os

SKIP_PATTERNS = [".beads/", ".DS_Store", ".env", "credentials", ".claude/worktrees/"]

BROKEN_HOOK_PATTERNS = [
    ("bd sync", "BROKEN: uses 'bd sync' — run 'bd export' instead"),
]


# ORCHESTRATOR

def check_workflow(repo_path: str) -> None:
    status_lines = parse_status(repo_path)
    staged, unstaged, untracked, skipped = classify_files(status_lines)
    import_warnings = find_import_warnings(repo_path, unstaged)
    hook_status = check_hook(repo_path)
    diff_staged = run(["git", "diff", "--cached", "--stat"], repo_path)
    diff_unstaged = run(["git", "diff", "--stat"], repo_path)
    print_report(staged, unstaged, untracked, skipped, import_warnings, hook_status, diff_staged, diff_unstaged)


# FUNCTIONS

# Run git command and return stdout
def run(cmd: list, cwd: str) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    return result.stdout.strip()


# Parse git status --porcelain output into raw lines
def parse_status(repo_path: str) -> list[tuple[str, str]]:
    raw = run(["git", "status", "--porcelain"], repo_path)
    lines = []
    for line in raw.splitlines():
        if line.strip():
            xy = line[:2]
            path = line[3:]
            lines.append((xy, path))
    return lines


# Classify files into staged/unstaged/untracked/skipped
def classify_files(lines: list[tuple[str, str]]) -> tuple[list, list, list, list]:
    staged, unstaged, untracked, skipped = [], [], [], []
    for xy, path in lines:
        if any(p in path for p in SKIP_PATTERNS):
            skipped.append((xy, path))
            continue
        x, y = xy[0], xy[1]
        if xy == "??":
            untracked.append(path)
        else:
            if x not in (" ", "?"):
                staged.append((xy, path))
            if y not in (" ", "?"):
                unstaged.append((xy, path))
    return staged, unstaged, untracked, skipped


# Check new imports in unstaged files for untracked module warnings
def find_import_warnings(repo_path: str, unstaged: list) -> list[str]:
    if not unstaged:
        return []
    paths = [p for _, p in unstaged]
    diff = run(["git", "diff"] + paths, repo_path)
    warnings = []
    for line in diff.splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            stripped = line[1:].strip()
            if stripped.startswith("import ") or stripped.startswith("from "):
                warnings.append(stripped)
    return warnings


# Check pre-commit hook for broken patterns
def check_hook(repo_path: str) -> str:
    hook_path = os.path.join(repo_path, ".git", "hooks", "pre-commit")
    if not os.path.exists(hook_path):
        return "NONE"
    with open(hook_path) as f:
        content = f.read()
    for pattern, message in BROKEN_HOOK_PATTERNS:
        if pattern in content:
            return f"WARNING: {message}"
    return "OK"


# Print structured report
def print_report(staged, unstaged, untracked, skipped, import_warnings, hook_status, diff_staged, diff_unstaged):
    _section("STAGED")
    if staged:
        for xy, p in staged:
            print(f"  {xy}  {p}")
    else:
        print("  (none)")

    _section("UNSTAGED")
    if unstaged:
        for xy, p in unstaged:
            print(f"  {xy}  {p}")
    else:
        print("  (none)")

    _section("UNTRACKED")
    if untracked:
        for p in untracked:
            print(f"  {p}")
    else:
        print("  (none)")

    _section("SKIP — do not stage")
    if skipped:
        for xy, p in skipped:
            print(f"  {p}")
    else:
        print("  (none)")

    if import_warnings:
        _section("IMPORT WARNINGS — check if imported module is untracked")
        for w in import_warnings:
            print(f"  {w}")

    if diff_unstaged:
        _section("DIFF SUMMARY (unstaged)")
        print(diff_unstaged)

    if diff_staged:
        _section("DIFF SUMMARY (already staged)")
        print(diff_staged)

    _section("HOOK STATUS")
    print(f"  pre-commit: {hook_status}")


def _section(title: str):
    print(f"\n=== {title} ===")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 -m src.git.check <repo-path>")
        sys.exit(1)
    check_workflow(sys.argv[1])
