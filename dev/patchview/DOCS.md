# dev/patchview/

## Role

Regression suite for the patchview renderer: a patch that applies, shifted hunks, a stale patch, bad arguments, a missing live file, the wrapper run from a cwd that has its own `src` package. Touch when changing patch parsing, apply semantics or page output.

## Public Interface

No `__init__.py`; run manually from the project root: `python3 dev/patchview/test_patchview.py`.

## Flow

No input: each case runs in its own process with its own temporary directory and its own `TMPDIR`, builds the patch with the real `diff -u`, runs the renderer in-process and asserts against pinned literal row lists. No browser is ever opened.

## Modules

### test_patchview.py (208 LOC)

**Purpose:** Regression guard for the six cases, asserted against hand-written expected red/green row lists.
**Reads:** Nothing external; builds its own temporary files.
**Writes:** stdout; no writes outside its temporary fixtures.
**Called by:** Run manually after changes to `src/patchview`.
**Calls out:** `src/patchview/__main__.py`, `bin/patchview` (a copy with a stub `show`), `dev/strand_runner.py`, the `diff` binary.

## State

Nothing shared: every run builds and removes its own fixtures.
