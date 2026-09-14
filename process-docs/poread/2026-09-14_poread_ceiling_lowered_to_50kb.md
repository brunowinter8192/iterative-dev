# 2026-09-14 — poread ceiling lowered from 500,000 to 50,000 bytes (iterative-dev half)

Worker task, worktree `.claude/worktrees/poreadcap/`, milestone 1 of a larger plan. Cross-repo
change, this entry covers only this repo's half; see `process-docs/poread/` in monitor-cc for the
proxy-side half of the same milestone. Same area as the prior entry
(`2026-09-14_poread_cli_lands_from_monitor_cc.md`) — this only lowers a value already established
there, the mechanism itself is unchanged (no paging/partial-read mode, no marker-format or notice
or hash-length or refusal-structure change).

## What changed

`src/poread_cli/__main__.py:6` — `POREAD_MAX_BYTES` `500_000` → `50_000`, this repo's
hand-maintained half of the two-repo marker contract (see the Gotcha in `src/poread_cli/DOCS.md`
for why it's a hand-maintained copy and not a shared import).

`dev/poread_cli/test_poread_cli.py:20` — `_PINNED_MAX_BYTES` `500_000` → `50_000`, the test's own
independent pinned literal copy of the same value (deliberately NOT imported from `__main__.py`,
same reasoning as the constant split itself — see that same DOCS.md Gotcha). This is the only test
in this repo that pins the ceiling; `test_oversize_file_refused_without_reading` builds its fixture
file by seeking to `_PINNED_MAX_BYTES` and writing one byte past it, and asserts the stderr message
contains `str(_PINNED_MAX_BYTES)` — both fully dynamic off the one constant, no other line in the
test needed touching.

Confirmed the two repos' `POREAD_MAX_BYTES`/`POREAD_HASH_LEN`/`POREAD_MARKER_PREFIX`/`POREAD_NOTICE`
lines are byte-identical after the edit by diffing them directly against monitor-cc's
`src/proxy/inject_poread.py` (not just asserting it — actually diffed).

## What was checked in this repo and found to need no change

Grepped this repo for `500,000|500_000|500000` and separately `ceiling` — the only other hits were
DOCS.md prose using the word "ceiling" generically with no number attached
(`src/poread_cli/DOCS.md`, `dev/poread_cli/DOCS.md`), and `test_poread_cli.py`'s own "over the
ceiling" check string, which asserts dynamically via `str(_PINNED_MAX_BYTES) in err` — not a
literal number, updates automatically with the constant. Nothing else in this repo referenced the
old value.

## Evidence

- `dev/poread_cli/test_poread_cli.py`: 17/17 before, 17/17 after.
- monitor-cc's `dev/proxy/poread_inject_tests.py`: 37/37 before, 37/37 after (see that repo's own
  entry).
- LOC unchanged on both touched files: 77 (`__main__.py`), 134 (`test_poread_cli.py`) — both
  already matched their existing `src/poread_cli/DOCS.md`/`dev/poread_cli/DOCS.md` headings, and
  `src/DOCS.md`'s Directory Map row (`poread_cli/ | ... | 77 | 1 (__main__.py)`) also still
  matches — checked, nothing to fix.

## Landmine for whoever touches the poread ceiling next

Re-run the same two greps (`500,000|500_000|500000`, `ceiling`) across THIS repo too before
trusting a fixed file list, same as noted in monitor-cc's own entry for this milestone — a value
this widely hand-copied can grow a new stale reference anywhere prose mentions it, and no test
catches prose drift.

## No further work planned by this worker here

Milestone 1 only, as scoped. `bin/poread`, the plugin-cache resolution logic, and everything else
in `src/poread_cli/__main__.py` beyond the one constant were untouched.
