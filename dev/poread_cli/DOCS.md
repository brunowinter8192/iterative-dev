# dev/poread_cli/

## Role

Regression suite for `src/poread_cli/__main__.py` — the poread CLI's own boundary behavior.
Proves the CLI's own boundary behavior (valid file, oversize file, missing file, directory, bad
argv) in isolation, calling `main()` directly rather than through a subprocess. Touch this
directory when changing `src/poread_cli/__main__.py`'s argument handling, size-ceiling check, or
marker format. The end-to-end proof that a marker this CLI mints is correctly recognized and
expanded lives in monitor-cc's `dev/proxy/poread_inject_tests.py` instead (a different repo — see
Gotchas in `src/poread_cli/DOCS.md`); that suite mints its own fixture markers from its own pinned
literal copy of the same contract, it does not invoke this CLI.

## Modules

### test_poread_cli.py (134 LOC)

**Purpose:** Unit-level regression guard for `main()`'s five boundary cases — valid file, oversize
file (refused before ever being opened), missing file, directory path, malformed argv — asserted
against a pinned literal copy of the marker contract (`_PINNED_MAX_BYTES`, `_PINNED_HASH_LEN`,
`_PINNED_MARKER_PREFIX`, `_PINNED_NOTICE`, hardcoded in this file, not imported from
`src.poread_cli.__main__`), so a drift in that module's own hand-maintained constants fails this
test loudly rather than the test silently checking itself.
**Reads:** nothing external — builds its own temp files/directories per test, cleans them up.
**Writes:** stdout (pass/fail via `check()`); no filesystem writes outside its own temp fixtures.
**Called by:** none — manual regression guard, re-run after any change to
`src/poread_cli/__main__.py`.
**Calls out:** `src.poread_cli.__main__` (`main`).
