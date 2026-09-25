# dev/git_automation/

## Role

Regression probes for staging correctness of gcommit and git-check. All commands assume the project root as working directory. Touch when changing the staging logic in src/git.

## Public Interface

No `__init__.py`; run manually: `python3 dev/git_automation/probe_umlaut_staging.py`.

## Flow

No input: builds throwaway git repositories per case, drives the commit and check modules against them, asserts on the repository's own git state, prints a pass/fail table to stdout and a report to md/.

## Modules

### probe_umlaut_staging.py (233 LOC)

**Purpose:** Growing assertion suite proving gcommit and git-check stage and commit non-ASCII and otherwise unusual paths correctly.
**Reads:** Nothing external; builds throwaway git repos per case.
**Writes:** stdout; a timestamped report under md/; throwaway repos removed after each case.
**Called by:** Run manually.
**Calls out:** `src/git` commit and check modules (subprocess), git.

## State

None.
