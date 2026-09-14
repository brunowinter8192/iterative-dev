# 2026-09-14 — the poread CLI lands here, moving out of monitor-cc

Worker task on branch `identity`, worktree `.claude/worktrees/poreadmove/`. New area in this repo
— no prior process-docs entry here to build on. Cross-repo milestone, first commit landed in
monitor-cc (own worktree, own process-docs entry there, area `poread`). This entry covers only
this repo's half of the move.

## What landed and why here specifically

`src/poread_cli/` (CLI package), `bin/poread`, `dev/poread_cli/` (its test) — the marker-minting
half of a two-repo mechanism. The other half, monitor-cc's `src/proxy/inject_poread.py` (recognizes
the marker inside a `tool_result` and replaces it with the file's full content, running as part of
a mitmproxy addon in front of Claude Code's own API traffic), stayed in monitor-cc — it has proxy
callers there and no reason to move. This CLI moved here because it belongs with the other
agent-facing CLIs (`worker-cli`, `gcommit`) rather than sitting inside a monitoring application, and
because it is genuinely stdlib-only (`hashlib`, `os`, `sys`) — the one property that makes this move
possible at all, since this plugin has no venv and runs system `python3` directly.

## Adaptation from monitor-cc's conventions to this repo's

`__main__.py` itself needed almost no change — it already used only stdlib. The only functional
change: the four marker constants (`POREAD_MAX_BYTES`, `POREAD_HASH_LEN`, `POREAD_MARKER_PREFIX`,
`POREAD_NOTICE`) used to come from monitor-cc's `src/constants.py` via a relative import
(`from ..constants import ...`); that import is gone once this package left monitor-cc's package
hierarchy, so `__main__.py` now defines its own copy directly in its own INFRASTRUCTURE section —
see Gotchas in `src/poread_cli/DOCS.md` for why this is a deliberate hand-maintained copy, not a
config-file workaround, matching monitor-cc's own `strip_vocab.py` precedent for the same kind of
cross-boundary contract.

`bin/poread` is new, built to match this repo's own `bin/gcommit`/`bin/worker-cli` shape exactly,
not monitor-cc's `bin/poread` (which did `cd /Users/.../monitor-cc && ./venv/bin/python -m
src.poread_cli`, an absolute hardcoded path plus a venv this repo doesn't have): resolves
`PLUGIN="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/cache/brunowinter-plugins/iterative-dev/1.0.0}"`,
then `cd "$PLUGIN" && python3 -m src.poread_cli "$@"` — system `python3`, plugin-cache resolution,
no venv, no absolute checkout path. Smoke-tested directly against this worktree
(`CLAUDE_PLUGIN_ROOT="$(pwd)" bash bin/poread /tmp/poread_smoke_test.txt`), confirmed the exact
same marker/notice shape monitor-cc's version produced.

## Tests — what this side pins

`dev/poread_cli/test_poread_cli.py` moved with one change beyond the import path: it now asserts
against its OWN pinned literal copy of the marker contract (`_PINNED_MAX_BYTES`,
`_PINNED_HASH_LEN`, `_PINNED_MARKER_PREFIX`, `_PINNED_NOTICE`, hardcoded in the test file) rather
than importing the four constants from `src.poread_cli.__main__` (which would just test the module
against itself — tautological, catches nothing). This mirrors monitor-cc's own
`dev/proxy/poread_inject_tests.py`, which does the identical thing for its side. Neither test can
detect a cross-repo drift — there is no shared CI between this repo and monitor-cc, and a
`$PATH`-resolved cross-repo check would be an environment dependency, which by this project's own
testing rule makes it a verification, not a test; both Gotchas say this plainly rather than
implying a safety net that doesn't exist. What each pinned test DOES guarantee: if either module's
own hand-maintained copy of the contract ever drifts from what its own test file independently
expects, that repo's test suite fails immediately and loudly, forcing a deliberate look before the
change ships — rather than a marker silently minted in one shape and expected in another, expanding
never, with no error anywhere.

Also removed the module docstring `test_poread_cli.py` carried in monitor-cc (its dev/ tests used
one; this repo's dev/ python tests — `dev/model_selector/*.py`, `dev/worker_spawn/
test_capture_clean.py` — don't) to match this repo's existing convention; the coverage description
that used to live there now lives in `dev/poread_cli/DOCS.md`'s Purpose line instead.

## Numbers

`dev/poread_cli/test_poread_cli.py`: 17/17 on first run in this repo (identical five boundary
cases as monitor-cc's version; only the constants' import source and the pin mechanism changed,
zero behavior change).

## Callers checked

Repo-wide grep for `poread` before this task: zero hits anywhere in this repo — a clean add, no
pre-existing partial wiring to reconcile. `src/DOCS.md`'s Documentation Tree and Directory Map, and
`dev/DOCS.md`'s Areas list, both updated to list the new package/area alongside `spawn/`, `git/`,
`pipeline/` and the existing `dev/` areas — matching their existing table/list shape exactly, no
new columns or sections invented.

## No further work planned by this worker here

The move is complete as scoped on this side: CLI package landed, `bin/poread` adapted to this
repo's own resolution convention, test suite moved and re-pinned, DOCS.md updated at both the
package level and the directory-map level. See `process-docs/poread/` in the monitor-cc repo for
the other half of this same milestone (the proxy-side constant-copy adaptation and its own test
rewrite).

## Recap close-out

Self-audit: `git diff integration --name-only` on this worktree returns files from other,
unrelated prior work already sitting on branch `identity` (`bin/worker-cli`,
`dev/worker_merge/*`, `process-docs/worker_merge/*`, `skills/*`) — not mine, out of this recap's
scope. The actual scope is this task's own commit (`git show --stat 7e91fb6 --name-only`):
`bin/poread`, `dev/DOCS.md`, `dev/poread_cli/DOCS.md`, `dev/poread_cli/test_poread_cli.py`,
`process-docs/poread/2026-09-14_poread_cli_lands_from_monitor_cc.md`, `src/DOCS.md`,
`src/poread_cli/DOCS.md`, `src/poread_cli/__init__.py`, `src/poread_cli/__main__.py` — matches the
file list already named in the task's completion checklist.

**DOCS.md currency check, this pass:** `src/poread_cli/DOCS.md`'s `__main__.py` entry says
`(77 LOC)`, `wc -l` confirms 77 — matches. `dev/poread_cli/DOCS.md`'s `test_poread_cli.py` entry
says `(134 LOC)`, `wc -l` confirms 134 — matches. `src/DOCS.md`'s Directory Map row for
`poread_cli/` says `77 | 1 (__main__.py)` — matches. Nothing stale found on this side; the one
LOC drift found this session was on the monitor-cc side (`inject_poread.py`, 79→81 LOC in its own
DOCS.md) — see that repo's own recap entry, not fixed here per this project's own rule (a found
error in another file is stated in the author's own file, never fixed there).

No further work planned by this worker here.
