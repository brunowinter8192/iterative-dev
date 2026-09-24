# dev/poread_cli/

## Role

Regression suite for the poread command's boundary behavior: valid file, oversize file, missing file, directory, bad arguments. Touch when changing argument handling, the size ceiling or the marker format.

## Public Interface

No `__init__.py`; run manually from the project root: `python3 dev/poread_cli/test_poread_cli.py`.

## Flow

No input: each boundary case runs in its own process against temporary fixtures, asserts against a pinned copy of the marker contract, and reports pass/fail per case.

## Modules

### test_poread_cli.py (122 LOC)

**Purpose:** Regression guard for the five boundary cases, asserted against a pinned literal copy of the marker contract rather than the module under test.
**Reads:** Nothing external; builds its own temporary files and directories.
**Writes:** stdout; no writes outside its temporary fixtures.
**Called by:** Run manually after changes to `src/poread_cli`.
**Calls out:** `src/poread_cli/__main__.py`, `dev/strand_runner.py`.

## State

Nothing shared: every run builds and removes its own fixtures.
