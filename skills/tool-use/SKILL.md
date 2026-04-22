---
name: tool-use
description: Tool-call hygiene. Reduces call-waste through concrete anti-patterns and preferred alternatives. Covers token efficiency, verbose output, tool selection, and per-tool behavior reference. Live feedback via Monitor_CC waste_pane.
---

# Tool-Use Skill

Goal: no large Bash-call where a small one works. Every tool_use input counts — tool_use JSON inflates with escaped newlines and quotes. Live feedback in Monitor_CC waste_pane (Window 4 right) shows current-session ratios ≥3.

## Hard Rules — Token Efficiency

### 1. NEVER inline Python heredoc; `python3 -c` hard cap at 300 chars

`python3 << 'EOF' ... EOF` is the #1 waster. Tool-input balloons to 1-4KB through escaped newlines/quotes. Output is typically <100 chars. Observed ratios: 50-190.

**Rule:** For any JSON/log analysis beyond a one-liner:

1. **Prefer jq/grep/awk** — purpose-built. `jq -c 'select(.type=="error")' file.jsonl` beats 15 lines of Python.
2. **Write script to file** — `Write /tmp/investigate.py` once, then `python3 /tmp/investigate.py`. Iterate via Edit tool, never re-write the full script.
3. **Shell variables for repeated paths** — `LOG=/path/foo.jsonl && jq '.type' $LOG` instead of inlining the path in every call.
4. **Pipeline chains** — `head -100 file | jq .type | sort -u` over monolithic Python.

**The test:** Bash tool_use contains >15 lines of Python → STOP. Rewrite as jq / script-file / pipeline.

**`python3 -c`:** when the `-c` string exceeds 300 chars including escaping — stop, write a script file instead. Same escape-inflation problem.

**Concrete failure (2026-04-19):** context-hygiene worker inspected session JSONL with 5+ inline python heredocs (500-2000 chars each). Context dropped from 40%+ to 18% in Phase 1 alone. A `jq '[.[] | select(.type=="attachment")] | length' file` one-liner would have answered the same question in ~80 chars.

### 2. No Bash for file creation → Write tool

**Rule:** NEVER use `cat > file << 'EOF'` or `echo >` to create files. Always use the Write tool.

**Why:** Bash heredocs can leak shell context into file content (e.g., `EOF 2>&1 | head -10` appended to a .gitignore). The Write tool is atomic and safe.

**Exception:** Single-line echo append to an existing file is fine: `echo "entry" >> config.log`.

### 3. Grep scope hygiene — always restrict when searching source

`grep -rn <pattern> <dir>` without type/include restriction matches inside JSONL, log files, vendored content, and node_modules. Output can explode into 10+ MB of irrelevant matches, poisoning context.

**Rule:**
- When searching for Python imports, function refs, or code-level patterns: always pass `--include='*.py'` to bash grep OR use the Grep tool with `type: "py"` / `glob: "*.py"`.
- Prefer the Grep tool over bash `grep -rn` for code search — safer defaults, structured results.
- For one-off bash grep: add explicit file scope (`grep -n <pattern> <specific_file>`) rather than `-r` over a whole tree.

Concrete failure (2026-04-19): `grep -rn "from queries import\|import queries" src/ dev/ workflow.py` without `--include` — `src/logs/` contained proxy JSONL with "queries" thousands of times. Output hit 75 MB. The Grep tool with `glob: "*.py"` returned the same information in milliseconds.

### 4. Context window hygiene — verbose output to file, not context (CRITICAL)

Large tool outputs (build output, test runners, dev scripts, background tasks) flood the context window. One verbose dump can burn 10k+ tokens of irrelevant noise.

**Rule: ALL potentially large output goes through files, NEVER directly into context.**

**Workflow:**
1. **Run command** → redirect: `command > /tmp/output.md 2>&1`
2. **Read result** → `grep`, `tail`, `head` on the file — extract ONLY what you need
3. **Present** → concise summary to user, not raw output

**The test:** Before ANY tool call that might produce >50 lines of output — redirect to file first. No exceptions.

```bash
# WRONG — dumps everything into context
./venv/bin/python dev/crawling_suite/03_test.py

# RIGHT — output to file, then extract what matters
./venv/bin/python dev/crawling_suite/03_test.py > /tmp/03_test_output.md 2>&1
tail -20 /tmp/03_test_output.md
```

- NEVER run `./venv/bin/python script.py` without `> /tmp/file.md 2>&1`
- NEVER run `cat` on a file that might be large — use `head`, `tail`, `grep`

### 5. Stop after 2 failed tool calls

When 2 tool calls in a row fail or don't deliver the desired result: **STOP IMMEDIATELY**.
- Clearly explain the problem to the user
- Ask: "How should I solve this?" or "Where can I find X?"
- NO further trial and error without user input

**"Quellen" = External Research, NOT More Bash:**
- After 2 failures: the answer is RESEARCH (Web/GitHub search, read source code, read docs), not RETRY
- Same error in a different wrapper = same bug. After 2nd failure: analyze the error pattern, ask what the common denominator is.

Concrete failure (2026-03-26): User asked 3× for needed sources. Response was more bash commands instead of naming concrete GitHub issues, tmux docs, or web searches to consult.

### 6. Never dispatch parallel Bash calls

Multiple Bash tool_use blocks in the same turn get serialized by the runtime — one wins, the others come back as `<tool_use_error>Cancelled: parallel tool call Bash(...)</tool_use_error>`. The cancelled calls still cost input tokens, produce zero useful output, and force a retry. Pure waste.

**Rule:** one Bash call per turn. If you need multiple bash operations:
- Chain them in a single command with `&&` or `;` (when outputs can be combined)
- Or run sequentially across turns (when each result informs the next)

Applies to ALL Bash invocations, not just `ls` — git, grep, cat, worker-cli, anything. Other tools (Read, Write, Edit, Grep, Glob) can be dispatched in parallel safely; only Bash has this cancel behavior.

Concrete failure (2026-04-22): worker proxy-strip-full dispatched 4 parallel `ls <path>` calls to probe the gitignored MCP schema directory. All but one were cancelled with `Cancelled: parallel tool call Bash(ls ...)`. Cost: 4× Bash input chars for 1 useful result.

### 7. Tool failure → immediate action (CRITICAL)

Tool call fails silently → do NOT continue with workaround or fallback without reporting.

**Rule:**
- Tool fails → report to user IMMEDIATELY in the same response
- Then: (a) fix the prerequisite yourself (start server, install dep, fix config) and retry, OR (b) stop and wait for user input if fix is outside your control
- NEVER silently fall back to a different approach without disclosing plan A failed
- NEVER ask "should I start X or work around it?" — if you CAN fix it, fix it

**Decision tree:**
1. Tool fails → report error to user in same message
2. Can I fix it? (start process, install dep, create dir) → fix it NOW, retry
3. Can't fix it? (needs user credentials, hardware, manual step) → stop, explain what's needed
4. NEVER: silently switch to plan B without disclosing plan A failed

Concrete failure (2026-03-28): RAG `search` failed with "llama-server not found". Claude fell back to `read_document` silently and only mentioned the issue in results. User had to say "starte den server wenn er nicht läuft".

---

## Soft Rules

### Repeated absolute paths → env var or single `cd`

When a path appears in 3+ consecutive commands: use `$MONITOR_CC_ROOT` (or equivalent) or `cd` once at the start of a planned block. Do NOT drift `cd` silently across interactive steps — only within a contained sequence.

### Don't chain greps/cats over the same pattern

```
WRONG: grep X a.log && grep X b.log && grep X c.log
RIGHT: grep X a.log b.log c.log
```

### Don't re-issue near-identical commands

If you've run a command in this session and the output wasn't what you needed, do NOT retry with a minor variation. Change approach: different tool (Grep/Glob), different scope, or read source.

### Grep/Glob gunshot

Multiple Grep/Glob calls with varied patterns that all return zero results = guessing. Pattern:
1. `Glob` first: find files matching a broad path pattern.
2. `Grep` on the hit: targeted pattern on a known file.

Zero-results live in the warnings_pane (Monitor Window 4 left). Two zero-results in a row on the same topic = stop, rethink.

---

## Large Artifacts

### Bead descriptions

`bd create --description "..."` is a top-3 waster at >1KB descriptions. Two options:
- Accept: bead quality > tokens. Rich descriptions are the point of beads.
- If `bd` supports `--description-file` (check): write to `/tmp/bead-desc.md`, then `bd ... --description-file /tmp/bead-desc.md`.

### Git commit messages

`git commit -m "$(cat <<'EOF' ... EOF)"` is acceptable for ≤500 chars. For longer multi-line commits: write message to a file, then `git commit -F /tmp/commit-msg.md`.

---

## Tool-Specific Reference

### Bash
- **Timeout:** default 120000ms (2 min), max 600000ms (10 min). Use the `timeout` parameter when running long builds, crawls, or test suites to avoid silent termination.

#### Worker CLI

**`c` is the canonical `project_path` argument.** Pass `c` instead of the full absolute path — resolves to the current project root from any directory including worktrees. Use absolute paths only when `c` cannot resolve (rare — only from a non-git directory). `worker-cli status --all c` snapshots all active workers in one call.

All worker lifecycle operations via `~/.local/bin/worker-cli`.

| Operation | CLI |
|---|---|
| List active workers | `worker-cli list <project_path>` |
| Check worker status | `worker-cli status <name> <project_path>` |
| Capture pane to file | `worker-cli capture <name> <project_path>` |
| Read last N lines | `tail -n <N> <output_file_from_capture>` |
| Merge worker branch | `worker-cli merge <name> <project_path>` |
| Kill worker | `worker-cli kill <name> <project_path>` |
| Send message to worker | `worker-cli send <name> <message> [project_path]` |
| Spawn worker in worktree | `worker-cli spawn <name> <prompt_file> <project_path> [model]` |

> `<project_path>` = `c` in the vast majority of cases.

The wrapper internally sources `$PLUGIN/src/spawn/tmux_spawn.sh`. Override plugin location via `CLAUDE_PLUGIN_ROOT` env var.

**Session name pattern:** `worker-<basename(project_path)>-<name>`. Example: project `/Users/x/Monitor_CC` + worker `inject-fixes` → session `worker-Monitor_CC-inject-fixes`.

**NEVER kill without checking status first.** If status is `working` → do NOT kill.

**Fallback** (wrapper unavailable):

```bash
PLUGIN=~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0
SPAWN="$PLUGIN/src/spawn/tmux_spawn.sh"
bash -c "source \"$SPAWN\" && worker_status \"<name>\" \"<project_path>\""
```

**Examples:**

```bash
worker-cli list c
worker-cli status inject-fixes c
worker-cli capture inject-fixes c
# → prints path like /tmp/worker_capture_inject-fixes_123456.txt
tail -n 50 /tmp/worker_capture_inject-fixes_123456.txt
worker-cli merge inject-fixes c
worker-cli kill inject-fixes c   # only after status is idle/done
worker-cli send inject-fixes "Go for step 2" c
worker-cli spawn new-feature /tmp/prompt.md c sonnet
```

#### Git CLI

Pre-commit check via `git-check` CLI, everything else via CLI.

##### Pre-Commit

`git-check [repo_path]` — `repo_path` accepts `c` (same resolver logic as worker-cli). Auto-stages files (with skip patterns: venv/, node_modules/) and returns a status report:
- `STAGED` / `UNSTAGED` / `UNTRACKED` sections
- `HOOK STATUS` (WARNING → run `bd export` via Bash before committing)
- `DIFF SUMMARY` → use for commit message

If all sections are `(none)` → nothing to commit, skip.

##### CLI Commands

| Operation | CLI | Notes |
|---|---|---|
| Commit (inside repo/worktree cwd) | `gc "<message>"` | Wrapper: stages tracked modifications + commits. Add filenames as extra args to stage specific files. |
| Commit (explicit path) | `git -C <repo_path> commit -am "<message>"` | Use when cwd is outside target repo. `-am` stages tracked mods. For untracked: `git -C <path> add <files> && git -C <path> commit -m "<msg>"`. |
| Push | `git -C <repo_path> push` | Falls back to `-u origin <branch>` if no upstream |
| Push with upstream | `git -C <repo_path> push -u origin $(git -C <repo_path> branch --show-current)` | For first push on new branch |
| Post-commit check | `git -C <repo_path> status --short` | Empty output = clean working tree. `.beads/` entries can be treated as clean. |
| Plugin sync | `~/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0/plugin-sync.sh <name> <repo_path>` | Plugin repos only (`.claude-plugin/plugin.json` must exist). Restart session after sync. |

##### Commit Flow

When user asks to commit:

1. **Check + Stage** — `git-check [repo_path]`
2. **Commit** — `gc "<message>"` (if cwd inside repo) OR `git -C c commit -am "<message>"` (explicit path; `c` resolves to project root)
3. **Post-check** — `git -C <repo> status --short` → empty = proceed; non-empty with non-`.beads/` paths → stage + commit again
4. **Push** — `git -C <repo> push` (retry with `-u origin <branch>` on first push)
5. **Plugin-sync** (if plugin repo) — run AFTER push

##### Commit Message Format

**Default: single-line `-m`, one concern per commit, ≤72 chars.**

```bash
gc "fix: reset warnings pane on proxy log path change"
# or
git -C c commit -am "fix: reset warnings pane on proxy log path change"
```

- Types: `feat` / `fix` / `refactor` / `docs` / `chore`
- Max 72 chars
- Pick dominant concern if mixed
- No Co-Author footer for routine commits

**Multi-line HEREDOC ONLY when ALL are true:**
- Breaking change, migration, or architecturally significant refactor
- Body genuinely adds information beyond the subject line
- The reader of `git log` will benefit from the extra context

```bash
git -C c commit -am "$(cat <<'EOF'
refactor: migrate X from Y to Z

Breaking: consumers of Y must update to new signature (see MIGRATION.md).
EOF
)"
```

HEREDOC for routine fixes is waste. Single-line `-m` is the default.

##### Multi-Repo Commits

When committing multiple repos (e.g., project + plugin source):
- Run the full flow for each repo sequentially
- Plugin-sync the plugin repo AFTER its push

##### Rules (Safety Protocol)

- NEVER amend existing commits
- NEVER force push
- NEVER skip hooks (`--no-verify`)
- NEVER modify git config
- NEVER create empty commits
- If push fails → report error, do NOT retry
- Commit only when user explicitly asks

### Grep
- **Brace escaping:** literal braces must be escaped — use `interface\{\}` to find `interface{}` in Go code. Without escaping, the pattern silently matches nothing.
- **Multiline:** by default patterns match within single lines only. For cross-line patterns (e.g. `struct \{[\s\S]*?field`), pass `multiline: true`.

### Glob
- **Sort order:** returns paths sorted by **modification time** (newest first), NOT alphabetical. First result = most recently modified file.

### Read
- **Line limit:** reads up to 2000 lines by default. Use `offset` + `limit` parameters for larger files.
- **Output format:** `cat -n` format — `line_number\tcontent`. NEVER include the `line_number\t` prefix in Edit's `old_string` or `new_string`.
- **Images:** can read PNG, JPG, etc. — presented visually as a multimodal model.
- **PDF:** files with >10 pages MUST include a `pages` parameter (e.g. `"1-5"`). Omitting it on large PDFs causes a tool failure. Max 20 pages per request.
- **Jupyter:** can read `.ipynb` notebooks — returns all cells with their outputs.
- **Directories:** Read cannot read directories. Use `ls` via Bash.
- **Empty file:** returns a system-reminder warning in place of content — do NOT interpret the warning as actual file content.

### Edit
- **Read first:** MUST call Read at least once before Edit. Tool errors if not.
- **Indentation:** preserve EXACT indentation as it appears AFTER the line-number prefix. Prefix format is `line_number\t` — NEVER include it in `old_string` or `new_string`.
- **Uniqueness:** FAIL if `old_string` is not unique in the file. Remedy: expand the match string with more surrounding context, or use `replace_all`.
- **replace_all:** use for rename-across-file operations (variable rename, import path change, etc.).

### Write
- **Existing file:** MUST call Read first. Tool fails without it.
- **Edit over Write:** for existing files, prefer Edit (sends only the diff). Write sends the full content every time.
- **No docs:** NEVER create `*.md` or README files unless explicitly requested by the User.

---

## Monitoring Self-Audit

- **waste_pane** (Monitor Window 4 right): check 1-2× per session. Expand top offenders. If the same command-prefix keeps appearing: that's a rule violation, stop and rethink.
- **warnings_pane zero-results**: repeated zero results on the same topic = Grep/Glob gunshot violation (Rule 6).
- **Per-session reports**: `dev/tool_use_analysis/YYYYMMDD_*.md` in Monitor_CC. Generated per session via ad-hoc scripts (one script per analysis, no shared library).

## What this skill does NOT do

- Does not strip tool_result content at the proxy. That's a separate concern (result-waste, tracked under a different bead).
- Does not enforce at commit time. This is advisory behavior through rule-awareness. The monitor is the feedback loop.
- Does not maintain a library or justfile. Every analysis script is one-off.
