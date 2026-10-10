# 2026-10-10 - patchview: red/green review page for rule and skill patches

Worker task on branch `patchview`. New area, no earlier entry.

## Problem

Rules (`~/.claude/shared-rules/`) and skills are user-owned; a PreToolUse hook blocks agents from editing them. Agents store proposed changes as patches in `dev/<area>/patch/` of their project. On 2026-10-04 the user rejected Old/New text blocks as unreadable. What he accepted: an HTML page of the WHOLE target file, removed lines on red, added lines on green, unchanged plain, opened in the browser, identical form every time. The accepted page came from an ad-hoc script (`/tmp/rules-review/render_diff.py`, two full files in, `difflib` opcodes). `patchview` is the permanent version, driven by a patch instead of two files.

## Decisions

1. **New command, not an extension of `show`.** `show` only opens files. `bin/patchview` is a humble wrapper: python renders and prints the page path, then `bin/show <page>` opens it (HTML falls into the generic `open` branch, i.e. the default browser). The wrapper resolves its repo via `readlink -f` of itself (as `worker-cli` does), so the repo working copy is live without `plugin-publish`. It does NOT `cd` into the repo (as `poread` does): the patch argument may be relative to the caller's cwd.
2. **Patch format = plain `diff -u`, no custom header.** The `---` line already names the live file. Required: absolute path (or `~`), single file. The tab-separated timestamp after the path is cut off. Creation: `diff -u <absolute live file> <new file> > dev/<area>/patch/<name>.patch`. The live file MUST be the first argument. `git diff` style `a/` `b/` prefixes are not supported (never observed).
3. **Apply semantics: exact context, offset allowed, no fuzz** (like `patch -F0` / `git apply`). Observed on 2026-10-10: between two proposal rounds the user edited `workers.md` himself in other places, so a patch whose hunks still match exactly at shifted line numbers has to apply. Per hunk, the block of context + removed lines must match the live file exactly; the search runs forward from the end of the previous hunk, the match nearest to the stated old line number wins. No match anywhere = stale patch = fail loudly (`STALE PATCH: hunk N ...`, exit 1), nothing rendered, nothing written. First planned as strict-at-stated-line; the user changed it to offset-tolerant for the reason above.
4. **The page is built from the same walk that applies the patch** (live lines between hunks plain, hunk lines red/green), not from a second `difflib` pass. What the user reviews is exactly the patch, not a recomputed diff. Own applier instead of the `patch` binary so nothing can ever write to the live file and the failure message is ours.
5. **Page location:** `${TMPDIR:-/tmp}/patchview/<patch-stem>-<12 hex of sha256 of the patch real path>.html`. Never inside the user's repos; same-named patches from different projects do not collide; re-running overwrites, so the browser tab reloads to the new state. The page is written only after the whole patch applied.
6. **Look** is taken from `render_diff.py` (dark page, `-`/`+` gutter, legend with line counts). Legend text stays German as in the accepted page.

## Verified (2026-10-10)

- `dev/patchview/test_patchview.py`: 5 strands pass (applies, offset, stale, bad argv, missing live file).
- One-off on the real accepted pair `/tmp/rules-review/workers-ist.md` / `workers-soll.md`: patch made with `diff -u`, rendered rows minus green = ist, minus red = soll (page body reproduces the soll file exactly); same patch against ist prefixed with two extra lines applies and shows them plain. Patch against an ist whose `### Lebenszyklus ...` heading (inside hunk 1 context) was edited fails with STALE.

## Pitfalls for a successor

- Do not test `bin/patchview` end to end with an applicable patch: it calls `show` and opens a browser. The wrapper smoke test of 2026-10-10 did exactly that by accident (a throw-away page opened). Test the python entry (`patchview_workflow`) only; the wrapper's failure path is safe with a stale patch.
- `read_text_lines` splits on `\n` only (not `str.splitlines`), so form feeds or unicode separators in a rule file cannot shift line counts against `diff`.
- Unsupported, never observed: `\ No newline at end of file` content differences are skipped, not rendered; CRLF files; blank context lines stripped of their leading space by an editor (parsed as malformed hunk, fails loudly).

## Verification command (for after merge, by the orchestrator)

```
ln -s <iterative-dev>/bin/patchview ~/.local/bin/patchview     # once; not done by the worker
diff -u ~/.claude/shared-rules/main/workers.md /tmp/<new>.md > <project>/dev/<area>/patch/workers.patch
patchview <project>/dev/<area>/patch/workers.patch
```

## Recap (2026-10-10)

- Files of this task: `bin/patchview`, `src/patchview/__main__.py`, `src/patchview/__init__.py`, `dev/patchview/test_patchview.py`, the three DOCS.md files (`bin/`, `src/patchview/`, `dev/patchview/`) and this entry. LOC values in the DOCS.md headings were checked against `wc -l` (24 / 193 / 170) and match.
- Date question: the orchestrator asked for the file to carry 2026-10-04, stating that `date` would show it. `date +%F` on this machine printed 2026-10-10, and the mtimes of `/tmp/rules-review/*` are also 2026-10-10. The file name and the dates inside therefore stay at 2026-10-10 until the orchestrator confirms otherwise. The only 2026-10-04 in this entry is the day the user rejected the Old/New blocks, as told in the task brief.
