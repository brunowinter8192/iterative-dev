# INFRASTRUCTURE
import os
from pathlib import Path

from src.docs_drift_check.config import (
    DOC_NAME,
    EXCLUDED_DIR_NAMES,
    EXCLUDED_REL_PREFIXES,
    SOURCE_EXTENSIONS,
)

# FUNCTIONS

def collect_doc_files(root: Path) -> list[Path]:
    return [p for p in _walk_files(root) if p.name == DOC_NAME]

def collect_source_files(root: Path) -> list[Path]:
    return [p for p in _walk_files(root) if p.suffix in SOURCE_EXTENSIONS]

def _walk_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        current = Path(dirpath)
        dirnames[:] = sorted(d for d in dirnames if not _is_excluded_dir(current / d, root))
        files.extend(current / name for name in sorted(filenames))
    return files

def _is_excluded_dir(path: Path, root: Path) -> bool:
    if path.name in EXCLUDED_DIR_NAMES:
        return True
    rel = path.relative_to(root).as_posix()
    return any(rel == prefix or rel.startswith(prefix + "/") for prefix in EXCLUDED_REL_PREFIXES)
