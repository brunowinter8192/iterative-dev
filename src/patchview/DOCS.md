# src/patchview/

## Role

Renders a proposed change to a user-owned rule or skill file as a self-contained HTML page: the whole target file, removed lines on red, added lines on green, unchanged lines plain. Verifies that the patch still applies to the live file. Touch for patch parsing, apply semantics or page look.

## Public Interface

`__init__.py` is a package marker only, no exports. Entry path:

```bash
python3 <repo>/src/patchview/__main__.py <patch-file>
```

Run as a script, never as `-m src.patchview`: the caller's cwd may hold its own `src` package, which would shadow this one.

`bin/patchview` wraps this, opens the page via `bin/show` and is the command users and agents call. Prints exactly one line on success: the path of the written page.

## Flow

Patch file (plain `diff -u` output against ONE live file, absolute path in the `---` line) → live path and hunks parsed → live file read-only → every hunk located by exact match of its context and removed lines, searching forward from the end of the previous hunk, nearest to the stated line number (offset allowed, no fuzz) → page built from the walk → written to `$TMPDIR/patchview/` → path on stdout. Any problem (not a unified diff, relative live path, unreadable file, hunk not found) prints one reason to stderr, writes no page, exits non-zero. The live file is never modified.

## Modules

### __main__.py (194 LOC)

**Purpose:** The whole renderer: patch parsing, strict hunk application against the live file, HTML page generation and writing.
**Reads:** the patch file and the live file named by its `---` line; `TMPDIR` from the environment.
**Writes:** one HTML page under `$TMPDIR/patchview/` (fallback `/tmp`); stdout (page path); stderr (failure reason).
**Called by:** `bin/patchview` (runs the file directly), `dev/patchview/test_patchview.py`.
**Calls out:** nothing, stdlib only.

## State

None. The page name derives from the patch name plus a hash of the patch's real path, so a re-run overwrites its own page. See `process-docs/patchview/` for the design decisions.
