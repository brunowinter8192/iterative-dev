# dev/docs_drift_check/

## Role

Regression suite for `docs-drift-check`. Runs the real wrapper against fixture projects built in isolated temp directories. Touch when changing the checks or the DOCS.md rules they encode.

## Public Interface

Run manually, no importable interface: `python3 dev/docs_drift_check/test_docs_drift_check.py` (from project root). Exit 0 = all cases passed.

## Flow

Fixture definitions → one temp project per case, all cases in parallel → wrapper invoked with the fixture as cwd → exit code and output assertions per case → pass/fail summary.

## Modules

### test_docs_drift_check.py (224 LOC)

**Purpose:** Fixture-based regression cases for path, LOC and rule checks, scope exclusions and cwd independence.
**Reads:** nothing external; builds its own temp projects.
**Writes:** stdout (pass/fail per case); no writes outside its temp fixtures.
**Called by:** none, manual regression guard.
**Calls out:** `bin/docs-drift-check` (subprocess).
