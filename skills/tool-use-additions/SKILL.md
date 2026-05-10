---
name: tool-use-additions
description: Recurring tool-use error patterns extending the static tool-use rules — concrete pre-action checks for Bash/Edit/Read/Write derived from observed-in-the-wild failures.
---

# Tool-Use Additions

Extension of the static tool-use rules in `~/.claude/shared-rules/global/tool-use.md`. Assume those rules are known and active. This skill adds: concrete pre-action checks for the failure classes that recur despite the static rules being in place.

Every entry below pairs a real failure mode with the literal error message and the verification step to perform BEFORE issuing the call.

---

## Pre-Bash Checks

| Pattern | Error message (literal) | Pre-check |
|---|---|---|
| `sleep N && <other>` | `Blocked: sleep N followed by: <other>` | If literal token `sleep` appears: only `sleep N && echo done` with `run_in_background=true` is allowed. Anything else → restructure (foreground call with `timeout=` parameter, or write progress to `/tmp/<name>.log` and finalize). |
| `git diff dev` / `git log dev` (any subcommand against `dev`) | `fatal: ambiguous argument 'dev': both revision and filename` | Repo has `dev/` directory at root → ALWAYS append trailing `--` to disambiguate: `git -C <repo> diff dev --` / `git -C <repo> log dev --oneline --`. Or compare against `main` / `origin/dev` instead. |
| Multiple Bash calls in same response | `<tool_use_error>Cancelled: parallel tool call Bash(...)` | One Bash per turn. Multi-step ops: chain with `&&` or `;` in a single command, OR split across sequential turns. Other tools (Read, Edit, Grep, Glob) are parallel-safe; only Bash gets cancelled. |
| `cmd_a && cmd_b` where `cmd_b` may exit non-zero on a normal correct case | `Exit code 1` (chain aborted on first non-fatal step) | Diagnostic chains (`grep` no-match, `ls` empty, `test -f` missing) use `;` not `&&`. `&&` only when N+1 truly depends on N's success: build before test, mkdir before write. Self-test: would step N+1 exit non-zero in a normal correct case? Yes → `;`. |
| Multi-line Bash chain ending with `[ -f X ] && Y` (or any conditional that may exit 1) | `Exit code 1` even though every line printed correctly — Monitor TOOL ERRORS pane fires | The Bash call's exit code = the LAST command's exit code. A diagnostic dump where everything printed but the LAST step is `[ -f path ] && tail` will return 1 if `path` doesn't exist, even when all upstream lines succeeded. Self-test before issuing: read the LAST line of the chain — if it's `[ ... ] && X` or `grep ... && X` or any conditional-then-action, either (a) drop the `&&` guard and do `[ -f path ] || true; [ -f path ] && tail` style, (b) restructure as `if [ -f X ]; then Y; fi` (returns 0 when X missing), or (c) end the chain with `; true` to force exit 0. The Monitor catches all non-zero Bash exits as TOOL ERRORS regardless of stdout — clean diagnostic output is not enough. |
| Verbose script outputs | (no error — context flooding) | Dev scripts / build / test runs: `> /tmp/<name>.log 2>&1` then `tail -20`. Direct-to-context only for signal output (search results, structured tool returns). |
| Long-running command exceeds default 2 min | (timeout hang or aborted call) | Pass `timeout=600000` (10 min max) on the Bash call. Or restructure into shorter steps. |

## Pre-Edit / Pre-Write Checks

| Pattern | Error message (literal) | Pre-check |
|---|---|---|
| Edit/Write before any Read in this session | `File has not been read yet. Read it first before writing to it.` | Mandatory Read on the exact file before Edit or Write. Per-session; "I read it last session" does NOT count. The Read can be in the same response, just before Edit. |
| Edit `old_string` not unique | `String to replace not found in file.` (or matches multiple) | Either expand `old_string` with surrounding context until unique, or use `replace_all: true` for rename-like changes. Verify uniqueness with a grep first if uncertain. |
| Edit `old_string == new_string` | `No changes to make: old_string and new_string are exactly the same.` | The diff is a no-op — re-read the file to confirm what's actually there before re-trying. |
| File modified externally between Read and Edit | `File has been modified since read, either by the user or by a linter. Read it again before attempting to write to it.` | If user might have edited (between turns), or a worker touched the file, re-Read before Edit. |

## Pre-Read Checks

| Pattern | Error message (literal) | Pre-check |
|---|---|---|
| Read on file >256 KB | `File content (Xkb) exceeds maximum allowed size (256KB). Use offset and limit parameters to read in chunks.` | For large files: grep first to find the target, OR Read with `offset=N, limit=M`. Never blind-Read a file you don't know the size of when it might be large (logs, JSONL, generated reports). |
| Read on file >25 000 tokens | `File content (X tokens) exceeds maximum allowed tokens (25000). Use offset and limit parameters to read in chunks.` | Same fix: grep + targeted Read with offset/limit. |
| Read on a file that doesn't exist | `File does not exist. Note: your current working directory is …` | Verify path with `ls` first if path is reconstructed from memory. Common typos in this codebase: `.claire/` (should be `.claude/`), `..claude/` (double-dot, no slash — never valid). |
| Read on a worktree path | (no error — but causes CLAUDE.md re-injection) | Worktree files (`.claude/worktrees/...`) → use Bash `cat` / `head` / `git show` instead of the Read tool. Worktrees have their own CLAUDE.md which gets re-injected on every Read tool call to a worktree path. |
| Read on a directory | `Read tool cannot read directories.` | Use Bash `ls` instead. |

## Pre-Skill-Invocation Check

| Wrong name | Correct name |
|---|---|
| `github-cli`, `gh-cli`, `github-research` | `github-search` |
| `reddit-cli`, `reddit-search` | `agent-reddit-search` |
| `cleanup-and-index-pdf` | `cleanup-and-index` (or check `available-skills` system-reminder) |

When an invocation fails with `Unknown skill: X. Did you mean Y?`: take the suggested `Y`. Otherwise consult the `available-skills` system-reminder injected at session start before re-attempting.

## Path Verification

| Wrong | Right | Why |
|---|---|---|
| `/Users/.../.claire/worktrees/...` | `/Users/.../.claude/worktrees/...` | Tokenizer-level typo, `i+r` instead of `u+d`. Common when reconstructing worktree paths from memory rather than relative-pathing. |
| `..claude/...` | `../claude/...` or absolute path | `..` is parent-traversal only when followed by `/`. `..<letter>` is always a typo. |
| `~/.local/bin/<name>` (in plugin code) | `~/.local/bin/<name>` (verified once) | New CLI wrappers go to `~/.local/bin/` (XDG-standard, in PATH for both interactive and tool-use shells). Not `~/bin/` — that's not in CC's tool PATH. |

## Worktree Branch-Sync Before Followup-Send

When sending a follow-up to an alive worker that has been idle across one or more merges into `dev`, prefix the message:

> "FIRST: in your worktree, run `git -C <worktree-path> fetch origin dev && git -C <worktree-path> merge origin/dev` to pull commits since you last ran. Verify with the relevant grep on touched files. THEN do the work: …"

Without sync, worker's branch tip is behind current `dev` and the merge will conflict at the end.

## Self-Audit

When you hit any error in this list a second time within a session: STOP, re-read this skill, and verify the pre-check IS being applied before EVERY relevant call going forward. The point of the skill is forward-looking discipline, not retroactive understanding.

## RAG: Multi-Model Awareness

The RAG box exposes multiple model variants per class (embedding, reranker) plus splade. The full preset list is dynamic — never assume the three legacy names (`embedding`, `reranker`, `splade`) cover everything.

**Discovery:**

```bash
rag-cli server presets             # human-readable list of all configured presets
rag-cli server presets --json      # JSON for scripts
rag-cli server status              # which preset(s) currently running + health
rag-cli server list                # all running servers (presets + arbitrary) with idle countdown
```

`rag-cli server presets` shows: name, mode (embedding/rerank/splade), model_path, default_port, and a `default` flag (true = used by `rag-cli server start` without a name + by `ensure_ready` for search/index workflows).

**Switching a variant:**

```bash
rag-cli server stop embedding-8b
rag-cli server start embedding-0.6b
```

Client-side `find_server_url("embedding")` does a prefix-match across all running servers — `embedding-0.6b` will then serve search requests until you switch back. Same for `reranker`. Splade has only one variant.

**Starting non-default variants:**

`rag-cli server start` (no args) starts only the entries with `default=true` in `presets`. To run a non-default variant: `rag-cli server start <full-name>` (e.g. `start reranker-8b`). Single-instance enforcement is per-name, not per-class — both `embedding-8b` and `embedding-0.6b` can run in parallel if GPU memory allows, and `find_server_url("embedding")` will pick the FIRST one found in `SERVERS` insertion order (the marked default).

**Anti-patterns:**

- Assuming `embedding` / `reranker` / `splade` are the only valid preset names — they're not, they're prefixes. Use `rag-cli server presets` to see the full list.
- Hardcoding preset names in Monitor display code or downstream scripts. Always pull from `rag-cli server presets --json`.
- Calling `start_arbitrary` to launch a known model variant — that bypasses preset config. Use `rag-cli server start <name>` instead so the entry has `default_port`, `extra_flags`, and `timeout` from `SERVERS`.

## RAG-CLI — Tool Reference

| Command | When |
|---|---|
| `rag-cli search_hybrid <query> <collection>` | Default for content search. Vector + BM25 + RRF + rerank in one call. |
| `rag-cli search <query> <collection>` | Pure semantic (dense only). When BM25 stems hurt. |
| `rag-cli search_keyword <query> <collection>` | Exact terms — function names, column names, parameter identifiers. AND across words, stems. |
| `rag-cli read_document <coll> <doc> <chunk> --before N --after M` | Expand context around a search hit. Max 10 before / 10 after. |
| `rag-cli list_collections` | Collections + chunk counts. |
| `rag-cli list_documents <coll> [--document PATTERN]` | Document names in a collection. `%` wildcard. |

Defaults: `--top-k 20` (10–50 valid). `--document` filter on any search command narrows to matching doc names.

When a search hit's chunk doesn't contain the full answer, expand via `read_document` on the hit's `chunk_index` — that IS the way to handle decision files split across multiple chunks. Do not fall back to a raw direct-read on the source file.

## RAG-meta: Status-Quo via RAG

Trigger: project has `.rag-docs.json` at root → there is a `<Project>-meta` collection containing decisions/, DOCS.md, CLAUDE.md.

Status-quo questions are answered by RAG, not by direct-read of `decisions/`:

- "What is the IST of X?"
- "How does Y work / why is Y configured this way?"
- "What was decided about Z?"
- "Where is constraint W documented?"

```bash
rag-cli search_hybrid "<query>" <Project>-meta
```

The returned chunk IS the answer. No follow-up direct-read of the same file.

Direct-read on the full decision file ONLY when:
- the file is being EDITED (need all sections in view)
- the file was edited THIS session and RAG hasn't been resynced (sync runs at recap)
- RAG returned no usable hit AND the path is known anyway
- the answer needs more than the chunk shows → expand via `read_document`, NOT raw direct-read

## Backlog of Concrete Cases (project-specific)

Patterns observed in actual session logs (`src/logs/tool_use_errors.jsonl` in Monitor_CC). Run `cc-errors --by summary` and `cc-errors --by tool` to see the current frequency distribution. When a class drops to zero across new sessions, the corresponding entry above is doing its job.
