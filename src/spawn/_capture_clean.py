#!/usr/bin/env python3

# INFRASTRUCTURE
import re
import sys

_RE_RULE        = re.compile(r'^[─━═\s-]{4,}$')
_RE_BARE_PROMPT = re.compile(r'^❯\s*$')
_RE_SONNET      = re.compile(r'sonnet.+\d+%', re.I)
_RE_BYPASS      = re.compile(r'bypass permissions|⏵⏵', re.I)

_RE_REAL_PROMPT = re.compile(r'^❯\s+\S')

_RE_BOX_TOP   = re.compile(r'^\s*╭')
_RE_BOX_BOT   = re.compile(r'^\s*╰')
_RE_COLLAPSE  = re.compile(r'ctrl\+o to expand', re.I)
_RE_THINKING  = re.compile(r'^\s*✻')
_RE_UPDATE    = re.compile(r'\b(Update|Create)\s*\(')
_RE_ADDED     = re.compile(r'^⎿\s+Added \d+')
_RE_DIFF_LINE = re.compile(r'^\s+\d+(?:\s|$)')

_GLYPHS = {'⏺', '⎿'}


# ORCHESTRATOR

def capture_clean_workflow():
    pane_file, worker_name = parse_args()
    lines = read_pane_lines(pane_file)
    body_lines, fallback = _scope_to_last_prompt(lines)
    cleaned = _clean(body_lines)
    _print_output(worker_name, cleaned, fallback)


# FUNCTIONS

def parse_args():
    return sys.argv[1], sys.argv[2]


def read_pane_lines(pane_file):
    with open(pane_file) as f:
        return f.read().split('\n')


def _scope_to_last_prompt(lines):
    trimmed = lines[:_trim_bottom_widget(lines)]
    last_idx = None
    for i in range(len(trimmed) - 1, -1, -1):
        if _RE_REAL_PROMPT.match(trimmed[i]):
            last_idx = i
            break
    if last_idx is None:
        return lines, 'WARNING: prompt marker not in scrollback, showing full buffer'
    return lines[last_idx + 1:], ''


def _trim_bottom_widget(lines):
    i = len(lines) - 1
    while i >= 0:
        line = lines[i]
        if not line.strip():
            i -= 1
            continue
        if (_RE_RULE.match(line) or _RE_BARE_PROMPT.match(line)
                or _RE_SONNET.search(line) or _RE_BYPASS.search(line)):
            i -= 1
            continue
        break
    return i + 1


def _clean(lines):
    out = []
    in_box = False
    in_diff = False

    for line in lines:
        drop, in_box = _handle_boot_box(line, in_box)
        if drop:
            continue

        if not line.strip():
            out.append('')
            in_diff = False
            continue

        if _is_chrome_line(line):
            continue

        orig = line
        if line and line[0] in _GLYPHS:
            line = line[1:].lstrip()
        stripped = line.strip()

        action, in_diff = _process_diff_block(line, orig, stripped, in_diff)
        if action == 'drop':
            continue

        out.append(line)

    while out and not out[-1].strip():
        out.pop()
    return out


def _handle_boot_box(line, in_box):
    if _RE_BOX_TOP.match(line):
        in_box = True
    if in_box:
        if _RE_BOX_BOT.match(line):
            in_box = False
        return True, in_box
    return False, in_box


def _is_chrome_line(line):
    if _RE_RULE.match(line) or _RE_BARE_PROMPT.match(line):
        return True
    if _RE_SONNET.search(line) or _RE_BYPASS.search(line):
        return True

    if _RE_COLLAPSE.search(line):
        return True
    if _RE_THINKING.match(line):
        return True

    return False


def _process_diff_block(line, orig, stripped, in_diff):
    if _RE_UPDATE.search(line):
        return 'append', True

    if in_diff:
        if _RE_ADDED.match(stripped):
            return 'append', True
        if _RE_DIFF_LINE.match(line):
            return 'drop', True
        if orig.lstrip().startswith('⏺'):
            return 'append', False
        return 'drop', True

    return 'append', in_diff


def _print_output(name, cleaned, fallback):
    body = '\n'.join(cleaned)
    chars = len(body)
    print(f'=== capture from {name} (since last prompt, {chars} chars) ===')
    if fallback:
        print(fallback)
    print(body)


if __name__ == '__main__':
    capture_clean_workflow()
