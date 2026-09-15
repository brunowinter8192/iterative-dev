# dev/git_automation/

## Role

Regression probes for `src/git/` (`gcommit`, `git-check`) staging correctness. All commands assume CWD = project root (iterative-dev/).

## Public Interface

Run manually, no importable interface: `python3 dev/git_automation/probe_umlaut_staging.py`.

## Flow

No CLI input — builds throwaway git repos per case, drives `python3 -m src.git.commit` / `python3 -m src.git.check --auto-stage` against them, asserts against the repo's own git state → pass/fail table out (stdout + `md/probe_umlaut_staging_<timestamp>.md`).

## Modules

### probe_umlaut_staging.py (233 LOC)

**Purpose:** Growing assertion suite proving `gcommit`/`git-check --auto-stage` stage/commit non-ASCII and otherwise "unusual" paths correctly.
**Reads:** nothing external — builds its own throwaway git repos per case.
**Writes:** stdout; `dev/git_automation/md/probe_umlaut_staging_<timestamp>.md`; throwaway git repos (cleaned up after each case).
**Called by:** run manually.
**Calls out:** `src.git.commit`, `src.git.check` (via subprocess), git.
