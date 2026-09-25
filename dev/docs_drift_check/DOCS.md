# dev/docs_drift_check/

## Role

Regression suite for the docs-drift-check command, one fixture case per rule check. Runs the real wrapper against fixture projects built in temporary directories. Touch when changing the checks or the DOCS.md rules they encode.

## Public Interface

No `__init__.py`; run manually from the project root: `python3 dev/docs_drift_check/test_docs_drift_check.py`. Exit 0 means all cases passed.

## Flow

Fixture definitions become one temporary git repository per case (one case deliberately without git). All cases run in parallel, including the missing-root case. The wrapper runs with the fixture as working directory. Exit code and output are asserted per case.

## Modules

### test_docs_drift_check.py (335 LOC)

**Purpose:** Fixture-based regression cases, at least one per rule check, plus scope exclusions, the argument rejection and working-directory independence.
**Reads:** Nothing external; builds its own temporary projects.
**Writes:** stdout (pass/fail per case).
**Called by:** Run manually as a regression guard.
**Calls out:** `bin/docs-drift-check` (subprocess).

## State

Nothing shared: every run builds and removes its own fixtures.
