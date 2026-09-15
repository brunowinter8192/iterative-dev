# 2026-09-16 — comment/docstring purge + DOCS.md format conformance

Worker task on branch `sweepitdev` (same worktree as milestone 1, the cohesion/concern-split
milestone). This is milestone 2: remove every comment and docstring outside the three section
markers from the 21 files Main scanned, and rewrite every touched directory's DOCS.md to the
Role/Public Interface/Flow/Modules/State format. Scope: `src/spawn/`, `src/git/`, `src/pipeline/`,
`dev/desktop_targeting/`, `dev/model_selector/`, `dev/worker_spawn/`, `dev/session_pipeline/`,
`dev/git_automation/`, `dev/poread_cli/`.

## How the triage was decided

For every comment/docstring block, I read the file's own DOCS.md (as it stood before I touched
it) and the process-docs entries for that area. If the substance was already there (even
loosely paraphrased), I deleted the comment with nothing else. If not, I copied the comment's
text verbatim into this file below, then deleted it from the code. A handful of one-line
comments that were pure restatements of the very next line of code (e.g. `# Print structured
report` directly above `def print_report(...)`) I treated as "covered" even when no DOCS.md
sentence matches them word-for-word — preserving them in process-docs would just be re-typing
the function signature, which is not the kind of insight process-docs exists for. Everything
else got relocated. Decorative section-divider comments (`# ── Foo ──`) were treated the same
way — trivial, deleted, not relocated.

**One deliberate deviation from "every docstring is a violation":**
`dev/desktop_targeting/probe.py`'s module docstring was not a passive comment — `_parse_args()`
passed it to argparse as `description=__doc__`, so deleting it would have changed the tool's
`--help` output, a real behavior change. I moved the text verbatim into a module-level string
constant (`_HELP_TEXT`) and pointed `description=` at that instead. This is not a docstring by
Python's own definition (a docstring is specifically the first statement's bare string literal;
`_HELP_TEXT = """..."""` is an ordinary assignment, and it sits after the import block, not
first), so it satisfies the letter of the rule, and it keeps `--help` byte-identical — verified,
see Verification below. Flag this if a future pass wants it gone entirely; it would need a
`--help` text change signed off first.

## Relocated comment/docstring substance, verbatim

### src/spawn/_capture_clean.py

Header block (module-level, above `# INFRASTRUCTURE`):
```
_capture_clean.py — clean+scope worker pane output for worker_capture_clean
Usage: python3 _capture_clean.py <pane_file> <worker_name>
  pane_file: raw tmux capture-pane -p -S - output; caller is responsible for cleanup
  worker_name: used in the output header
Output: "=== capture from <name> (since last prompt, N chars) ===" + cleaned body
```

Inline, in `_clean` (blank-line handling):
```
blank line exits diff block
```

Above what is now `_is_chrome_line`:
```
Bottom widget chrome (safety: may survive in body on edge cases), collapse markers, thinking spinners
```
(the "safety: may survive in body on edge cases" part is the substance — these patterns are
already stripped upstream by `_trim_bottom_widget`; this second check inside the per-line loop
is deliberate defense-in-depth for edge cases where they survive into the body.)

Above what is now `_process_diff_block`:
```
Diff block: Update()/Create() header enters; sticky until blank or next ⏺ tool-call
```

Inline, in the diff-block sticky-exit branch:
```
Sticky: only a new ⏺ tool-call exits diff; everything else (⋯, wrap) is dropped
```

### src/git/check.py and src/git/staged.py

Both files carried the identical comment above `_extract_stage_path` (duplicated code, not
just duplicated comment — `staged.py` has its own copy of the helper):
```
For RM entries like 'old -> new', return new path only (the one to git add)
```

### src/spawn/spawn.py

Above `_resolve_worker_model`:
```
Resolve the worker model when no explicit CLI argument was given: "worker" key from
~/.claude/shared-rules/model_selection.json (menubar Models tab), else the hardcoded
fallback. Never raises — a missing/unreadable/malformed file or a missing/empty key all
degrade silently to the fallback; a spawn must never fail because of this file.
```
The "menubar Models tab" detail (where a human actually edits this config) is the one piece not
already covered by `src/spawn/DOCS.md`'s longer prose about `_resolve_worker_model`.

### dev/model_selector/verify_spawn_model_resolution.py

Inline, before the argparse-resolution section of the orchestrator:
```
---- "explicit arg wins" as argparse itself resolves it (real parser, not reimplemented) ----
```
Substance: the argparse-based cases deliberately drive the real `argparse.ArgumentParser`
rather than reimplementing its resolution logic in test code, so the test can't silently drift
from real parser behavior.

### dev/git_automation/probe_umlaut_staging.py

Inline, in `make_repo`:
```
matches the global commit-msg identity guard (~/.githooks/commit-msg) so throwaway
commits aren't rejected by it
```

Above `_force_writable`:
```
Undo any chmod-000 lockouts (loud-failure case) so tempdir removal doesn't fail, then remove
```

### dev/worker_spawn/test_capture_clean.py

Above the `FIXTURE` constant:
```
Hand-built fixture covering every filter case.
Lines present:
  boot welcome box (╭…╰), thinking spinner (✻), Read tool + ctrl+o sub-line,
  Update() header + diff body (+/-) + Added counter, Bash() tool header + output,
  Update() header with ... collapse + post-collapse body + wrap continuation,
  worker prose + checklist, collapse ellipsis, rule, bare ❯, Sonnet footer, bypass
```

### dev/desktop_targeting/move_test.py

`get_window_space` docstring:
```
Primäre Verifikation: CGSGetWindowWorkspace → direkte per-Fenster Space-ID.

Gibt None zurück wenn der Call fehlschlägt (z.B. TCC-Einschränkung).
Kein try/except — Ausnahmen (Segfault etc.) sollen sichtbar sein.
```

`get_window_spaces_copy` docstring:
```
Sekundäre Verifikation: CGSCopySpacesForWindows (Array-Return).
Liefert auf macOS 15 für fremde Prozess-Fenster häufig [] (TCC-Einschränkung).
```

`run_test` docstring:
```
Liest before-space, ruft Move auf, liest after-space.

Kein try/except auf dem Move-Call — TCC/Permission-Fehler sollen unverdeckt erscheinen.
Gibt True bei PASS zurück.
```
Note: `process-docs/desktop_targeting/desktop_targeting_sidecar.md`'s "Re-verification 2026-05-29"
section found that `CGSGetWindowWorkspace`/`SLSCopySpacesForWindows` are NOT reliable for a
freshly created window's live position (they report the active Space regardless) — that finding
is about a different, now-shelved production module (`src/desktop/desktop_targeting.py`), not
this probe, but it directly bears on whether `get_window_space`'s "Primäre Verifikation" framing
here is still trustworthy. Not fixed as part of this comment-purge milestone — out of scope.

### dev/desktop_targeting/objc_bridge.py

```
CGSCopySpacesForWindows: returns CFArrayRef of space IDs for given window IDs
```
```
CGSGetWindowWorkspace: single-window space query (alternative verification)
```
```
CFUNCTYPE refs — module-level to prevent GC from corrupting IMP table
```

### dev/desktop_targeting/spaces.py

`choose_target_space` docstring:
```
Gibt (active_space, target_space) zurück.

override: explizite Space-ID. None → auto: erster nicht-aktiver Space auf
demselben Display (same-Display-Constraint um Cross-Display-Artefakte auszuschließen).
```

## Salvage from src/git/DOCS.md

Cut to reach the Purpose/Reads/Writes/Called-by/Calls-out module format (the pre-existing
Purpose paragraphs for `check.py` and `commit.py` carried far more than one sentence) and to
drop the `## Usage`/`## Gotchas` sections, which aren't in the target schema:

`check.py`'s full original Purpose paragraph:
```
Pre-commit analysis + optional auto-staging. Classifies files into staged/unstaged/untracked/skipped, detects new imports in unstaged .py files, checks hook health. `parse_status` reads `git status --porcelain -z` (NUL-delimited, unquoted paths) rather than the default text format, which C-quotes any non-ASCII/backslash/quote/control-char path into an escaped literal (`"anh\303\244nge/x.pdf"`) that no longer matches a real file — `-z` sidesteps that entirely; rename entries are reassembled into the same `"from -> to"` display string the rest of the module already expects. `stage_all` runs `git add --` per path via `subprocess.run` directly (not through `run()`, which discards returncode/stderr), and cross-checks successes against `git diff --cached --name-only -z` (`verify_staged`) before calling a path staged — a path reported as staged is always actually in the index.
```

`commit.py`'s full original Purpose paragraph:
```
One-call stage-all + commit, worktree-correct (no path resolution/stripping — `repo_path` used as-is, `git` itself resolves the right worktree branch). Reuses `parse_status`/`classify_files`/`stage_all` from `check.py` — single source of truth for `SKIP_PATTERNS` and for the `-z`-based staging fix. `stage_all` now returns `(staged, errors)`; a non-empty `errors` list (e.g. an unreadable file that makes `git add` fail) aborts before `do_commit` runs — non-zero exit, no commit made, never a silent partial commit.
```

`## Usage`:
```bash
python3 -m src.git.check <repo-path>                # analysis only
python3 -m src.git.check <repo-path> --auto-stage   # analysis + stage all (normal flow)
python3 -m src.git.staged <repo-path>               # manual staging verification (fallback)
python3 -m src.git.post <repo-path>
python3 -m src.git.commit "<message>" [repo-path]   # stage-all + commit, one call
```

`## Gotchas` (full section):
```
`check.py`'s `resolve_project_path` (in the `bin/git-check` wrapper, not this module) strips `.claude/worktrees/…` back to the parent repo — worktree-hostile. `commit.py`'s wrapper (`bin/gcommit`) deliberately does NOT do this: `repo_path` defaults to the caller's `pwd` (captured before the wrapper `cd`s into the plugin root) and is passed through unresolved — `git` itself finds the correct worktree branch from `cwd`.

`run()` must `rstrip()`, NOT `strip()`. `git status --porcelain`'s first line carries a leading status-column space (e.g. `" M file.py"` = unstaged modification); a whole-blob `.strip()` eats that space when it's the first char of the captured stdout, shifting `parse_status`'s `line[:2]`/`line[3:]` split and silently dropping the file from staging. Any future `run()`-consuming parser that reads leading characters needs this same care.

`SKIP_PATTERNS` includes bare `"venv"`/`".venv"`/`"node_modules"` — catches worktree dependency symlinks (e.g. `venv -> ../real/venv`), which `git status` reports without a trailing slash (unlike real directories), so the repo's `.gitignore` `venv/` entry doesn't match them.

`parse_status` must use `git status --porcelain -z`, never the default text format — the default C-quotes any non-ASCII/backslash/quote/control-char path (`core.quotePath=true`), and the quoted-escaped string is not a valid filesystem path, so a later `git add` on it silently no-ops instead of staging the real file. `-z` also reverses the rename field order (new path first, then old path, each NUL-terminated) — `parse_status` consumes the extra token when `R`/`C` appears in either status column, and re-glues it into the same `"from -> to"` string the rest of the module (`_extract_stage_path`, report printers) already assumed, so nothing downstream needed to change.

`verify_staged` matches directory-entry paths (trailing `/`, from a brand-new untracked folder that `git status` collapses to one line) by prefix, not exact match — `git diff --cached --name-only` only ever lists individual files, never the directory itself, so an exact match would false-positive every new folder as a staging failure.
```

## Salvage from src/spawn/DOCS.md

`tmux_spawn.sh`'s full original Purpose paragraph (worker model resolution, the 2026-08 5th
hardcode-site fix, `worker_capture_clean`, worker permission mode, status detection, and the
`spawn_claude_worker` prompt-inject flow — all previously crammed into one module's Purpose
field):
```
Bash library — worker lifecycle: spawn, list, status, capture, send. Handles proxy injection for Monitor_CC sessions automatically when `/tmp/.monitor_cc_proxy_*` marker exists. **Worker model resolution (2026-08, model-selector milestone 3):** `_resolve_worker_model()` — returns the `"worker"` key from `~/.claude/shared-rules/model_selection.json` (env-overridable via `MODEL_SELECTION_FILE`, for tests) if present and non-empty, else the hardcoded fallback `claude-sonnet-5`; uses `jq` with the same `2>/dev/null || true` fail-open idiom already established at the `hooks.json` read in `_worker_detect_status` (this file runs under `set -euo pipefail`). Used as the default in `spawn_claude_worker`'s and `spawn_claude_worker_from_file`'s `${4:-$(_resolve_worker_model)}` (bash short-circuits — never called when an explicit 4th arg is given), and in `worker_revive`'s fallback (`[ -z "$model" ] && model="$(_resolve_worker_model)"`) — revive's own stored `WORKER_MODEL` (the model the worker was ORIGINALLY spawned with) always wins over this; the config only applies when that stored value is itself absent. **For `worker-cli spawn`, `spawn.py`'s own resolution runs first** (see `spawn.py`'s entry below) and hands this file an already-concrete model string, so `_resolve_worker_model()` here isn't reached on that path EITHER WAY — by design, not a gap: `spawn.py` resolving once in Python and passing the result down is the intended shape. This function is load-bearing for direct callers of `spawn_claude_worker`/`spawn_claude_worker_from_file` that omit the model argument, and for `worker_revive`. **2026-08 fix (model-selector milestone 3):** a 5th hardcode site, `bin/worker-cli`'s own `spawn)` case, used to pre-resolve the "no model" case to a hardcoded literal BEFORE `spawn.py` ever ran — silently shadowing `spawn.py`'s resolution for every real `worker-cli spawn` call and making this milestone's fix dead code end-to-end. Fixed same milestone (`MODEL="${4:-}"` — passes an empty string through instead of pre-resolving); see `process-docs/model_selector/` (monitor-cc repo) for the full trace, including why the milestone's own file list didn't catch this.

`worker_capture_clean NAME [PROJECT_PATH]` — captures pane, scopes to output since last real orchestrator `❯` prompt, applies clean filter (see `_capture_clean.py`), prints to stdout. Called by `worker-cli capture` (default). `worker_capture` (raw pane to file) called via `worker-cli capture --raw`.

**Worker permission mode (2026-09-02):** workers launch with `--permission-mode acceptEdits`, not `--dangerously-skip-permissions` — the default `extra_flags` value in `spawn_claude_worker`/`spawn_claude_worker_from_file` (callers may still override via the 6th arg) and the hardcoded flag in `worker_revive`'s runner script. Changed because Claude Code 2.1.258 introduced permission mode `auto`, which fires a Sonnet harm-classifier side request with the full transcript on every tool call when `--dangerously-skip-permissions` combined with a global `defaultMode: auto` setting — workers were paying that classifier cost on every tool call.

**Status detection (`_worker_detect_status`):** closed three-value vocabulary (2026-09-02) — `working`, `idle`, `dead`; `unknown` is retired (no consumer needs a "no data" placeholder anymore) and the old `limit reached` label is retired too (it conflated a real process death with a user ESC-interrupt, which now reads as `idle`). `dead` = cannot accept a message: `#{pane_dead}=1`, no `claude` descendant under the pane pid, or the session JSONL's last assistant-type entry is Claude Code's client-side context-limit marker (`message.model=="<synthetic>"` + text `Prompt is too long` + `isApiErrorMessage=true` + `error="invalid_request"` — every later input fails the same way until `/compact`/`/clear`; anthropics/claude-code #90113, #23377). The marker check reads only the last 200 lines (`tail`, not a full slurp) — the marker is always the newest assistant entry, and a multi-megabyte session JSONL must stay cheap under `wait`'s 5s poll cadence. `idle` = `hooks.json[session_id].status=="idle"` (Stop hook fired), OR status `working`/absent with `#{window_activity}` stale > 10s (mirrors menubar `discover.py:178-181`) — this single window_activity check now covers BOTH the ESC-interrupt case (process alive, Stop hook never fired, pane quiet) and every former "no data" case (fresh spawn pre-JSONL, no hook entry, unreadable hooks file) once the pane itself has gone quiet. `working` is the default: fresh activity, or no dead/idle signal fired. Fail-open throughout: any unreadable check falls through toward `working`, never toward a dead-end. All paths return exit 0. See `process-docs/worker_status/worker_force_stop_detection.md`.

**spawn_claude_worker — Prompt-Inject Flow:**
claude starts bare (no positional prompt arg — prompt never touches the cmdline).
After session creation, a readiness gate polls `tmux capture-pane` for `^❯`
(U+276F at col 0 = CC input-ready). 30s deadline; timeout → `return 1`.
Prompt is injected via `load-buffer / paste-buffer / send-keys Enter` (same
as `worker_send`). Fragility: `^❯` marker is CC-version-dependent — if the
glyph changes, gate times out and spawn fails explicitly; update the grep
pattern. See `process-docs/worker_spawn/worker_spawn_prompt_injection.md`.
```

`_capture_clean.py`'s Scope/Clean-filter detail paragraphs (below the 5-field block):
```
Scope: slices to lines after the last real orchestrator prompt (`_RE_REAL_PROMPT = r'^❯\s+\S'`); pre-trims bottom widget (rule/bare-❯/Sonnet footer/bypass) so the bare input box never wins the anchor. Fallback: full buffer + `⚠` warning when no prompt in scrollback.

Clean filter — **Strip:** boot welcome box (`╭…╰`), thinking spinners (`✻`), `ctrl+o to expand` collapse markers, CC diff body lines (indented `<linenum>[+/-]content` after `Update()`/`Create()` headers — counter `⎿ Added N` kept, body dropped), bottom widget chrome (rule/bare-❯/Sonnet/bypass). **Keep:** `Update()`/`Create()` headers, `Added N, removed M` counters, `Read()`/`Bash()` headers, prose, Bash output, checklists. Leading `⏺`/`⎿` glyphs stripped from lines where they are the first character.
```

`spawn.py`'s full original Purpose paragraph:
```
Worktree setup + worker session launch. Stdlib only — no fastmcp, no external deps. **Worker model resolution (2026-08, model-selector milestone 3):** the `model` CLI positional's argparse default changed from the hardcoded literal `"claude-sonnet-5"` to `None`, so `args.model` can be told apart from "not given" instead of colliding with a real value; `resolved_model = args.model or _resolve_worker_model()` — `_resolve_worker_model()` reads the `"worker"` key from `~/.claude/shared-rules/model_selection.json` (`MODEL_SELECTION_FILE`, env-overridable for tests), falling back to the hardcoded `"claude-sonnet-5"` on any error or a missing/empty key; never raises. `resolved_model` (always a concrete non-empty string, never the literal string `"None"`) is what actually reaches `spawn_workflow`/`tmux_spawn`. **Load-bearing for `worker-cli spawn` since the same milestone's follow-up fix:** `bin/worker-cli`'s own `spawn)` case used to pre-resolve its 4th positional to a hardcoded literal (`MODEL="${4:-claude-sonnet-5}"`) BEFORE ever invoking this module — `args.model` was never actually `None` on that path, so this module's own resolution never ran for a real `worker-cli spawn` call, making the whole worker-model-config feature dead code end-to-end despite every individual piece working correctly in isolation. Fixed in `bin/worker-cli` (`MODEL="${4:-}"` — passes an empty string through when no model arg is given, which argparse stores as `''`, which `args.model or _resolve_worker_model()` correctly treats as falsy). Verified end-to-end with a real subprocess call to `bin/worker-cli spawn` (not a sourced-function unit check) — see `process-docs/model_selector/` (monitor-cc repo) for the full trace and why the milestone's own file list missed this site.
```

`## Usage` (full section, including Cross-project Lifecycle, sidecar format, orphan cleanup):
```bash
# Via worker-cli (standard)
worker-cli spawn <name> <prompt_file> <project_path> [model] [--no-worktree]

# Direct (from plugin root)
python3 -m src.spawn.spawn <name> <prompt_file> <project_path> [model] [--no-worktree]
```
```
### Cross-project Lifecycle

When a worker needs to operate in a DIFFERENT repo from the one it was spawned into:
```
```bash
# 1. Spawn worker in the spawn project (creates spawn-side worktree + registry entry)
worker-cli spawn <name> <prompt_file> <spawn-project> [model]

# 2. Create + register a worktree in the target project (default branch = <name>)
worker-cli worktree <name> <target-repo> [branch]
# → creates <target-repo>/.claude/worktrees/<name> on branch <name>
# → appends "<target-repo>\t<branch>" to $REGISTRY_DIR/<name>.worktrees (sidecar)
# → echoes the absolute worktree path for use in the worker prompt

# 3. Worker does its work in the target worktree (path echoed above)

# 4. Kill cleans BOTH sides (spawn-side + all entries in the sidecar)
worker-cli kill <name>
```
```
**Sidecar format:** `$REGISTRY_DIR/<name>.worktrees` — one `<target-repo>\t<branch>` per line (tab-separated). Multiple cross-project worktrees for the same worker are each on their own line. `kill` reads and deletes this file automatically; `list`/`status --all` skip `*.worktrees` files so they are never treated as worker names.

**Orphan cleanup** (worktrees that predate registration — no sidecar exists):
```
```bash
worker-cli worktree-rm <target-repo> <name> [branch]
# → removes <target-repo>/.claude/worktrees/<name> + deletes branch (best-effort)
# → no registry/sidecar involvement
```

`## Gotchas` (full section):
```
- `spawn.py` derives `PLUGIN_DIR` from `__file__` — call `python3 -m` from any cwd, `TMUX_SPAWN_SH` resolves correctly.
- `worker-cli spawn` converts relative paths to absolute before `cd "$PLUGIN"` to avoid path drift.
- Proxy injection: `spawn_claude_worker` reads `/tmp/.monitor_cc_proxy_<md5(project_path)>`. If marker absent → worker spawns without proxy (silent, no error).
```

## Salvage from src/pipeline/DOCS.md

`## Usage`:
```bash
python3 -m src.pipeline.jsonl_to_md --input <path> --output <path> [--dispatch]
python3 -m src.pipeline.list_agents --project <path> [--session latest]
python3 -m src.pipeline.extract_calls --input <path> --calls 1,3 [--output <path>]
```

`## Gotchas`:
```
- No active external callers — these modules were invoked via the eval-agent skill which has been removed. Re-wire via a new skill or command if eval workflows are reactivated.
```

## Salvage from dev/model_selector/DOCS.md

`verify_worker_model_precedence.sh`'s full original Purpose paragraph:
```
Verifies `tmux_spawn.sh`'s shared `_resolve_worker_model()` and the real
`${4:-$(_resolve_worker_model)}`/`[ -z "$model" ] && model="$(_resolve_worker_model)"` expansion
patterns used at its 3 call sites (`spawn_claude_worker`, `spawn_claude_worker_from_file`,
`worker_revive`'s fallback) — by sourcing the real file and calling the real function, not
reimplementing the resolution logic. Covers: config hit/missing/malformed/missing-key/empty-key
(5 cases against `_resolve_worker_model` directly); explicit-arg-wins, empty-arg-falls-to-config,
omitted-arg-falls-to-config (3 cases against the real spawn-site expansion pattern);
stored-value-wins, stored-absent-falls-to-config, stored-and-config-both-absent (3 cases against
the real revive fallback pattern); a structural grep confirming all 3 call sites plus the
definition reference `_resolve_worker_model`. **Real entry-point section (2026-08 fix
follow-up):** drives the actual `bin/worker-cli spawn` binary via subprocess — the only kind of
check that caught the 5th hardcode site (see Gotchas) after the isolated checks above all passed
while the assembled path was still dead code. 2 cases: no model arg (config's `worker` value must
reach both the generated runner script's `--model` and the tmux `WORKER_MODEL` env var) and an
explicit model arg (must still win). Overrides `WORKER_REGISTRY_DIR` (never touches the real
worker registry), `CLAUDE_BIN` (points at a tiny mock that prints `❯` and sleeps — never spawns a
real Claude process), `CLAUDE_PLUGIN_ROOT` (points `bin/worker-cli`'s own `$PLUGIN` resolution at
THIS worktree instead of the installed plugin cache — see Gotchas), and unsets
`PROXY_PROJECT_PATH` (so an ambient proxied session never redirects the scratch project path).
Runs under `set -uo pipefail` (deliberately NOT `-e` — assertion mismatches must not abort the
script; the sourced `tmux_spawn.sh` keeps its own `set -euo pipefail` for the functions it
defines).
```

`verify_spawn_model_resolution.py`'s full original Purpose paragraph:
```
Verifies `spawn.py`'s `_resolve_worker_model()` (config hit/missing/malformed/
missing-key, same 4 cases as the bash side) and, separately, that argparse's `model` positional
— default changed from the hardcoded `"claude-sonnet-5"` literal to `None` — never lets the
literal string `"None"` leak into the resolved model: an omitted CLI arg produces real `None`
(not the string), and `args.model or _resolve_worker_model()` always yields a concrete non-empty
string. Loads `spawn.py` via `importlib.util.spec_from_file_location` (it has zero relative
imports — stdlib only — so file-path loading works without package context).
```

`## Gotchas` (full section):
```
**Neither script touches the real `~/.claude/shared-rules/model_selection.json` or the real
`~/.claude/.worker-registry`.** Config cases use a temp path via `MODEL_SELECTION_FILE`; the real
entry-point section overrides `WORKER_REGISTRY_DIR` too.

**The 5th hardcode site, found by tracing (not by grep scoped to `src/`) — fixed.**
`bin/worker-cli`'s own `spawn)` case used to pre-resolve its 4th positional to a hardcoded literal
(`MODEL="${4:-claude-sonnet-5}"`) BEFORE ever calling `spawn.py`, so `spawn.py`'s `args.model` was
never actually `None` on that path, and `spawn.py` in turn always handed `tmux_spawn.sh` a
concrete value — `tmux_spawn.sh`'s own `_resolve_worker_model()` was never reached there either.
**Every individual piece verified correctly in isolation while the assembled real path
(`worker-cli spawn` with no model arg) was still dead code** — the isolated `_resolve_worker_model`
and expansion-pattern checks above could not have caught this; only a real subprocess call to
`bin/worker-cli spawn` could, and did. Fixed: `MODEL="${4:-}"` (empty string passes through,
`args.model or _resolve_worker_model()` correctly treats it as falsy). See
`process-docs/model_selector/` (monitor-cc repo) for the full trace and the whole-repo grep that
confirmed no 6th site.

**`CLAUDE_PLUGIN_ROOT` must be set for a real-entry-point test to exercise THIS worktree.**
`bin/worker-cli` resolves its own `$PLUGIN` variable from `CLAUDE_PLUGIN_ROOT`, falling back to
the INSTALLED plugin cache copy (`~/.claude/plugins/cache/.../iterative-dev/1.0.0/`) if unset —
confirmed live that the installed copy still carries the pre-fix code, so a real-entry-point test
run without this override silently verifies the wrong `spawn.py`/`tmux_spawn.sh`, passing or
failing for the wrong reason. `verify_worker_model_precedence.sh`'s real-entry-point section sets
`CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"` (this worktree) before invoking `bin/worker-cli`.
```

## Salvage from dev/git_automation/DOCS.md

`probe_umlaut_staging.py`'s full original Purpose paragraph:
```
Growing assertion suite proving `python3 -m src.git.commit` and `python3 -m src.git.check --auto-stage` stage/commit paths correctly, including non-ASCII and otherwise "unusual" paths that `git status --porcelain` (without `-z`) C-quotes. Builds throwaway git repos per case, drives the real module entry points against them, asserts via `git show --name-only -z` / `git diff --cached --name-only -z` on the repo itself (never trusts gcommit's own report). New fix-specific cases fold into this file rather than spawning a new one per fix.
```

Old `**Output:**` line:
```
`dev/git_automation/md/probe_umlaut_staging_<timestamp>.md` — pass/fail table + per-case detail (rc, committed files, raw output). Exit code non-zero if any case fails.
```

Old `**Cases covered:**` line:
```
umlaut file in an existing tracked folder (the reported bug); brand-new umlaut folder (single directory status entry — exercises `verify_staged`'s prefix match, not an exact-path match); path with a space; staged rename via `git mv`; plain ASCII modification (regression); unreadable file forcing `git add` to fail (loud-failure path, asserts non-zero exit + no commit); `git-check --auto-stage` against the same kind of fixture.
```

## Salvage from dev/poread_cli/DOCS.md

Original Role paragraph (trimmed to fit the 50-word Role limit; full original text):
```
Regression suite for `src/poread_cli/__main__.py` — the poread CLI's own boundary behavior.
Proves the CLI's own boundary behavior (valid file, oversize file, missing file, directory, bad
argv) in isolation, calling `main()` directly rather than through a subprocess. Touch this
directory when changing `src/poread_cli/__main__.py`'s argument handling, size-ceiling check, or
marker format. The end-to-end proof that a marker this CLI mints is correctly recognized and
expanded lives in monitor-cc's `dev/proxy/poread_inject_tests.py` instead (a different repo — see
Gotchas in `src/poread_cli/DOCS.md`); that suite mints its own fixture markers from its own pinned
literal copy of the same contract, it does not invoke this CLI.
```

Original module Purpose paragraph (trimmed to fit the 25-word Purpose limit; full original text):
```
Unit-level regression guard for `main()`'s five boundary cases — valid file, oversize
file (refused before ever being opened), missing file, directory path, malformed argv — asserted
against a pinned literal copy of the marker contract (`_PINNED_MAX_BYTES`, `_PINNED_HASH_LEN`,
`_PINNED_MARKER_PREFIX`, `_PINNED_NOTICE`, hardcoded in this file, not imported from
`src.poread_cli.__main__`), so a drift in that module's own hand-maintained constants fails this
test loudly rather than the test silently checking itself.
```

## Salvage from dev/desktop_targeting/DOCS.md

Old `probe.py` module fields, superseded by the new Public Interface section and an accurate
Writes line (the code itself only ever prints to stdout — no `write_text` call exists anywhere
in `probe.py`, so the old `**Output:**` line was documenting a manually-saved past run, not
current behavior):
```
**Usage:** `python3 dev/desktop_targeting/probe.py`
**Output:** `dev/desktop_targeting/md/space_move_probe_2026-05-29.md`
```

## Verification — behavior unchanged

Same method as milestone 1: run every touched entry point before/after, diff stdout, and for the
pure-function modules compare against a real fixture (a 1134-line real session JSONL, and a
throwaway-git-repo probe) rather than an invented one.

- `python3 dev/worker_spawn/test_capture_clean.py` — `All assertions passed.` both before and
  after comment removal; additionally diffed the fixture's raw stdout between the old and new
  `_capture_clean.py` byte-for-byte — identical.
- `python3 dev/model_selector/verify_spawn_model_resolution.py` — `RESULT: PASS`, output
  byte-identical to the pre-purge run (compared old vs. new via a patched copy of the pre-purge
  script, both invocations landing in the same wall-clock second so even the timestamp line
  matched).
- `python3 dev/git_automation/probe_umlaut_staging.py` — all 7 cases PASS against real throwaway
  git repos (exercises `src/git/check.py` and `src/git/commit.py` end-to-end, not just imports).
- `python3 -m src.git.check <worktree>`, `python3 -m src.git.staged <worktree>`,
  `python3 -m src.git.post <worktree>` — all run clean, no exceptions.
- `src.pipeline.jsonl_to_md.convert_workflow` against the same real 1134-line JSONL used in
  milestone 1's verification: `tool_calls: 210`, matching the milestone-1 baseline count.
- `dev/desktop_targeting/probe.py --help` — byte-identical output to the pre-purge run (this
  exercises every `ctypes.CDLL` load across all 5 files in the package, plus the `_HELP_TEXT`
  deviation described above). `spaces.choose_target_space(cid, None)` re-run read-only against
  this machine's live Space state — same `(5, 3)` result, same stdout, as the milestone-1 and
  pre-purge runs.
- Zero-docstring/zero-stray-comment scan (AST-based `ast.get_docstring` + line-based `#`-scan
  excluding the three markers and shebangs) across all 21 files: 0 docstrings, 0 stray comments.
- LOC-heading-vs-`wc -l` cross-check script across all 9 rewritten DOCS.md files: 0 mismatches.
- Purpose-word-count check (`**Purpose:**` field split on whitespace) across all 9 DOCS.md files:
  0 fields over 25 words.

## What I'd tell the next agent

- The per-block triage rule I used (delete a whole comment/docstring block if ANY of its
  substance is covered, relocate the WHOLE block verbatim if ANY of it isn't) is simpler and
  safer than trying to split a block mid-sentence. It means a couple of relocated blocks carry
  one sentence's worth of genuinely new information wrapped in two sentences of already-covered
  context (e.g. `spawn.py`'s `_resolve_worker_model` comment) — that's the trade I made
  deliberately, re-typing 3 extra lines costs nothing, losing a detail costs a future agent real
  time.
- I did NOT treat "the new DOCS.md will restate this anyway" as grounds for skipping the Salvage
  step for existing DOCS.md `## Usage`/`## Gotchas` sections — those went to Salvage unconditionally,
  verbatim, even where my rewritten Public Interface section says nearly the same thing. That's
  the mechanical Salvage rule, separate from the comment-triage judgment call above.
- `dev/desktop_targeting/probe.py`'s `_HELP_TEXT` constant is the one place code still carries a
  large text block that looks like a docstring but isn't one by Python's own rules. If a later
  pass wants argparse's `--help` text gone from the `.py` file entirely, that's a real behavior
  change (`--help` output shrinks) and needs explicit sign-off, not a silent deletion.
- `src/git/check.py` and `src/git/staged.py` have a byte-identical `_extract_stage_path` helper
  (and, pre-existing, duplicate `SKIP_PATTERNS`/`run()`/`parse_status()`/`classify_files()` —
  documented already in `process-docs/git_automation/gcommit_worktree_correct_commit_cli.md` and
  in `src/git/DOCS.md`'s new State section). Not touched here — deduplicating is a code change,
  out of scope for a comment-only milestone.
- I did not re-read every `.sh` file's own comments (`tmux_spawn.sh`, the three `.sh` files under
  `dev/worker_spawn/`, `verify_worker_model_precedence.sh`) — Main's hit list was `.py`-only, and
  the milestone's own hit list is what defines scope. I only touched their DOCS.md entries
  (format compliance, LOC currency), never their source.

## Recap — 2026-09-16

Self-check (`git diff integration --name-only`) confirms the diff is exactly the 33 files touched
during this milestone (32 edited + this process-docs file), plus one generated report
(`dev/git_automation/md/probe_umlaut_staging_20260916_002718.md`, a byproduct of running the
verification probe, consistent with the existing convention of committing timestamped probe
reports — `dev/git_automation/md/probe_umlaut_staging_20260902_184629.md` was already tracked
before this session).

**DOCS.md currency, re-checked this pass:** ran the LOC-heading-vs-`wc -l` cross-check script
again after the conformance commit landed — 0 mismatches across all 9 rewritten DOCS.md files.
Re-ran the `**Purpose:**`-word-count check — 0 fields over 25 words. Re-ran the zero-docstring/
zero-stray-comment AST scan across all 21 hit-list files — 0/0. All three checks match what's
reported under Verification above; nothing drifted between the conformance commit and this recap.

**Nothing else in this milestone's scope was left stale.** `src/DOCS.md`'s Directory Map LOC
column for `spawn/`/`git/`/`pipeline/` was corrected to the post-purge totals (1124/446/670) —
this file's own directory (`src/`) wasn't "touched" by the hit list, so it did not get a full
format rewrite, only the numeric correction the milestone's "zero code lines change, but comments
did" consequence requires. `dev/DOCS.md` carries no LOC figures, so it needed no change.

No process-docs entries outside this file were touched or need touching — the only other
DOCS.md-adjacent claim I found while triaging (the "menubar Models tab" detail cut from
`spawn.py`, and the two module-fields cut from `dev/desktop_targeting/DOCS.md`'s `probe.py`
entry) are recorded above under Relocated/Salvage, not left dangling anywhere else.
