# INFRASTRUCTURE
import re
from pathlib import Path

BACKTICK_RE = re.compile(r"`([^`]+)`")

# FUNCTIONS

def iter_backtick_lines(doc: Path) -> list[tuple[int, list[str]]]:
    result: list[tuple[int, list[str]]] = []
    in_fence = False
    for lineno, line in enumerate(doc.read_text().splitlines(), 1):
        in_fence = _toggle_fence(line, in_fence)
        if in_fence:
            continue
        spans = BACKTICK_RE.findall(line)
        if spans:
            result.append((lineno, spans))
    return result

def _toggle_fence(line: str, in_fence: bool) -> bool:
    stripped = line.strip()
    if stripped.startswith("```") or stripped.startswith("~~~"):
        return not in_fence
    return in_fence
