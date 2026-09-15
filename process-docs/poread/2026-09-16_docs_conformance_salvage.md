# 2026-09-16 — src/poread_cli/DOCS.md conformance, Gotchas salvage

Worker task on branch `sweepitdev`, same worktree as the three prior milestones in this sweep.
Main scanned every DOCS.md across all four projects touched by this sweep and found
`src/poread_cli/DOCS.md` still carried a `## Gotchas` section — out of the Role / Public
Interface / Flow / Modules / State format the rest of this project's touched DOCS.md files were
already converted to in the module-standards-conformance milestone. This is the one real item
out of three Main flagged; `src/DOCS.md` and `dev/DOCS.md` were explicitly left alone — they
hold no `.py` modules of their own, they're navigation maps over subdirectories, and a Modules
section there would be empty while the Directory Map/Areas list they already have is what
actually serves a reader.

## Salvage from src/poread_cli/DOCS.md

The full `## Gotchas` section, verbatim, before removal:

```
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
```

(The `(Monitor_CC)` cross-repo markers inside the backticks above are from the prior
docs-drift-check milestone, not new here — carried through verbatim as they stood in the file at
the moment of salvage.)

## What changed in src/poread_cli/DOCS.md

- Removed the `## Gotchas` heading and both paragraphs above (now living only here).
- Role's closing sentence pointed at "see Gotchas for what else needs to change alongside it" —
  redirected to "see State" since Gotchas no longer exists in the file.
- Added a `## State` section: a short, honest paragraph naming the four constants, the
  hand-maintained-copy fact, and the no-shared-CI fact, then pointing to `process-docs/poread/`
  (this file) for the full contract. Not a paraphrase-and-drop of the salvaged text — the full
  text lives above, verbatim; the State section is a legitimately new, terse, format-compliant
  summary earning its own place under the standard's "State: which module owns state, who reads
  it" definition, since the shared-contract-with-a-sibling-repo IS the state this module's Role
  already gestures at needing explained somewhere.

## Verification

`python3 ~/.local/bin/docs-drift-check` from the project root, before vs. after this change:

```
Before: Path-Drift 0, LOC-Drift 0, Symbol-Drift 0, Total 0 (exit 0)
After:  Path-Drift 0, LOC-Drift 0, Symbol-Drift 0, Total 0 (exit 0)
```

Stayed at zero — the `(Monitor_CC)` markers and all four `POREAD_*`/`inject_poread.py` symbols
carried over unchanged from the already-whitelisted/already-correctly-marked state, and moving
prose between two Markdown files doesn't touch anything the checker's path/symbol/LOC checks
look at differently.
