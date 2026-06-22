#!/usr/bin/env python3
# _capture_clean.py — clean+scope worker pane output for worker_capture_clean
# Usage: python3 _capture_clean.py <pane_file> <worker_name>
#   pane_file: raw tmux capture-pane -p -S - output; caller is responsible for cleanup
#   worker_name: used in the output header
# Output: "=== capture from <name> (since last prompt, N chars) ===" + cleaned body

# INFRASTRUCTURE
import re
import sys

# Bottom widget patterns — stripped before searching for prompt anchor
_RE_RULE        = re.compile(r'^[─━═\s-]{4,}$')
_RE_BARE_PROMPT = re.compile(r'^❯\s*$')
_RE_SONNET      = re.compile(r'sonnet.+\d+%', re.I)
_RE_BYPASS      = re.compile(r'bypass permissions|⏵⏵', re.I)

# Prompt anchor: ❯ with non-whitespace content (real prompt, not bare input box)
_RE_REAL_PROMPT = re.compile(r'^❯\s+\S')

# Filter patterns — applied inside the clean pass
_RE_BOX_TOP   = re.compile(r'^\s*╭')
_RE_BOX_BOT   = re.compile(r'^\s*╰')
_RE_COLLAPSE  = re.compile(r'ctrl\+o to expand', re.I)
_RE_THINKING  = re.compile(r'^\s*✻')
_RE_UPDATE    = re.compile(r'\b(Update|Create)\s*\(')
_RE_ADDED     = re.compile(r'^Added \d+')
_RE_DIFF_LINE = re.compile(r'^\s*[+\-]\s')

# Leading tool-use glyphs to strip (keep the text after them)
_GLYPHS = {'⏺', '⎿'}


# ORCHESTRATOR

# Read pane file, scope to last real prompt, apply clean filter, print result.
def capture_clean_workflow():
    pane_file = sys.argv[1]
    worker_name = sys.argv[2]
    raw = open(pane_file).read()
    lines = raw.split('\n')
    body_lines, fallback = _scope_to_last_prompt(lines)
    cleaned = _clean(body_lines)
    _print_output(worker_name, cleaned, fallback)


# FUNCTIONS

# Trim bottom widget, find last real ❯ prompt, return (body_lines, fallback_note).
# Pre-trimming the bottom widget prevents the bare input-box ❯ from winning the anchor.
def _scope_to_last_prompt(lines):
    trimmed = lines[:_trim_bottom_widget(lines)]
    last_idx = None
    for i in range(len(trimmed) - 1, -1, -1):
        if _RE_REAL_PROMPT.match(trimmed[i]):
            last_idx = i
            break
    if last_idx is None:
        return lines, '⚠ prompt marker not in scrollback — showing full buffer'
    return lines[last_idx + 1:], ''


# Return index one past the last non-widget line (scan up past blanks/rules/bare-❯/footer).
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


# Apply the full clean filter to body_lines; return list of cleaned strings.
def _clean(lines):
    out = []
    in_box = False
    in_diff = False

    for line in lines:
        # Welcome boot box: ╭ ... ╰ — drop entire block
        if _RE_BOX_TOP.match(line):
            in_box = True
        if in_box:
            if _RE_BOX_BOT.match(line):
                in_box = False
            continue

        if not line.strip():
            out.append('')
            in_diff = False    # blank line exits diff block
            continue

        # Bottom widget chrome (safety: may survive in body on edge cases)
        if _RE_RULE.match(line) or _RE_BARE_PROMPT.match(line):
            continue
        if _RE_SONNET.search(line) or _RE_BYPASS.search(line):
            continue

        # Collapse markers and thinking spinners
        if _RE_COLLAPSE.search(line):
            continue
        if _RE_THINKING.match(line):
            continue

        # Strip leading ⏺/⎿ glyph, keep the rest
        if line and line[0] in _GLYPHS:
            line = line[1:].lstrip()
        stripped = line.strip()

        # Diff block: Update()/Create() header enters, ⎿Added exits, +/- body lines dropped
        if _RE_UPDATE.search(line):
            in_diff = True
            out.append(line)
            continue

        if in_diff:
            if _RE_ADDED.match(stripped):
                out.append(line)
                in_diff = False
                continue
            if _RE_DIFF_LINE.match(line):
                continue
            in_diff = False   # any other line exits diff block

        out.append(line)

    while out and not out[-1].strip():
        out.pop()
    return out


# Print header + optional fallback warning + cleaned body to stdout.
def _print_output(name, cleaned, fallback):
    body = '\n'.join(cleaned)
    chars = len(body)
    print(f'=== capture from {name} (since last prompt, {chars} chars) ===')
    if fallback:
        print(fallback)
    print(body)


if __name__ == '__main__':
    capture_clean_workflow()
