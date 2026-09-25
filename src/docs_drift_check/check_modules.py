# INFRASTRUCTURE
import re
from pathlib import Path

from src.docs_drift_check.markdown_scan import iter_module_headings

MODULE_HEADING_RE = re.compile(r"^###\s+([^\s/]+)\s+\((\d+) LOC\)$")

# FUNCTIONS

def check_module_headings(doc_files: list[Path], root: Path) -> list[str]:
    findings: list[str] = []
    for doc in doc_files:
        rel_doc = doc.relative_to(root).as_posix()
        for lineno, line in iter_module_headings(doc):
            finding = _check_heading(doc, line)
            if finding:
                findings.append(f"`{rel_doc}:{lineno}` {finding}")
    return findings

def _check_heading(doc: Path, line: str) -> str | None:
    match = MODULE_HEADING_RE.match(line)
    if not match:
        return f"malformed module heading `{line}` (expected `### <file> (<N> LOC)` with a bare file name and single spaces)"
    return _compare_heading(doc, match.group(1), int(match.group(2)))

def _compare_heading(doc: Path, module_name: str, claimed: int) -> str | None:
    module_path = doc.parent / module_name
    if not module_path.is_file():
        return f"documents `{module_name}` but the module file does not exist in this directory"
    actual = module_path.read_bytes().count(b"\n")
    if claimed == actual:
        return None
    return f"claims `{module_name}` = {claimed} LOC, actual {actual} ({actual - claimed:+d})"
