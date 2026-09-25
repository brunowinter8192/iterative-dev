# INFRASTRUCTURE
import os
import subprocess
from pathlib import Path

DOC_NAME = "DOCS.md"
EXCLUDED_DIR_NAMES = {".git", ".venv", "venv", "node_modules", "__pycache__", "dist", "build"}
EXCLUDED_REL_PREFIXES = (".claude/worktrees", "logs", "src/logs")
SOURCE_EXTENSIONS = {".py", ".sh"}

# FUNCTIONS

def collect_doc_files(root: Path) -> list[Path]:
    return [p for p in _walk_files(root) if p.name == DOC_NAME]

def collect_source_files(root: Path) -> list[Path]:
    return [p for p in _walk_files(root) if p.suffix in SOURCE_EXTENSIONS]

def collect_path_suffixes(root: Path) -> set[str]:
    suffixes: set[str] = set()
    for dirpath, dirnames, filenames in _walk(root):
        for name in list(dirnames) + list(filenames):
            parts = (Path(dirpath) / name).relative_to(root).parts
            suffixes.update("/".join(parts[i:]) for i in range(len(parts)))
    return suffixes

def relative_dir_label(directory: Path, root: Path) -> str:
    return directory.relative_to(root).as_posix()

def _walk_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for dirpath, _, filenames in _walk(root):
        files.extend(Path(dirpath) / name for name in sorted(filenames))
    return files

def _walk(root: Path):
    ignored = _ignored_paths(root)
    for dirpath, dirnames, filenames in os.walk(root):
        current = Path(dirpath)
        dirnames[:] = sorted(d for d in dirnames if not _is_excluded_dir(current / d, root, ignored))
        kept = [name for name in filenames if _rel(current / name, root) not in ignored]
        yield dirpath, dirnames, kept

def _ignored_paths(root: Path) -> set[str]:
    result = subprocess.run(
        ["git", "ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"],
        cwd=root, capture_output=True, text=True, check=True,
    )
    return {entry.rstrip("/") for entry in result.stdout.split("\0") if entry}

def _rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()

def _is_excluded_dir(path: Path, root: Path, ignored: set[str]) -> bool:
    if path.name in EXCLUDED_DIR_NAMES:
        return True
    rel = _rel(path, root)
    if rel in ignored:
        return True
    return any(rel == prefix or rel.startswith(prefix + "/") for prefix in EXCLUDED_REL_PREFIXES)
