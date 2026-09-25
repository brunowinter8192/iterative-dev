# INFRASTRUCTURE
import re
from pathlib import Path

BACKTICK_RE = re.compile(r"`([^`]+)`")
FIELD_RE = re.compile(r"^\*\*([A-Za-z ]+):\*\*\s*(.*)$")

# FUNCTIONS

def iter_lines(doc: Path) -> list[tuple[int, str]]:
    lines: list[tuple[int, str]] = []
    in_fence = False
    for lineno, line in enumerate(doc.read_text().splitlines(), 1):
        if _is_fence(line):
            in_fence = not in_fence
        elif not in_fence:
            lines.append((lineno, line))
    return lines

def iter_backtick_lines(doc: Path) -> list[tuple[int, list[str]]]:
    result: list[tuple[int, list[str]]] = []
    for lineno, line in iter_lines(doc):
        spans = BACKTICK_RE.findall(line)
        if spans:
            result.append((lineno, spans))
    return result

def section_lines(doc: Path, name: str) -> list[tuple[int, str]]:
    lines: list[tuple[int, str]] = []
    active = False
    for lineno, line in iter_lines(doc):
        if line.startswith("## "):
            active = line[3:].strip() == name
        elif active:
            lines.append((lineno, line))
    return lines

def iter_module_headings(doc: Path) -> list[tuple[int, str]]:
    return [(n, line.rstrip()) for n, line in section_lines(doc, "Modules") if line.startswith("### ")]

def iter_fields(doc: Path, label: str) -> list[tuple[int, str]]:
    fields: list[tuple[int, list[str]]] = []
    current: list[str] | None = None
    for lineno, line in iter_lines(doc):
        match = FIELD_RE.match(line)
        if match:
            current = [match.group(2)] if match.group(1) == label else None
            if current is not None:
                fields.append((lineno, current))
        elif current is not None and _continues_field(line):
            current.append(line.strip())
        else:
            current = None
    return [(lineno, " ".join(parts).strip()) for lineno, parts in fields]

def _continues_field(line: str) -> bool:
    stripped = line.strip()
    return bool(stripped) and not stripped.startswith(("---", "#"))

def _is_fence(line: str) -> bool:
    return line.strip().startswith(("```", "~~~"))
