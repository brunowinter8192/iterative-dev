# INFRASTRUCTURE
import re
from pathlib import Path

from src.docs_drift_check.markdown_scan import iter_backtick_lines
from src.docs_drift_check.symbols import find_module_function_tokens

ALL_CAPS_RE = re.compile(r"\b[A-Z][A-Z0-9_]{3,}\b")
FLAG_METAVAR_RE = re.compile(r"--[\w-]+[ =]+([A-Z][A-Z0-9_]{3,})\b")
CALL_RE = re.compile(r"\b([A-Za-z_]\w*)\(")

# FUNCTIONS

def check_function_references(
    doc_files: list[Path], root: Path, functions: set[str], owners: set[str]
) -> list[str]:
    findings: list[str] = []
    for doc in doc_files:
        rel_doc = doc.relative_to(root).as_posix()
        for lineno, spans in iter_backtick_lines(doc):
            hits = _unique(hit for span in spans for hit in _function_hits(span, functions, owners))
            findings.extend(f"`{rel_doc}:{lineno}` function-level reference `{symbol}`" for symbol in hits)
    return findings

def check_constant_references(doc_files: list[Path], root: Path, constants: set[str]) -> list[str]:
    findings: list[str] = []
    for doc in doc_files:
        rel_doc = doc.relative_to(root).as_posix()
        for lineno, spans in iter_backtick_lines(doc):
            hits = _unique(hit for span in spans for hit in _constant_hits(span, constants))
            findings.extend(f"`{rel_doc}:{lineno}` constant reference `{symbol}`" for symbol in hits)
    return findings

def _function_hits(span: str, functions: set[str], owners: set[str]) -> list[str]:
    module_refs = find_module_function_tokens(span, owners)
    covered = {ref.rstrip(".").rsplit(".", 1)[-1] for ref in module_refs}
    hits = list(module_refs)
    hits.extend(
        f"{name}()" for name in CALL_RE.findall(span) if name in functions and name not in covered
    )
    return hits

def _constant_hits(span: str, constants: set[str]) -> list[str]:
    metavars = set(FLAG_METAVAR_RE.findall(span))
    return [c for c in ALL_CAPS_RE.findall(span) if c in constants and c not in metavars]

def _unique(items) -> list[str]:
    result: list[str] = []
    for item in items:
        if item not in result:
            result.append(item)
    return result
