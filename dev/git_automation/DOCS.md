# dev/git_automation/

## Role

Regression probe for staging correctness of git-check. All commands assume the project root as working directory. Touch when changing the staging logic in src/git.

## Public Interface

No `__init__.py`; run manually: `python3 dev/git_automation/probe_git_check_staging.py`.

## Flow

No input: builds a throwaway git repository per case, drives the check module against it, asserts on the repository's own git state, prints a pass/fail table to stdout and a report to md/.

## Modules

### probe_git_check_staging.py (114 LOC)

**Purpose:** Assertion suite proving git-check --auto-stage stages non-ASCII and otherwise unusual paths correctly.
**Reads:** Nothing external; builds throwaway git repos per case.
**Writes:** stdout; a timestamped report under md/; throwaway repos removed after each case.
**Called by:** Run manually.
**Calls out:** `src/git` check module (subprocess), git.

## State

None.
