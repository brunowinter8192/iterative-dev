# INFRASTRUCTURE
from pathlib import Path

from src.docs_drift_check.collect import relative_dir_label
from src.docs_drift_check.markdown_scan import iter_fields, iter_lines, section_lines

ROLE_MAX_WORDS = 50
PURPOSE_MAX_WORDS = 25

# FUNCTIONS

def check_titles(doc_files: list[Path], root: Path) -> list[str]:
    findings: list[str] = []
    for doc in doc_files:
        expected = f"# {relative_dir_label(doc.parent, root)}/"
        finding = _check_title(doc, expected)
        if finding:
            findings.append(f"`{doc.relative_to(root).as_posix()}{finding[0]}` {finding[1]}")
    return findings

def _check_title(doc: Path, expected: str) -> tuple[str, str] | None:
    for lineno, line in iter_lines(doc):
        if line.startswith("# "):
            if line.rstrip() == expected:
                return None
            return f":{lineno}", f"title `{line.rstrip()}` should be `{expected}`"
    return "", f"has no title `{expected}`"

def check_word_limits(doc_files: list[Path], root: Path) -> list[str]:
    findings: list[str] = []
    for doc in doc_files:
        rel_doc = doc.relative_to(root).as_posix()
        findings.extend(_check_role(doc, rel_doc))
        findings.extend(_check_purposes(doc, rel_doc))
    return findings

def _check_role(doc: Path, rel_doc: str) -> list[str]:
    lines = [(n, line) for n, line in section_lines(doc, "Role") if line.strip()]
    if not lines:
        return []
    words = _count_words(" ".join(line for _, line in lines))
    if words <= ROLE_MAX_WORDS:
        return []
    return [f"`{rel_doc}:{lines[0][0]}` Role has {words} words, maximum {ROLE_MAX_WORDS}"]

def _check_purposes(doc: Path, rel_doc: str) -> list[str]:
    findings: list[str] = []
    for lineno, text in iter_fields(doc, "Purpose"):
        words = _count_words(text)
        if words > PURPOSE_MAX_WORDS:
            findings.append(f"`{rel_doc}:{lineno}` Purpose has {words} words, maximum {PURPOSE_MAX_WORDS}")
    return findings

def _count_words(text: str) -> int:
    return sum(1 for token in text.split() if any(ch.isalnum() for ch in token))
