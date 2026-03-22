"""
Pre-commit check: staged/unstaged/untracked files, hook status, import warnings.
Usage: python3 -m src.git.check <repo-path> [--auto-stage]
"""

# INFRASTRUCTURE

import argparse
import logging
import subprocess
import os

logger = logging.getLogger(__name__)

SKIP_PATTERNS = [".beads/", ".DS_Store", ".env", "credentials", ".claude/worktrees/", "WORKER_REPORT.md"]

BROKEN_HOOK_PATTERNS = [
    ("bd sync", "BROKEN: uses 'bd sync' — run 'bd export' instead"),
]


# ORCHESTRATOR

def check_workflow(repo_path: str, auto_stage: bool = False) -> None:
    logger.info("check_workflow repo=%s auto_stage=%s", repo_path, auto_stage)
    status_lines = parse_status(repo_path)
    staged, unstaged, untracked, skipped = classify_files(status_lines)
    import_warnings = find_import_warnings(repo_path, unstaged)
    hook_status = check_hook(repo_path)
    diff_staged = run(["git", "diff", "--cached", "--stat"], repo_path)
    diff_unstaged = run(["git", "diff", "--stat"], repo_path)
    print_report(staged, unstaged, untracked, skipped, import_warnings, hook_status, diff_staged, diff_unstaged)

    if auto_stage:
        auto_staged = stage_all(repo_path, unstaged, untracked)
        print_auto_stage_report(auto_staged)
        diff_after = run(["git", "diff", "--cached", "--stat"], repo_path)
        print_diff_summary(diff_after)


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


# For RM entries like 'old -> new', return new path only (the one to git add)
def _extract_stage_path(path: str) -> str:
    if " -> " in path:
        return path.split(" -> ", 1)[1]
    return path


# Stage all unstaged and untracked files (minus SKIP)
def stage_all(repo_path: str, unstaged: list, untracked: list) -> list[str]:
    paths_to_stage = [_extract_stage_path(p) for _, p in unstaged] + untracked
    if not paths_to_stage:
        return []
    for path in paths_to_stage:
        run(["git", "add", path], repo_path)
    return paths_to_stage


# Print auto-staged files report
def print_auto_stage_report(auto_staged: list[str]):
    _section("AUTO-STAGED")
    if auto_staged:
        for p in auto_staged:
            print(f"  {p}")
    else:
        print("  (nothing to stage)")


# Print diff summary after staging
def print_diff_summary(diff: str):
    _section("DIFF SUMMARY — use this for commit message")
    if diff:
        print(diff)
    else:
        print("  (nothing staged)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pre-commit check for git-committer agent")
    parser.add_argument("repo_path", help="Path to git repository")
    parser.add_argument("--auto-stage", action="store_true", help="Stage all unstaged/untracked files (minus SKIP)")
    args = parser.parse_args()
    check_workflow(args.repo_path, auto_stage=args.auto_stage)
