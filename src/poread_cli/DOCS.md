# src/poread_cli/

## Role

Standalone CLI (`poread <path>`) that lets an agent bring one file's full content into the model's context past Bash's inline-result ceiling. It prints a short marker plus a fixed notice; a proxy addon in another repo swaps in the content. Touch for argument handling, size limit or marker format.

## Public Interface

`__init__.py` is a package marker only, no exports. Entry path from the plugin root:

```bash
python3 -m src.poread_cli <path>
```

`bin/poread` wraps this and is symlinked to `~/.local/bin/poread`, so `poread <path>` works from any cwd. It resolves the plugin cache through the plugin-root environment variable, with the standard plugin-cache location under the home directory as fallback.

## Flow

One positional path argument → real-path resolution → file size checked against the ceiling BEFORE the file is opened, so an oversize file is never read into memory just to be rejected → file read and hashed (sha256, truncated) → exactly two lines on stdout, the marker then the fixed notice, exit 0. Any failure (missing path, not a file, unreadable, over the ceiling, malformed argv) prints one reason to stderr, prints neither line, exits non-zero; no truncated or partial export is ever produced.

## Modules

### __main__.py (77 LOC)

**Purpose:** The whole CLI: argument parsing, size-ceiling tripwire, file read, marker and notice emission.
**Reads:** The named file's bytes and size from disk; argv.
**Writes:** stdout (marker line then notice line on success, nothing otherwise); stderr (one reason line on any failure).
**Called by:** `bin/poread` (via `-m src.poread_cli`); nothing else, it is a leaf CLI entry point never imported by other `src/` code.
**Calls out:** nothing, stdlib only by design: this is what makes the CLI installable into a plugin cache with no venv.

## State

The size ceiling, hash length, marker prefix and notice sentence are a hand-maintained copy of monitor-cc's own copy in `src/proxy/inject_poread.py (Monitor_CC)`. There is no shared import between the two repos and no CI to catch drift. See `process-docs/poread/` for the full contract, its silent-failure mode, and why the notice sentence is part of the match, not just an extra printed line.
