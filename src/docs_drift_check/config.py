# INFRASTRUCTURE
import re

DOC_NAME = "DOCS.md"
ROOT_ENV_VAR = "DOCS_DRIFT_ROOT"

EXCLUDED_DIR_NAMES = {".git", ".venv", "venv", "node_modules", "__pycache__", "dist", "build"}
EXCLUDED_REL_PREFIXES = (".claude/worktrees", "logs", "src/logs")

SOURCE_EXTENSIONS = {".py", ".sh"}

FILE_EXTENSIONS = {
    "py", "sh", "md", "json", "jsonl", "yaml", "yml", "txt", "toml", "cfg", "ini",
    "log", "pid", "flock", "lock", "html", "js", "ts", "css", "csv", "png", "env",
}

BACKTICK_RE = re.compile(r"`([^`]+)`")
