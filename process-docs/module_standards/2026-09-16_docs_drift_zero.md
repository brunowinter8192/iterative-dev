# 2026-09-16 — docs-drift-check: 21 findings to zero

Worker task on branch `sweepitdev`, same worktree as the two prior milestones. Main ran
`docs-drift-check` (`~/.local/bin/docs-drift-check`) in the project root after the milestone-2
merge: 21 findings, 6 path + 15 symbol, no `.drift-whitelist.txt` present so nothing was
pre-filtered. Target: zero. Reached zero; verified by re-running the tool, not by inspection.

## The 6 path findings were not dead references — they were a checker-format gap

Main's prior was that these six were real drift (code moved or died). I checked the actual
filesystem at `/Users/brunowinter2000/Documents/ai/monitor-cc/` before touching any doc:

- `src/proxy/inject_poread.py` — exists there now, unchanged in role from what the doc already
  said (the mitmproxy addon that expands a poread marker back into full file content).
- `src/constants.py` — exists there now (49 LOC, other constants), but no longer carries the
  four `POREAD_*` values — `inject_poread.py` hardcoded its own copy of them at some point,
  same pattern this repo's `__main__.py` already uses. The doc's claim about `src/constants.py`
  is phrased in the past tense ("Before this package existed here... imported these four values
  from one `src/constants.py`") — that's accurate history, not a current-state claim, so nothing
  needed correcting there beyond the path-checker format.
- `dev/proxy/poread_inject_tests.py` — exists there now, the monitor-cc-side regression suite
  for the same contract `dev/poread_cli/test_poread_cli.py` pins on this side.

None of the three files moved or died. The doc prose already correctly said "a different repo" /
"monitor-cc's" next to every one of these — just in plain prose *outside* the backticks, where
`docs-drift-check`'s path checker never looks. The checker has a real, designed exemption for
exactly this case (its own module docstring says "Cross-project markers `path (ProjectName)` are
skipped in path check"), implemented as: if the backtick content itself ends in `\s(Word)` with
`Word` starting uppercase, the whole backtick's paths are skipped. Fix applied: moved the marker
*inside* the backticks — `` `src/proxy/inject_poread.py (Monitor_CC)` `` etc. — across
`src/poread_cli/DOCS.md` (3 spots) and `dev/poread_cli/DOCS.md` (1 spot). `Monitor_CC` (not
`monitor-cc`) because the regex is `[A-Z][A-Za-z_]+` — no hyphens allowed — and this project
already uses `Monitor_CC` as a proper-noun spelling elsewhere (`src/spawn/DOCS.md`'s proxy-marker
prose), so it's not a new convention, just an existing one applied inside backticks for the first
time in this project's DOCS.md corpus.

**Convention for the next agent:** any future cross-repo path reference in this project's
DOCS.md must carry its `(Monitor_CC)` (or whatever project name) marker *inside* the same
backtick span as the path, immediately after it, no space-separated prose parenthetical outside
the backticks — that's what the checker actually reads.

## The 6th path finding was a genuinely different shape — a runtime-built path, not a project file

`src/git/DOCS.md`'s `check.py` entry referenced `` `.git/hooks/pre-commit` `` as something it
reads. That literal path does not exist anywhere in this repo (checked both the worktree, where
`.git` is a worktree-pointer file, and the main checkout, where `.git/hooks/` only has the
stock `*.sample` files — no live `pre-commit`). But the code claim is true: `check_hook()` in
`check.py` really does build and read `<repo_path>/.git/hooks/pre-commit`, for whatever
`repo_path` the tool is pointed at (any target repo, not necessarily this one) — it's a
per-invocation runtime path, not a static artifact of this project, and the code already handles
its absence gracefully (`return "NONE"`). Fix: de-backticked it and reworded as prose
("the target repo's pre-commit hook file (.git/hooks/pre-commit) if present") — the path
checker only ever looks inside backticks, so plain prose describing a dynamic path template is
never a path-existence claim in the first place. This is the correct home for this kind of
reference going forward: a path that is a *shape*, not a *file*, doesn't belong in backticks.

## The 15 symbol findings were exactly what Main predicted

`docs-drift-check` only greps `src/**/*.py` and `dev/**/*.py` (see its own `SOURCE_GLOBS`) for
symbol existence — it never reads `.sh` files at all, and this project's worker-lifecycle logic
(`bin/worker-cli`, `src/spawn/tmux_spawn.sh`) is almost entirely bash. Checked every one of the
15 against real source before whitelisting, not assumed:

- `WORKER_REGISTRY_DIR`, `WORKER_LOGGER_DIR`, `CLAUDE_PLUGIN_ROOT`, `SAW_WORKING`, `NAMES`,
  `CHATTY` — real bash env vars / variables, found by exact grep in `bin/worker-cli` and/or
  `src/spawn/tmux_spawn.sh`.
- `go_quiet`, `kill_claude_child`, `delete_hook_entry`, `worker_capture_clean` — real bash
  functions, found by exact grep (`worker_capture_clean` in `tmux_spawn.sh:311`, the other three
  in `dev/worker_wait/test_worker_wait.sh`).
- `TMUX_TMPDIR` — a real tmux/OS environment variable, external to this project by design (never
  going to be in this project's own source).
- `EXIT` — bash's own pseudo-signal name in `trap ... EXIT`, not a project symbol.
- `CONFLICT` — git's own merge-conflict output text ("`CONFLICT (content): ...`"), not a project
  symbol.
- `XXXXXXXX` — literal placeholder text quoting macOS `mktemp`'s `tmp.XXXXXXXX` naming pattern,
  not a symbol reference at all.
- `THIS` — confirmed by hand-tracing the checker's own backtick regex against
  `dev/worker_wait/DOCS.md:16`: it's an ordinary English word ("if THIS invocation observed...")
  that only got swept into a "symbol" because the line has several short adjacent
  backtick-quoted terms and the regex pairs backticks positionally per line, not semantically —
  the text between two unrelated backtick spans reads as if it were itself backtick content.
  Genuinely nothing to fix in the doc; this is a parser artifact, not miswritten markdown.

All 15 added to a new `.drift-whitelist.txt` at the project root (this project had none before
this session) — `resolve_whitelist()` checks `scripts/docs_drift_whitelist.txt` first, then
`.drift-whitelist.txt`, one bare symbol per line, `#`-prefixed lines are comments. Grouped by
reason with a comment header, unlike reddit-cli's bare 4-line file — this project's set spans
four distinct root causes (bash vars, bash functions, genuinely-external tokens, prose
artifacts), worth keeping legible for whoever adds the next entry.

## Verification

`python3 ~/.local/bin/docs-drift-check` from the project root, before vs. after:

```
Before: Path-Drift 6, LOC-Drift 0, Symbol-Drift 15, Total 21 (exit 1)
After:  Path-Drift 0, LOC-Drift 0, Symbol-Drift 0,  Total 0  (exit 0)
```

## What I'd tell the next agent

- Don't assume a `docs-drift-check` path finding means the doc is wrong. Check the actual
  filesystem (including sibling repos this project explicitly documents cross-repo dependencies
  on) before editing anything — two different fix shapes came out of the same 6 findings here
  (cross-repo marker reformat vs. de-backticking a runtime path template), and neither was
  "delete the claim."
- The whitelist mechanism is symbol-only. There is no way to whitelist a path finding — the only
  two levers are making the path exist, or changing what the doc says/how it's formatted so the
  checker doesn't treat it as a path-existence claim.
- This project's real logic is more bash than the checker's `SOURCE_GLOBS` (`src/**/*.py`,
  `dev/**/*.py`) accounts for. Every future DOCS.md that documents a `.sh` file's variables or
  functions will keep tripping fresh symbol findings — that's expected, not a regression signal,
  and the fix is always "verify against the real `.sh` file, then whitelist," never "reword the
  doc to hide the symbol."
