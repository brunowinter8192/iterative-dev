# INFRASTRUCTURE
import re
from pathlib import Path

FILE_EXTENSIONS = {
    "py", "sh", "md", "json", "jsonl", "yaml", "yml", "txt", "toml", "cfg", "ini",
    "log", "pid", "flock", "lock", "html", "js", "ts", "css", "csv", "png", "env",
}

PY_FUNCTION_RE = re.compile(r"^\s*(?:async\s+)?def\s+(\w+)", re.MULTILINE)
SH_FUNCTION_RE = re.compile(r"^\s*(?:function\s+)?([A-Za-z_]\w*)\s*\(\)\s*\{?", re.MULTILINE)
PY_CLASS_RE = re.compile(r"^\s*class\s+(\w+)", re.MULTILINE)
PY_CONSTANT_RE = re.compile(r"^([A-Z][A-Z0-9_]{3,})\s*(?::[^=\n]+)?=", re.MULTILINE)
SH_CONSTANT_RE = re.compile(
    r"^\s*(?:export\s+|readonly\s+|local\s+|declare\s+(?:-\w+\s+)?)?([A-Z][A-Z0-9_]{3,})=",
    re.MULTILINE,
)
PY_ENV_RE = re.compile(r"""(?:environ(?:\.\w+)?\s*[\(\[]|getenv\s*\()\s*['"]([A-Z][A-Z0-9_]{3,})['"]""")
SH_ENV_RE = re.compile(r"\bexport\s+([A-Z][A-Z0-9_]{3,})\b|\$\{([A-Z][A-Z0-9_]{3,}):[-?=+]")
TOKEN_RE = re.compile(r"[\w./-]+")

# FUNCTIONS

def build_symbol_index(source_files: list[Path]) -> tuple[set[str], set[str], set[str]]:
    functions: set[str] = set()
    constants: set[str] = set()
    owners: set[str] = set()
    env_names: set[str] = set()
    for source in source_files:
        text = source.read_text()
        owners.add(source.stem)
        if source.suffix == ".py":
            functions.update(PY_FUNCTION_RE.findall(text))
            owners.update(PY_CLASS_RE.findall(text))
            constants.update(PY_CONSTANT_RE.findall(text))
            env_names.update(PY_ENV_RE.findall(text))
        else:
            functions.update(SH_FUNCTION_RE.findall(text))
            constants.update(SH_CONSTANT_RE.findall(text))
            env_names.update(name for pair in SH_ENV_RE.findall(text) for name in pair if name)
    return functions, constants - env_names, owners

def find_module_function_tokens(span: str, owners: set[str]) -> list[str]:
    return [t for t in TOKEN_RE.findall(span) if is_module_function_reference(t, owners)]

def is_module_function_reference(token: str, owners: set[str]) -> bool:
    token = token.rstrip(".")
    if "." not in token:
        return False
    prefix, suffix = token.rsplit(".", 1)
    if not prefix or not re.fullmatch(r"[A-Za-z_]\w*", suffix):
        return False
    if suffix.lower() in FILE_EXTENSIONS:
        return False
    return prefix.split("/")[-1] in owners
