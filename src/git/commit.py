# INFRASTRUCTURE

import argparse
import logging
import os
import subprocess
import sys

from src.git.check import parse_status, classify_files, stage_all

logger = logging.getLogger(__name__)


# ORCHESTRATOR

def commit_workflow() -> None:
    repo_path, message = parse_args()
    logger.info("commit_workflow repo=%s", repo_path)
    status_lines = parse_status(repo_path)
    staged, unstaged, untracked, skipped = classify_files(status_lines)
    auto_staged, stage_errors = stage_all(repo_path, unstaged, untracked)
    if stage_errors:
        abort_on_stage_errors(auto_staged, skipped, stage_errors)
    returncode, output = do_commit(repo_path, message)
    print_commit_report(auto_staged, skipped, output)
    exit_if_failed(returncode)


# FUNCTIONS

def parse_args() -> tuple[str, str]:
    parser = argparse.ArgumentParser(description="Stage all + commit in one call")
    parser.add_argument("message", help="Commit message")
    parser.add_argument("repo_path", nargs="?", default=os.getcwd(), help="Path to git repository (default: cwd)")
    args = parser.parse_args()
    return os.path.abspath(args.repo_path), args.message


def abort_on_stage_errors(auto_staged: list[str], skipped: list, stage_errors: list[str]) -> None:
    print_commit_report(auto_staged, skipped, "")
    print_stage_errors(stage_errors)
    sys.exit(1)


def exit_if_failed(returncode: int) -> None:
    if returncode != 0:
        sys.exit(returncode)


def do_commit(repo_path: str, message: str) -> tuple[int, str]:
    result = subprocess.run(
        ["git", "commit", "-m", message],
        capture_output=True, text=True, cwd=repo_path,
    )
    output = (result.stdout + result.stderr).strip()
    return result.returncode, output


def print_commit_report(staged: list[str], skipped: list, commit_output: str) -> None:
    if staged:
        print(f"staged: {', '.join(staged)}")
    else:
        print("staged: (nothing new)")
    if skipped:
        print(f"skipped: {', '.join(p for _, p in skipped)}")
    print(commit_output)


def print_stage_errors(stage_errors: list[str]) -> None:
    print("stage errors:")
    for e in stage_errors:
        print(f"  {e}")
    print("aborting: staging failed, no commit made")


if __name__ == "__main__":
    commit_workflow()
