# INFRASTRUCTURE
import re
from pathlib import Path

LOC_HEADING_RE = re.compile(r"^###\s+([\w./-]+\.\w+)\s+\((\d+)\s+LOC\)")

# FUNCTIONS

def check_loc_drift(doc_files: list[Path], root: Path) -> list[str]:
    findings: list[str] = []
    for doc in doc_files:
        findings.extend(_check_doc_headings(doc, root))
    return findings

def _check_doc_headings(doc: Path, root: Path) -> list[str]:
    findings: list[str] = []
    rel_doc = doc.relative_to(root).as_posix()
    in_fence = False
    for lineno, line in enumerate(doc.read_text().splitlines(), 1):
        if line.strip().startswith(("```", "~~~")):
            in_fence = not in_fence
            continue
        match = LOC_HEADING_RE.match(line)
        if in_fence or not match:
            continue
        finding = _compare_heading(doc, match.group(1), int(match.group(2)))
        if finding:
            findings.append(f"`{rel_doc}:{lineno}` {finding}")
    return findings

def _compare_heading(doc: Path, module_name: str, claimed: int) -> str | None:
    module_path = doc.parent / module_name
    if not module_path.is_file():
        return f"documents `{module_name}` but the module file does not exist"
    actual = module_path.read_bytes().count(b"\n")
    if claimed == actual:
        return None
    return f"claims `{module_name}` = {claimed} LOC, actual {actual} ({actual - claimed:+d})"
