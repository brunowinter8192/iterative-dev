# INFRASTRUCTURE
import re
from pathlib import Path

from src.docs_drift_check.markdown_scan import BACKTICK_RE, iter_fields

CROSS_PROJECT_MARKER_RE = re.compile(r"\s\([A-Z][A-Za-z_]+\)\s*$")
ENTRY_TOKEN_RE = re.compile(r"^[\w./-]+$")
FILE_EXTENSION_RE = re.compile(r"\.[A-Za-z]{1,5}$")

# FUNCTIONS

def check_called_by(doc_files: list[Path], root: Path, path_suffixes: set[str]) -> list[str]:
    findings: list[str] = []
    for doc in doc_files:
        rel_doc = doc.relative_to(root).as_posix()
        for lineno, text in iter_fields(doc, "Called by"):
            findings.extend(_check_field(rel_doc, lineno, text, path_suffixes))
    return findings

def _check_field(rel_doc: str, lineno: int, text: str, path_suffixes: set[str]) -> list[str]:
    if not text:
        return [f"`{rel_doc}:{lineno}` Called by is empty (list the callers or flag DEAD CODE)"]
    return [
        f"`{rel_doc}:{lineno}` Called by names `{entry}` which does not exist in the project"
        for entry in _entries(text)
        if _normalize(entry) not in path_suffixes
    ]

def _entries(text: str) -> list[str]:
    entries: list[str] = []
    for span in BACKTICK_RE.findall(text):
        token = _span_token(span)
        if token and token not in entries:
            entries.append(token)
    return entries

def _span_token(span: str) -> str | None:
    if span.startswith(("~/", "/")) or "<" in span or CROSS_PROJECT_MARKER_RE.search(span):
        return None
    token = span.split()[0]
    if not ENTRY_TOKEN_RE.match(token):
        return None
    if "/" in token or FILE_EXTENSION_RE.search(token):
        return token
    return None

def _normalize(entry: str) -> str:
    while entry.startswith(("./", "../")):
        entry = entry.split("/", 1)[1]
    return entry.rstrip("/")
