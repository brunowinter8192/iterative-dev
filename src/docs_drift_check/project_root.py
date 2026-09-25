# INFRASTRUCTURE
import os
import subprocess
import sys
from pathlib import Path

ROOT_ENV_VAR = "DOCS_DRIFT_ROOT"

# FUNCTIONS

def resolve_root() -> Path:
    value = os.environ.get(ROOT_ENV_VAR)
    if not value:
        print(f"docs-drift-check: {ROOT_ENV_VAR} is not set; run via bin/docs-drift-check", file=sys.stderr)
        sys.exit(2)
    return Path(value).resolve()

def reject_arguments(args: list[str]) -> None:
    if args:
        print(
            f"docs-drift-check: takes no arguments, the project root is the working directory; got: {' '.join(args)}",
            file=sys.stderr,
        )
        sys.exit(2)

def require_git_repo(root: Path) -> None:
    result = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"], cwd=root, capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"docs-drift-check: {root} is not inside a git repository", file=sys.stderr)
        sys.exit(2)
