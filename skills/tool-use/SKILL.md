---
name: tool-use
description: Tool-call hygiene. Reduces call-waste through concrete anti-patterns and preferred alternatives. Covers token efficiency, verbose output, tool selection, and per-tool behavior reference. Live feedback via Monitor_CC waste_pane.
---

# Tool-Use Skill

Goal: no large Bash-call where a small one works. Every tool_use input counts — tool_use JSON inflates with escaped newlines and quotes. Live feedback in Monitor_CC waste_pane (Window 4 right) shows current-session ratios ≥3.

## Hard Rules — Token Efficiency

### 1. Python: heredoc for one-shot, Write + Exec ONLY for iteration (binary rule)

**This is not a style preference. It is a measurable cost difference per probe:**

- One-shot probe via **heredoc** = **1 tool call** (`python3 << 'EOF' ... EOF`)
- Same one-shot via **Write + Exec** = **2 tool calls** (Write the file, then Bash to run it)

Write + Exec on a one-shot probe is pure waste — one extra tool call, one extra `tool_use` JSON payload, one extra `tool_result`, and a temp file left behind. The iteration-discount of Write + Edit **only** pays from run #2 onward, when Edit diffs replace full-heredoc re-transmission. There is no third option and no "Faulheit" / "cleaner / easier" justification — the call-count delta is the rule.

**Decision is binary, by reuse:**

1. **jq / grep / awk first** — purpose-built, shortest form. `jq -c 'select(.type=="error")' file.jsonl` beats 15 lines of Python every time. Use a one-liner when the data shape fits.
2. **Python heredoc** when Python is actually needed (multi-field comparisons, nested dict walks, shapes awk/jq struggle to express). One run, one heredoc, done.
3. **Write + Edit** ONLY when the SAME script will run a second time after edits. Switch from run #2, not before.

**Different script for a different question is a NEW one-shot.** Five probes answering five questions in one session = five heredocs, not five Writes. The signal is "will this exact script run again with changes" — not line count, not "it looks substantial", not "a file feels cleaner".

**`python3 -c`:** when the `-c` string exceeds 300 chars including escaping — switch to heredoc (or Write once iteration starts). Argument-level quote escaping in `-c` is worse than heredoc quoting for medium scripts.

Concrete failure (2026-04-23): `sidecar_inspect.py` was a one-shot probe (one question: "which entries have `stripped_sidecar_content` in modifications?"). Created via Write, run via Bash, result read once, thrown away. Two tool calls for what a heredoc would have done in one. No iteration followed. Pure call-count waste. Justification at the time was "Faulheit" — 2 calls instead of 1 is not laziness, it is a concrete cost.

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

### 8. `<persisted-output>` blocks: grep the full file, never settle for the preview

**Rule:** When a tool_result contains a `<persisted-output>` block (CC's truncation feature for large Bash outputs), use Grep / Read / cat on the persisted file path. NEVER stop at the `Preview (first NKB)` content.

CC injects this format when a Bash output exceeds its inline limit:

```
<persisted-output>
Output too large (NMB). Full output saved to: /Users/.../tool-results/<id>.txt

Preview (first 2KB):
... 2KB snippet ...
...
</persisted-output>
```

The preview is bait. It suggests "this is everything you can see" and the natural read is to draw conclusions from those 2KB alone. That is almost always wrong — the full data lives at the path and is one Grep / Read call away. Preview content is redundant the moment you grep the persisted file.

**Workflow:**
1. Extract the absolute path from `Full output saved to: <path>`.
2. **Grep first** — `grep <pattern> <path>` for targeted lookups (lowest context cost).
3. **Read with offset/limit** for ranges — `Read(file_path=<path>, offset=N, limit=M)`. CC's "too large" warning is conservative; direct Read on the persisted file works for files much larger than the inline tool-output limit.
4. **cat / head / tail** only when the file is small and you genuinely need contiguous content.

**The mistake to avoid:** answering questions, drawing conclusions, or planning next steps from preview content alone. If preview content looks like it answers the question, that is coincidence — the full file may contain the actual answer or a different signal entirely.

Concrete failure (2026-04-27): During the ham-bead audit review on Monitor_CC, three REQs (#66, #137, #145 of `api_requests_opus_monitor_cc_1777294641.jsonl`) contained `<persisted-output>` blocks. The preview was treated as the full output; the persisted files at `~/.claude/projects/.../tool-results/*.txt` were never grepped. User flagged: "anstatt dann alle infos zu holen die du brauchst stoppst du belässt es bei den preview infos. das entspricht aber nicht der wahrheit."

### 9. Read before Edit/Write — non-negotiable

The Edit and Write tools fail on files that haven't been read in the current session with `<tool_use_error>File has not been read yet. Read it first before writing to it.` There is no workaround — the call must be re-issued after a Read.

**Rule:** before any Edit or Write call on an existing file, call Read on the same path. ONE Read per file per session is enough — subsequent Edit/Write calls reuse the read state. Read followed by Edit in the same response is fine; both fire in order.

**Forbidden shortcut:** "I know the content already" or "I just edited this in another session" does NOT satisfy the requirement. The Read-state is per-session, not persisted across sessions.

The per-tool reference at the bottom of this file (Edit / Write sections) carries the same rule, but it gets overlooked because it lives in a reference table rather than the Hard Rules. This is a Hard Rule.

Concrete failure (2026-04-28 aggregate of 10 sessions): 4 of 23 failures were Edit-without-Read on `DOCS.md` and `sources.md` files (sources.md once, DOCS.md three times across `src/proxy/`, `src/input/`, plus the same `src/proxy/DOCS.md` again in a later session).

### 10. Branch-name ambiguity in repos with same-named directories

`git diff <branch>` and `git log <branch>` fail with `fatal: ambiguous argument '<branch>': both revision and filename` when a directory of the same name exists at the repo root. The classic case: a `dev/` directory (for dev-scripts, evals, etc.) plus a `dev` branch. Git cannot tell which you meant.

**Rule:** when the branch name collides with a directory in the repo, disambiguate with a trailing `--` to force the branch interpretation:

```bash
git -C <repo> diff dev --
git -C <repo> log dev --oneline --
```

Alternatives that also work:
- `git diff origin/dev` — remote-prefixed refs never collide with directory names
- `git diff main` — compare against trunk instead, when that's what you actually want

`workers-2` prescribes `git -C <project_root>/.claude/worktrees/<name> diff dev` for code review of worker branches. In a Monitor_CC-shaped repo (with `dev/` at root) this triggers the ambiguity error every time. Use `git -C <worktree> diff dev --` or `git -C <worktree> diff main` instead.

Concrete failure (2026-04-28 aggregate): 4 of 23 failures were `git -C <worktree> diff dev` exiting 128 with the ambiguity error. Monitor_CC has a `dev/` directory at root.

### 11. Diagnostic Bash chains: `;` not `&&`

`grep` returns exit 1 when no match is found. `find` returns 1 when its base path is partially missing. `ls` returns 1 on empty or missing directories. None of those are bugs — they are normal results that signal "no rows matched". But they break `&&`-chained commands halfway through, truncating the rest of the diagnostic.

**Rule:** for chains where each step produces independent output (status checks, multi-source probes, sanity diagnostics), separate with `;`. Reserve `&&` for cases where the next step genuinely depends on the previous one succeeding (commit before push, install before test, mkdir before write).

```bash
# WRONG — grep no-match aborts the rest
echo "=== refs ===" && grep X file && ls dir/ && echo "=== done ==="

# RIGHT — each step runs regardless
echo "=== refs ==="; grep X file; ls dir/; echo "=== done ==="
```

Same principle: `2>/dev/null` swallows stderr but does NOT change exit codes — adding it does not save the chain.

Concrete failure (2026-04-28 aggregate): ~4 of 23 failures were `&&`-chained diagnostic blocks (multi-`echo` headers around `grep` / `find` / `ls`) where a benign no-match exit-1 killed the chain. Output was half-rendered, the actual probe output never arrived.

### 12. `sleep N && command` is runtime-blocked — use background timer

CC's tool-use runtime blocks any Bash call of the form `sleep N && <command>` (or `sleep N; <command>`, or `sleep N && echo X && <command>`) and returns `<tool_use_error>Blocked: sleep N followed by: <command>`. The block fires before any sleep happens — there is no way around it inside a single Bash call.

**Rule:** to wait and then act, split the wait from the action:

1. Background timer: `Bash(command="sleep 120 && echo done", run_in_background=true)` — the bare `sleep N && echo done` form is allowed only as the entire backgrounded command, not chained with anything else.
2. Wait for the completion message (the user's "Background command completed" notification arrives as a normal turn input).
3. NEXT turn: run the actual check as a fresh foreground call (`worker-cli status <name> c`, `ps aux ...`, etc.).

This is also the canonical worker-polling flow described in `opus-workers-2`. The block in tool-use exists to prevent foreground sleeps from stalling the API stream.

**Forbidden:** chaining `sleep` with any other command in the same Bash call, foreground OR backgrounded (except the literal `sleep N && echo done` background-timer form). The runtime blocks both directions.

Concrete failure (2026-04-28 aggregate): 2 of 23 failures were exactly this pattern (`sleep 60 && worker-cli status req-cascade-doc c`; `sleep 60 && echo "=== 60s post-restart ===" && ps aux | grep workflow ...`). The runtime block fires immediately, so the cost is the failed tool call plus a re-issue, but it pollutes the call history and breaks the polling flow.

### 13. Worktree path is `.claude/worktrees/` — never `.claire/`

The worktree directory in every project is `.claude/worktrees/<name>/`. There is no `.claire/` anywhere. But there is a recurring tokenizer-level typo where Edit, Write, Read, or Bash calls inside worker sessions land on `.claire/worktrees/...` paths and fail with `File does not exist` (or, for Bash `cd`, with a no-such-directory error).

**Rule:** before any file operation that names a worktree path explicitly, verify the literal substring `.claude/worktrees/` (with a `u` and `d`, not an `i` and `r`). When working from cwd inside a worktree, prefer relative paths or the `c` shortcut for `worker-cli` rather than reconstructing the absolute path — the typo only happens when the model rebuilds the path string by hand.

**Detection:** if a tool call returns `<tool_use_error>File does not exist. Note: your current working directory is /Users/.../.claude/worktrees/<name>.` — the cwd is correct but the path argument has the typo. The fix is rewriting the file_path with `.claude/`.

Concrete failure (2026-04-28 aggregate of 44 sessions): 7 of 66 failures (16% of the new-batch cluster, largest new pattern) had `.claire/worktrees/` in the tool input. Same-session counts: ttfb-fix worker had 96 occurrences of `.claire` against 126 of `.claude` — the model writes both forms inside one session. Affected tools: Edit (5×), Read (1×), Write (1×). Path examples: `.claire/worktrees/ttfb-fix/src/proxy_display/pane.py`, `.claire/worktrees/ctrl-r-heal/src/tmux_launcher.py`, `.claire/worktrees/tag-3audits/dev/tool_use_analysis/tag_presence_audit.py`.

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

### Heredoc — three distinct cases

Not every heredoc is the same problem. Three classes, three different answers.

**Case 1 — Python / analysis: one-shot = heredoc. Iteration = Write + Edit. Binary.**

`python3 << 'EOF' ... EOF` is the form for a one-shot probe — 1 tool call, no temp file.

Switch to Write + Edit the moment you're about to run the SAME script a second time after editing it. Not third run, not fourth — from run #2. The switch pays because Edit diffs are smaller than re-transmitting the full script.

Different script for a different question is NOT iteration. It is a new one-shot → new heredoc. Running five distinct probes in one session means five heredocs, not five Writes.

Still: jq / awk / sed first when the question fits a one-liner. Python (via heredoc) is for shapes those don't express cleanly.

**Case 2 — File creation heredoc (Rule 2 above): NEVER.**

`cat > file << 'EOF'` and `echo >` can leak shell context into the file content (e.g. `EOF 2>&1 | head -10` accidentally appended). Write tool is atomic and safe. Zero exceptions except the narrow single-line-append pattern noted in Rule 2.

**Case 3 — Shell-argument heredoc for a one-shot command: OK.**

Bead description, multi-line git commit body, one-off `curl -d`-style payload. The content is a single argument to a single command, never executed again, never edited. The alternatives (Write tool + `Bash` with `$(cat /tmp/file)`) and heredoc inline carry the **same content bytes** in tool_use JSON — the only difference is the heredoc version skips one tool-call overhead and does not leave a temp file behind.

```bash
# OK — one-shot shell argument
bd --repo <path> create --title "..." --type task --description "$(cat <<'EOF'
<full markdown description>
EOF
)"
```

Case 3 applies specifically to multi-line shell-command arguments that the user will never iterate on. For anything that might be re-run, re-shaped, or debugged later, fall back to Write + `$(cat ...)` so the content is editable via the Edit tool.

**Decision flow:**

1. Is the content Python / analysis code? → try jq/awk/sed first. If Python is needed: one-shot (one run, throw away) → heredoc. Same script will run a second time after edits → Write + Edit from run #2.
2. Is the goal to create a file? → never heredoc. Write tool.
3. Is it a multi-line argument to a one-shot shell command (bd create, git commit -m body, curl -d payload)? → heredoc inline is the clean form. One tool call, no temp file.
4. Will the same multi-line content be reused, revised, or referenced across multiple calls? → treat as iterated. Write + Edit.

### Bead descriptions

Case 3. Bead descriptions are written once and not iterated.

```bash
bd --repo <path> create --title "..." --type task --description "$(cat <<'EOF'
<full markdown description>
EOF
)"
```

If `bd` later grows a `--description-file` flag, Write + flag is equivalent.

### Git commit messages

Single-line `-m` is the default for routine commits (see `Commit Message Format` below).

Multi-line body only when it genuinely adds information for `git log` readers — and when it does, Case 3 applies: heredoc inline, no temp file.

```bash
git -C <repo> commit -am "$(cat <<'EOF'
refactor: migrate X from Y to Z

Breaking: consumers of Y must update to new signature (see MIGRATION.md).
EOF
)"
```

Multi-line body is justified when all three hold: breaking or architecturally significant change, body adds real information beyond the subject, `git log` readers benefit from the extra context. Otherwise single-line `-m` — heredoc for routine fixes is waste.

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
| Check worker status | `worker-cli status <name> <project_path>` — outputs `idle 72%` / `working 28%` / `exited` |
| Capture pane to file | `worker-cli capture <name> <project_path>` |
| Read last N lines | `tail -n <N> <output_file_from_capture>` |
| Get clean last response | `worker-cli response <name> [project_path]` |
| Merge worker branch | `worker-cli merge <name> <project_path>` |
| Kill worker | `worker-cli kill <name> <project_path>` |
| Send message to worker | `worker-cli send <name> <message> [project_path]` |
| Spawn worker in worktree | `worker-cli spawn <name> <prompt_file> <project_path> [model]` |

> `<project_path>` = `c` in the vast majority of cases.

`worker-cli response <name>` is the default for reading idle workers — returns clean text from session JSONL (~200-2000 chars, no UI trailers or prompt echo). `worker-cli capture <name>` + `tail` + `sed`-filter is the fallback when `response` misses context (rare — Phase-A partial-report situations). Capture dumps 2-5k chars of CC UI + prompt echo.

Polling flow (timer → status → response, with flow-level discipline like "one timer at a time", foreground vs background, etc.) is orchestration, not a command-level concern — see opus-workers-2 "Timer & Polling Flow".

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
2. **Commit** — `gc "<message>"` (if cwd inside repo) OR `git -C <repo> commit -am "<message>"` (explicit path)
3. **Post-check** — `git -C <repo> status --short` → empty = proceed; non-empty with non-`.beads/` paths → stage + commit again
4. **Push** — `git -C <repo> push` (retry with `-u origin <branch>` on first push)
5. **Plugin-sync** (if plugin repo) — run AFTER push

##### Commit Message Format

**Default: single-line `-m`, one concern per commit, ≤72 chars.**

```bash
gc "fix: reset warnings pane on proxy log path change"
# or
git -C <repo> commit -am "fix: reset warnings pane on proxy log path change"
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
git -C <repo> commit -am "$(cat <<'EOF'
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
