# dev/

## Role

Development scripts for tests, probes and experiments, one directory per area. Touch when adding or changing a test suite or probe. Do not touch for production code in src or bin.

## Public Interface

No `__init__.py`; every script is run directly. Areas with their own DOCS.md: [cc_hooks](cc_hooks/DOCS.md), [desktop_targeting](desktop_targeting/DOCS.md), [docs_drift_check](docs_drift_check/DOCS.md), [git_automation](git_automation/DOCS.md), [model_selector](model_selector/DOCS.md), [poread_cli](poread_cli/DOCS.md), [session_pipeline](session_pipeline/DOCS.md), [worker_janitor](worker_janitor/DOCS.md), [worker_merge](worker_merge/DOCS.md), [worker_message_delivery](worker_message_delivery/DOCS.md), [worker_spawn](worker_spawn/DOCS.md), [worker_status](worker_status/DOCS.md), [worker_sweep_logs](worker_sweep_logs/DOCS.md), [worker_wait](worker_wait/DOCS.md).

## Flow

A suite lists its independent cases as strands and hands them to the shared runner. Each strand runs in parallel with private state and stops at its first failure. The runner prints every strand block, then a summary. Probes and reports live in the area directories.

## Modules

### strand_runner.sh (105 LOC)

**Purpose:** Shared runner for shell suites: runs each case as a parallel, isolated, fail-fast strand and aggregates the results.
**Reads:** The suite's strand list and strand functions.
**Writes:** stdout; a private scratch directory per strand, removed on exit.
**Called by:** Every shell suite in the area directories, sourced.
**Calls out:** tmux, mktemp.

---

### strand_runner.py (43 LOC)

**Purpose:** Shared runner for Python suites: runs each case in its own process, prints per-case output and returns the exit code with all outputs.
**Reads:** Case callables handed over by the suite.
**Writes:** stdout only.
**Called by:** The Python suites of poread_cli, worker_spawn, model_selector.
**Calls out:** Python standard library only.

## State

Owned by the runners per run: one temporary root with one scratch directory per strand. Nothing persists after a run.
