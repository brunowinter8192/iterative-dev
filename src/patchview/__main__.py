# INFRASTRUCTURE
import hashlib
import html
import os
import re
import sys
from typing import NamedTuple

PAGE_DIR_NAME = "patchview"
PAGE_HASH_LEN = 12
HUNK_HEADER = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
PAGE_CSS = (
    "body{background:#1e1f22;color:#d4d4d4;font:14px/1.5 Menlo,monospace;margin:0;padding:16px}\n"
    "h1{font:600 16px -apple-system,sans-serif;margin:0 0 4px}"
    ".legend{font:13px -apple-system,sans-serif;margin-bottom:12px;color:#aaa}\n"
    "pre{margin:0;font:inherit;white-space:pre-wrap}"
    "pre span{display:inline-block;width:100%;box-sizing:border-box;padding:0 8px}"
    'pre span:empty::before{content:"\\00a0"}\n'
    ".del{background:#4b1f24}.add{background:#1f4b2a}.legend .add,.legend .del{padding:0 6px}"
)


class PatchviewError(Exception):
    def __init__(self, message: str, code: int = 1):
        super().__init__(message)
        self.code = code


class Hunk(NamedTuple):
    number: int
    old_start: int
    old_count: int
    lines: list


# ORCHESTRATOR

def patchview_workflow(argv: list) -> int:
    return exit_code_of(render_patch_page, argv)

# FUNCTIONS

def exit_code_of(step, argv: list) -> int:
    try:
        step(argv)
    except PatchviewError as error:
        print(f"patchview: {error}", file=sys.stderr)
        return error.code
    return 0

def render_patch_page(argv: list) -> None:
    patch_path = parse_args(argv)
    patch_lines = read_text_lines(patch_path)
    live_path, hunks = parse_patch(patch_lines, patch_path)
    live_lines = read_text_lines(live_path)
    rows = apply_hunks(live_lines, hunks, live_path)
    page = build_page(rows, live_path, patch_path)
    page_path = write_page(page, patch_path)
    print(page_path)

def parse_args(argv: list) -> str:
    if len(argv) != 1:
        raise PatchviewError("usage: patchview <patch-file>", code=2)
    return os.path.abspath(os.path.expanduser(argv[0]))

def read_text_lines(path: str) -> list:
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except (OSError, UnicodeDecodeError) as e:
        raise PatchviewError(f"cannot read {path}: {e}")
    lines = text.split("\n")
    if lines[-1] == "":
        lines.pop()
    return lines

def parse_patch(patch_lines: list, patch_path: str):
    live_path = parse_live_path(patch_lines, patch_path)
    hunks = parse_hunks(patch_lines, patch_path)
    return live_path, hunks

def parse_live_path(patch_lines: list, patch_path: str) -> str:
    if len(patch_lines) < 2 or not patch_lines[0].startswith("--- ") or not patch_lines[1].startswith("+++ "):
        raise PatchviewError(f"{patch_path} is not a unified diff: it must start with the '--- <live file>' and '+++ <new file>' lines of `diff -u`")
    live_path = patch_lines[0][4:].split("\t")[0].strip()
    live_path = os.path.expanduser(live_path)
    if not os.path.isabs(live_path):
        raise PatchviewError(f"the '---' line of {patch_path} names '{live_path}', which is not an absolute path; create the patch with `diff -u <absolute live file> <new file>`")
    return live_path

def parse_hunks(patch_lines: list, patch_path: str) -> list:
    hunks = []
    index = 2
    while index < len(patch_lines) and patch_lines[index].startswith("@@"):
        hunk, index = parse_hunk(patch_lines, index, len(hunks) + 1, patch_path)
        hunks.append(hunk)
    if not hunks:
        raise PatchviewError(f"{patch_path} contains no hunk")
    if index < len(patch_lines):
        raise PatchviewError(f"{patch_path} line {index + 1} is not part of a hunk; only a single-file unified diff is supported")
    return hunks

def parse_hunk(patch_lines: list, index: int, number: int, patch_path: str):
    match = HUNK_HEADER.match(patch_lines[index])
    if not match:
        raise PatchviewError(f"{patch_path} line {index + 1}: malformed hunk header: {patch_lines[index]}")
    old_start = int(match.group(1))
    old_count = 1 if match.group(2) is None else int(match.group(2))
    new_count = 1 if match.group(4) is None else int(match.group(4))
    lines, index = read_hunk_body(patch_lines, index + 1, old_count, new_count, patch_path)
    return Hunk(number, old_start, old_count, lines), index

def read_hunk_body(patch_lines: list, index: int, old_count: int, new_count: int, patch_path: str):
    lines = []
    old_seen = new_seen = 0
    while old_seen < old_count or new_seen < new_count:
        if index >= len(patch_lines):
            raise PatchviewError(f"{patch_path} ends inside a hunk: fewer lines than its header announces")
        sign, text = patch_lines[index][:1], patch_lines[index][1:]
        if sign != "\\":
            old_seen += sign in (" ", "-")
            new_seen += sign in (" ", "+")
            if sign not in (" ", "-", "+") or old_seen > old_count or new_seen > new_count:
                raise PatchviewError(f"{patch_path} line {index + 1}: line does not fit the hunk header: {patch_lines[index]}")
            lines.append((sign, text))
        index += 1
    while index < len(patch_lines) and patch_lines[index].startswith("\\"):
        index += 1
    return lines, index

def apply_hunks(live_lines: list, hunks: list, live_path: str) -> list:
    rows = []
    cursor = 0
    for hunk in hunks:
        position = locate_hunk(live_lines, hunk, cursor, live_path)
        rows.extend(("eq", text) for text in live_lines[cursor:position])
        rows.extend(hunk_rows(hunk))
        cursor = position + len(old_block_of(hunk))
    rows.extend(("eq", text) for text in live_lines[cursor:])
    return rows

def locate_hunk(live_lines: list, hunk: Hunk, cursor: int, live_path: str) -> int:
    old_block = old_block_of(hunk)
    last_start = len(live_lines) - len(old_block)
    candidates = [p for p in range(cursor, last_start + 1) if live_lines[p:p + len(old_block)] == old_block]
    if not candidates:
        raise PatchviewError(stale_message(hunk, old_block, cursor, live_path))
    expected = hunk.old_start if hunk.old_count == 0 else hunk.old_start - 1
    return min(candidates, key=lambda p: abs(p - expected))

def old_block_of(hunk: Hunk) -> list:
    return [text for sign, text in hunk.lines if sign in (" ", "-")]

def stale_message(hunk: Hunk, old_block: list, cursor: int, live_path: str) -> str:
    return (
        f"STALE PATCH: hunk {hunk.number} (old line {hunk.old_start}) does not match {live_path} exactly "
        f"at or after line {cursor + 1}; first line it expects: {old_block[0]!r}. "
        f"The file changed since the patch was created, or an earlier hunk consumed its place. "
        f"Nothing was rendered or modified; recreate the patch with `diff -u {live_path} <new file>`."
    )

def hunk_rows(hunk: Hunk) -> list:
    kinds = {" ": "eq", "-": "del", "+": "add"}
    return [(kinds[sign], text) for sign, text in hunk.lines]

def build_page(rows: list, live_path: str, patch_path: str) -> str:
    title = f"{live_path}  <-  {os.path.basename(patch_path)}"
    removed = sum(1 for kind, _ in rows if kind == "del")
    added = sum(1 for kind, _ in rows if kind == "add")
    body = "".join(render_row(kind, text) for kind, text in rows)
    legend = (
        f'<div class="legend"><span class="del">rot = entfällt ({removed} Zeilen)</span> '
        f'<span class="add">grün = neu ({added} Zeilen)</span></div>'
    )
    return (
        f'<!doctype html><meta charset="utf-8"><title>{html.escape(title)}</title><style>{PAGE_CSS}</style>\n'
        f"<h1>{html.escape(title)}</h1>{legend}\n<pre>{body}</pre>"
    )

def render_row(kind: str, text: str) -> str:
    return f'<span class="{kind}">{html.escape(text)}</span>\n'

def write_page(page: str, patch_path: str) -> str:
    page_dir = os.path.join(os.environ.get("TMPDIR") or "/tmp", PAGE_DIR_NAME)
    os.makedirs(page_dir, exist_ok=True)
    digest = hashlib.sha256(os.path.realpath(patch_path).encode()).hexdigest()[:PAGE_HASH_LEN]
    stem = os.path.splitext(os.path.basename(patch_path))[0]
    page_path = os.path.join(page_dir, f"{stem}-{digest}.html")
    with open(page_path, "w", encoding="utf-8") as f:
        f.write(page)
    return page_path

if __name__ == "__main__":
    sys.exit(patchview_workflow(sys.argv[1:]))
