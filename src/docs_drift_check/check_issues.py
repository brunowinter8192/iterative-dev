# INFRASTRUCTURE
import re
from pathlib import Path

from src.docs_drift_check.markdown_scan import iter_lines

ISSUE_RE = re.compile(r"(?<![\w&#/])#\d+\b|/issues/\d+")

# FUNCTIONS

def check_issue_references(doc_files: list[Path], root: Path) -> list[str]:
    findings: list[str] = []
    for doc in doc_files:
        rel_doc = doc.relative_to(root).as_posix()
        for lineno, line in iter_lines(doc):
            match = ISSUE_RE.search(line)
            if match:
                findings.append(f"`{rel_doc}:{lineno}` references an issue (`{match.group(0)}`)")
    return findings
