---
name: tool-use
description: Tool-call hygiene. Reduces call-waste (large Bash commands for tiny outputs) through concrete anti-patterns and preferred alternatives. Runs in parallel with the proxy-injected rules. Live feedback via Monitor_CC waste_pane.
---

# Tool-Use Skill

Goal: no large Bash-call where a small one works. Every call's input counts — tool_use JSON inflates with escaped newlines and quotes. Live feedback in Monitor_CC waste_pane (Window 4 right) shows current-session ratios ≥3.

## Hard rules

### 1. NEVER inline Python heredoc for analysis

`python3 << 'EOF' ... EOF` is the #1 waster. Tool-input balloons to 1-4KB through escaped newlines/quotes. Output is typically <100 chars. Observed ratios: 50-190.

**Instead:**
- Write tool → `/tmp/analyze.py` (flat content, ONE Write call) → `./venv/bin/python3 /tmp/analyze.py`
- For true one-liners: `python3 -c "..."` hard-capped at ≤300 chars including escaping. Above → Write tool.

### 2. `python3 -c "..."` > 300 chars → Write-then-run

Same escape-inflation problem. When the `-c` string exceeds 300 chars, stop typing it inline. Write a script file.

### 3. Don't chain greps/cats over the same pattern

```
WRONG: grep X a.log && grep X b.log && grep X c.log
RIGHT: grep X a.log b.log c.log
```

### 4. Don't re-issue near-identical commands

If you've run a command in this session and the output wasn't what you needed, do NOT retry the same command with a minor variation. Change approach: different tool (Grep/Glob), different scope, or read source.

## Soft rules

### 5. Repeated absolute paths → env var or single `cd`

When a path appears in 3+ consecutive commands: use `$MONITOR_CC_ROOT` (or equivalent) or `cd` once at the start of a planned block. Do NOT drift `cd` silently across interactive steps — only within a contained sequence.

### 6. Grep/Glob gunshot

Multiple Grep/Glob calls with varied patterns that all return zero results = guessing. Pattern:
1. `Glob` first: find files matching a broad path pattern.
2. `Grep` on the hit: targeted pattern on a known file.

Zero-results live in the warnings_pane (Monitor Window 4 left). Two zero-results in a row on the same topic = stop, rethink.

### 7. Multi-line echo → Write

`echo "..." >> file` or `cat << 'EOF' >> file ... EOF` multi-line = use the Write tool. Single-line echo append for config/log is fine.

## Large artifacts

### 8. Bead descriptions

`bd create --description "..."` is a top-3 waster at >1KB descriptions. Two options:
- Accept: bead quality > tokens. Rich descriptions are the point of beads.
- If `bd` supports `--description-file` (check): write to `/tmp/bead-desc.md`, then `bd ... --description-file /tmp/bead-desc.md`.

### 9. Git commit messages

`git commit -m "$(cat <<'EOF' ... EOF)"` is acceptable for ≤500 chars. For longer multi-line commits: write message to a file, then `git commit -F /tmp/commit-msg.md`.

## Monitoring self-audit

- **waste_pane** (Monitor Window 4 right): check 1-2× per session. Expand top offenders. If the same command-prefix keeps appearing: that's a rule violation, stop and rethink.
- **warnings_pane zero-results**: repeated zero results on the same topic = rule 6 violation.
- **Per-session reports**: `dev/tool_use_analysis/YYYYMMDD_*.md` in Monitor_CC. Generated per session via ad-hoc scripts (one script per analysis, no shared library).

## What this skill does NOT do

- Does not strip tool_result content at the proxy. That's a separate concern (result-waste, tracked under a different bead).
- Does not enforce at commit time. This is advisory behavior through rule-awareness. The monitor is the feedback loop.
- Does not maintain a library or justfile. Every analysis script is one-off.
