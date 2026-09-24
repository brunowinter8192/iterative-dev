# INFRASTRUCTURE
import re
from pathlib import Path

from src.docs_drift_check.markdown_scan import iter_backtick_lines
from src.docs_drift_check.symbols import is_module_function_reference

RUNTIME_SKIP_EXTENSIONS = {".log", ".flock", ".pid", ".jsonl"}
PLACEHOLDER_TOKENS = {
    "foo", "bar", "baz", "qux",
    "area", "name", "module", "letter",
    "xxx", "dummy", "example",
}
PATH_RE = re.compile(
    r"(?:[a-zA-Z0-9_.*-]+/)+[a-zA-Z0-9_.*-]+"
    r"(?:\.(?:py|md|json|jsonl|sh|yaml|yml|txt))?"
    r"(?::\d+)?"
)
CROSS_PROJECT_MARKER_RE = re.compile(r"\s\([A-Z][A-Za-z_]+\)\s*$")
COLON_SUFFIX_RE = re.compile(r"(\.[a-zA-Z]{1,5}):.*$")

# FUNCTIONS

def check_path_existence(doc_files: list[Path], root: Path, owners: set[str]) -> list[str]:
    findings: list[str] = []
    for doc in doc_files:
        rel_doc = doc.relative_to(root).as_posix()
        for lineno, spans in iter_backtick_lines(doc):
            for raw in _line_candidates(spans):
                finding = _check_candidate(raw, root, doc, owners)
                if finding:
                    findings.append(f"`{rel_doc}:{lineno}` references `{finding[0]}` - {finding[1]}")
    return findings

def _line_candidates(spans: list[str]) -> list[str]:
    candidates: list[str] = []
    for span in spans:
        if _is_excluded_span(span):
            continue
        for match in PATH_RE.finditer(span):
            raw = match.group(0).strip()
            if raw not in candidates:
                candidates.append(raw)
    return candidates

def _is_excluded_span(span: str) -> bool:
    return span.startswith("~/") or "<" in span or bool(CROSS_PROJECT_MARKER_RE.search(span))

def _check_candidate(raw: str, root: Path, doc: Path, owners: set[str]) -> tuple[str, str] | None:
    if raw.startswith("/") or is_module_function_reference(raw, owners):
        return None
    if _should_skip_path(raw, root, doc.parent):
        return None
    path_str = COLON_SUFFIX_RE.sub(r"\1", raw)
    if "*" in path_str:
        hits = list(root.glob(path_str)) + list(doc.parent.glob(path_str))
        return None if hits else (path_str, "NOT FOUND (glob)")
    if (root / path_str).exists() or (doc.parent / path_str).exists():
        return None
    return path_str, "NOT FOUND"

def _should_skip_path(raw: str, root: Path, doc_dir: Path) -> bool:
    if raw.startswith(("http://", "https://", "~/")):
        return True
    if "{" in raw or "..." in raw:
        return True
    if any(Path(part).stem in PLACEHOLDER_TOKENS for part in raw.split("/")):
        return True
    path_part = COLON_SUFFIX_RE.sub(r"\1", raw)
    if Path(path_part.split("*")[0]).suffix.lower() in RUNTIME_SKIP_EXTENSIONS:
        return True
    first = path_part.split("/")[0]
    return not (root / first).exists() and not (doc_dir / first).exists()
