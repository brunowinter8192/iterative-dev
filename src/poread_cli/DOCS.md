# src/poread_cli/

## Role

Standalone CLI (`poread <path>`), invoked by an agent through Bash, that brings the full content of
one named file into the model's context without going through Bash's own ~30,000-character inline
result ceiling. It prints a short marker naming the file and its size, plus one fixed notice
sentence — its own output always stays far below that ceiling — and relies entirely on
`src/proxy/inject_poread.py (Monitor_CC)` (a different repo, running as a mitmproxy addon in front
of Claude Code's own API traffic) to recognize the marker-plus-notice block inside the resulting
`tool_result` and replace it with the file's full content in the forwarded payload. This package
owns only the marker-minting half. Touch this package when changing the CLI's argument handling,
size ceiling, or marker format — and see Gotchas for what else needs to change alongside it.

## Public Interface

`__init__.py` is a package marker only — no exports. The entry path is the module runner:

```bash
python3 -m src.poread_cli <path>
```

Run from the plugin root, or via `bin/poread` (repo root, mode 755), symlinked to
`~/.local/bin/poread` the same way `bin/gcommit`/`bin/worker-cli` are — `poread <path>` from any
cwd, resolving the plugin cache through `CLAUDE_PLUGIN_ROOT` with the standard
`$HOME/.claude/plugins/cache/...` fallback.

## Flow

`__main__.main(argv)` → one positional path argument → `os.path.realpath` resolution →
`os.path.getsize` against `POREAD_MAX_BYTES` (checked BEFORE the file is ever opened, so an
oversize file is never read into memory just to be rejected) → on success, reads the file, hashes
it (`sha256`, truncated to `POREAD_HASH_LEN`), prints exactly two lines to stdout — the marker,
then `POREAD_NOTICE` — exit 0. Any failure (missing path, not a file, unreadable, over the ceiling,
malformed argv) prints one reason to stderr, prints neither line, and exits non-zero — no truncated
or partial export is ever produced.

## Modules

### __main__.py (77 LOC)

**Purpose:** The whole CLI — argument parsing, size-ceiling tripwire, file read, marker+notice
emission.
**Reads:** The named file's bytes and size from disk; argv.
**Writes:** stdout (exactly the marker line then the fixed notice line on success, nothing
otherwise); stderr (one reason line on any failure).
**Called by:** `bin/poread` (via `-m src.poread_cli`); nothing else — this is a leaf CLI entry
point, never imported by other `src/` code.
**Calls out:** nothing — stdlib only (`hashlib`, `os`, `sys`), by design: this is what makes the
CLI installable into a plugin cache with no venv.

---

## Gotchas

**`POREAD_MAX_BYTES`, `POREAD_HASH_LEN`, `POREAD_MARKER_PREFIX`, `POREAD_NOTICE` are a
hand-maintained copy of monitor-cc's own copy in `src/proxy/inject_poread.py (Monitor_CC)`, not a shared
import — the two repos cannot share one.** Before this package existed here, both halves lived in
monitor-cc and imported these four values from one `src/constants.py (Monitor_CC)`; this package moved out
into this plugin specifically because it is stdlib-only and needed `worker-cli`'s no-venv home, so
the shared import is gone by construction. The exact attribute string this module emits
(`path="..." bytes="..." sha256="..."/>` followed by the fixed notice sentence) and the regex
monitor-cc's `inject_poread.py` parses it with are two separately-maintained pieces of code in two
separate repos that happen to agree. A change to the marker prefix, the ceiling, the hash length,
or the notice sentence on this side without the matching edit on the monitor-cc side makes every
future marker silently fail to expand — the agent sees only the tiny marker-plus-notice lines
forever, no error anywhere. Change both together by hand; there is no shared CI between the two
repos to catch a drift automatically. `dev/poread_cli/test_poread_cli.py` pins its own independent
literal copy of the same four values (not imported from this module) specifically so a drift in
THIS module's copy fails that test loudly instead of silently minting an unexpandable marker;
`dev/proxy/poread_inject_tests.py (Monitor_CC)` does the same for its side.

**The notice sentence is not an extra line the CLI happens to also print — it is a required part
of the whole-block match on the monitor-cc side.** `inject_poread.py`'s regex requires the block to
be exactly `<marker>\n<the fixed POREAD_NOTICE text>`, nothing before, nothing after, nothing
between. A marker with no notice under it, or with different trailing text instead, is ineligible
for expansion on the monitor-cc side — this module has no way to observe that from here, which is
exactly why the notice text must stay byte-identical between the two hand-maintained copies.
