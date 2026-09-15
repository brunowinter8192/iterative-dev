# dev/poread_cli/

## Role

Regression suite for `src/poread_cli/__main__.py`'s boundary behavior (valid file, oversize file, missing file, directory, bad argv), calling `main()` directly. Touch when changing argument handling, size-ceiling check, or marker format. The cross-repo recognition proof lives in monitor-cc's `dev/proxy/poread_inject_tests.py` instead.

## Public Interface

Run manually, no importable interface: `python3 dev/poread_cli/test_poread_cli.py` (from project root).

## Flow

No CLI input — drives `main()` directly against temp fixtures for each boundary case → pass/fail summary out (stdout).

## Modules

### test_poread_cli.py (132 LOC)

**Purpose:** Unit-level regression guard for `main()`'s five boundary cases, asserted against a pinned literal copy of the marker contract (not imported from the module under test).
**Reads:** nothing external — builds its own temp files/directories per test, cleans them up.
**Writes:** stdout (pass/fail via `check()`); no filesystem writes outside its own temp fixtures.
**Called by:** none — manual regression guard, re-run after any change to `src/poread_cli/__main__.py`.
**Calls out:** `src.poread_cli.__main__` (`main`).
