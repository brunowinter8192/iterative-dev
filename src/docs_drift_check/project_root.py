# INFRASTRUCTURE
import os
from pathlib import Path

from src.docs_drift_check.config import ROOT_ENV_VAR

# FUNCTIONS

def resolve_root() -> Path:
    return Path(os.environ.get(ROOT_ENV_VAR) or Path.cwd()).resolve()
