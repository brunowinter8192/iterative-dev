# INFRASTRUCTURE
import re
from pathlib import Path

from src.docs_drift_check.markdown_scan import iter_backtick_lines
from src.docs_drift_check.symbols import find_module_function_tokens

ALL_CAPS_RE = re.compile(r"\b[A-Z][A-Z0-9_]{3,}\b")
FLAG_METAVAR_RE = re.compile(r"--[\w-]+[ =]+([A-Z][A-Z0-9_]{3,})\b")
CALL_RE = re.compile(r"\b([A-Za-z_]\w*)\(")

# FUNCTIONS

def check_rule_violations(
    doc_files: list[Path],
    root: Path,
    functions: set[str],
    constants: set[str],
    owners: set[str],
) -> list[str]:
    findings: list[str] = []
    for doc in doc_files:
        rel_doc = doc.relative_to(root).as_posix()
        for lineno, spans in iter_backtick_lines(doc):
            hits = _collect_line_hits(spans, functions, constants, owners)
            findings.extend(f"`{rel_doc}:{lineno}` {kind} `{symbol}`" for kind, symbol in hits)
    return findings

def _collect_line_hits(
    spans: list[str], functions: set[str], constants: set[str], owners: set[str]
) -> list[tuple[str, str]]:
    hits: list[tuple[str, str]] = []
    for span in spans:
        for hit in _find_span_hits(span, functions, constants, owners):
            if hit not in hits:
                hits.append(hit)
    return hits

def _find_span_hits(
    span: str, functions: set[str], constants: set[str], owners: set[str]
) -> list[tuple[str, str]]:
    module_refs = find_module_function_tokens(span, owners)
    covered = {ref.rstrip(".").rsplit(".", 1)[-1] for ref in module_refs}
    hits = [("function-level reference", ref) for ref in module_refs]
    hits.extend(
        ("function-level reference", f"{name}()")
        for name in CALL_RE.findall(span)
        if name in functions and name not in covered
    )
    metavars = set(FLAG_METAVAR_RE.findall(span))
    hits.extend(
        ("constant reference", c)
        for c in ALL_CAPS_RE.findall(span)
        if c in constants and c not in metavars
    )
    return hits
