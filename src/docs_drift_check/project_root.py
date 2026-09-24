# INFRASTRUCTURE
import os
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
