---
name: iterative-dev-doccheck
description: Systematic documentation & structure compliance check. Use when the user asks to check/audit a project's docs and folder structure against the documentation rules. Two passes that BOTH check everything — structure (decision↔OldThemes matching), decisions deep-dive, OldThemes assignment via RAG, dev, DOCS via pattern-scripts, a language sweep, and skills. Opus runs all steps solo and fixes decisions/ + OldThemes/; a worker re-runs all steps one at a time and fixes dev/ (and patches any decisions/OldThemes miss Opus left). Two user gates: Opus reports before spawning the worker, and again when the worker is done. Skills is report-only and runs last — skill edits need the user's approval. The doc-side counterpart to iterative-dev-refactor.
---

# Doc & Structure Check

Audit docs + folder structure against the documentation rules, in two passes. Both passes investigate EVERYTHING identically and flag the same findings; they differ only in who may APPLY a fix (§ What each agent does). Two user gates: Opus reports after Pass 1 (before spawning the worker) and after Pass 2. Step 7 (skills) is report-only — SKILL.md edits need user approval.

## The rule is the fence

The rules are the standard, not the project's current state. NEVER accept an existing structure as a "project convention" that excuses a deviation — "it's consistent everywhere" is not a defense; a consistent deviation is still a deviation. Diverges from a rule → the rule wins: flag it, bring it into line. A deviation stays only on an explicit user decision, never on your own "it already works".

## Scope

Project root (cwd). Surfaces: `decisions/` + `decisions/OldThemes/`, `dev/`, every `DOCS.md`, `skills/*/SKILL.md`.
Filter runtime artifacts every step: `__pycache__/`, `.git/`, `venv/`, `.venv/`, `node_modules/`, `.claude/worktrees/`.

## What each agent does

Investigation + flagging: IDENTICAL for both — same surfaces, same findings. They differ in one thing, who APPLIES a fix:

- Documentation fixes (`decisions/`, `decisions/OldThemes/`, every `DOCS.md` incl. dev) — either agent; whoever finds it fixes it.
- Source-code fixes (`dev/` scripts, `.py`, in-code paths, file/folder renames) — WORKER only; Opus never edits source.

Pass 1: Opus fixes the docs it finds, flags the source fixes. Pass 2: the worker re-checks everything on Opus's committed state, fixes any doc miss, applies the flagged source fixes.

## Workflow

### Pass 1 — Opus solo → Gate 1

Run all steps across every surface. Per step: read → state findings in chat → fix (docs you apply directly; source fixes you flag for the worker). Do NOT go idle between steps. Step 7 is report-only. Then COMMIT the doc work (the worker branches from it) → report fixes + what you flagged for the worker → **Gate 1**. Wait for approval before spawning the worker.

### Pass 2 — Worker step-by-step → Gate 2

On approval, re-sync the docs RAG index yourself first — Opus updates docs, NOT the worker — so Step-3 RAG runs on the current structure. This mid-check sync is MANDATORY and overrides the global rule "RAG sync only at recap, never mid-session". Spawn one worker on the committed state, have it activate this skill. It branches from the Pass-1 commit: your doc fixes are already in place, it checks that fixed state. It runs the steps one at a time, reports after each. Left for it: doc misses you left + the flagged source fixes. Review each report vs your Pass-1 work; where you agree, send it to apply (rename a report script with its `NN_` prefix, change an in-code path, move/merge/delete a dev file — confirm deletions with the user). Converge first — never send a fix you and it disagree on. Step 3 RAG: this skill authorizes the worker to run `rag-cli` (Bash), the one place a worker uses RAG. Step 7: worker reports only, no skill edit. Timer after each send. At Step 7, read the skill yourself to judge its findings → report → **Gate 2**.

Steps (both passes):
1. Structure — decision ↔ OldThemes matching
2. decisions — deep dive
3. OldThemes — assignment (RAG) + content (grep)
4. dev — deep dive
5. DOCS — structural checks via scripts
6. Language — non-English sweep
7. skills — deep dive (report-only, last)

## Step 1 — Structure

One thematic area = one `decisions/<area>.md` + one same-named `decisions/OldThemes/<area>/` + same name in `dev/<area>/`. Splitting a decision file in two and moving its OldThemes with it is allowed. Target shape:

```
decisions/
├── auth.md
├── delivery.md
├── retrieval.md
└── OldThemes/
    ├── auth/
    ├── retrieval/
    └── ...
```

A decision file with no process history needs no OldThemes folder (`delivery.md`). An OldThemes folder without a same-named decision file must never exist.

Step 1 = match decision-file stems (every `*.md` directly in `decisions/`, excluding `OldThemes/`) against OldThemes folder names. Name matches → fine. Flag only:

- decision file with no same-named OldThemes folder
- OldThemes folder with no same-named decision file
- any `.md` loose directly in `decisions/OldThemes/` (straggler)

Carry mismatches to Step 3. Do NOT read OldThemes files here. Do NOT look at `dev/` here — that is Step 4.

## Step 2 — decisions Deep-Dive

Read every `decisions/<area>.md` in full (few + small). Per file: check the rules, state findings, fix (decision files are docs). This also loads their content for Step 3.

- Sections in order: IST, Evidenz, Offene Fragen, Quellen. Empty section omitted, never padded (`None.`, `No benchmarks run.`) — fix filler + out-of-order.
- No SOLL — no `SOLL` token, no `Recommendation (SOLL)` section, no desired-future-state (→ issue). ("soll ich" chat phrase excepted.)
- No issue references (`#`-number, `/issues/`).
- IST resting on a measurement (benchmark, timing, "better/faster than X") cites it in Evidenz; plain behavioral/config description (readable from code) needs none. Fix only a measured claim missing its evidence.
- Evidenz cites the dev report (script, report-MD, dataset), key result only — fix a full report pasted in.

## Step 3 — OldThemes Deep-Dive

Two stages. Never read a whole OldThemes file — RAG chunks + grep only.

### Stage 1 — assignment (RAG)

Input = Step-1 mismatches (unmatched decision files, unmatched folders, stragglers). One decision file at a time:

1. Unmatched decision file (content known from Step 2).
2. ONE RAG query, its topic/IST, scoped to STILL-UNASSIGNED folders — a paired folder drops out. Path scope: `--document "%OldThemes/<folder>/%"` includes, `--exclude "%OldThemes/<folder>/%"` drops:
   `rag-cli search_hybrid "<topic>" <Project>-docs --exclude "%OldThemes/<already-paired>/%"`
   (with `auth`/`retrieval`/`discovery`, `discovery` paired → include `auth`+`retrieval`, exclude `discovery`).
3. Chunks (not whole files) → the folder dominating the top hits is the match.
4. Rename that folder to the decision stem; drop it from the pool.
5. Next decision file — one query each.

Straggler `.md`: same query on its content → `git mv` into the best match, or a new area-named folder if none fits.

Never pull an `.md` OUT of a folder — files stay together. Only moves: rename a folder to its decision stem, create a folder for a straggler, drop a straggler into an existing folder. In Pass 2 the worker runs the same queries and moves what it agrees on.

### Stage 2 — content (grep, never read files)

Grep the OldThemes files (or act on Stage-1 RAG chunks). Check:

- issue references (`#`-number, `/issues/`)
- present-tense "current"/"production" claims — OldThemes is historical, these go stale
- a superseded measurement presented as current IST

State findings, fix.

## Step 4 — dev Deep-Dive

Three sub-steps. Opus FLAGS only; the worker applies every source change (folder renames, in-code paths, report moves).

**4a — structure.** Match `dev/` folder names against decision stems. Flag: a dev folder with no same-named decision file; any file loose in `dev/` with no folder home — incl. a maintenance/utility script (reclean, one-shot fixer): it goes in its thematic `dev/<area>/`, unnumbered if it emits no report. No exempt catch-all folder — every dev file resolves to an area. Name-matches stay.

**4b — assignment.** Per unassigned dev folder: read that folder's `DOCS.md` (or the root module docstring if none) — the dev RAG-replacement; its own doc states its area. Rename to the decision stem.

**4c — report convention.** Report-producing script numbered (`01_`, …); non-report script unnumbered; every report in the area's `md/`/`csv/`/`png/` folder with its script's `NN_` prefix. A per-script `NN_<name>_reports/` folder is wrong → reports in the shared type-folder, script's in-code output path points there. Reports never to console — a numbered script writes to a file. Opus flags; the worker applies renames, moves, in-code paths.

## Step 5 — DOCS Deep-Dive

Three structural checks via heredoc / `/tmp` scripts — not by reading every `DOCS.md`:

1. **Schema** — each `DOCS.md`: Role, Public Interface, Flow, Modules (each: Purpose, Reads, Writes, Called-by, Calls-out), State, Gotchas; module-level only.
2. **References resolve** — every file a `DOCS.md` names exists on disk.
3. **No orphans** — every `.py` at a `DOCS.md`'s level appears in it.

State findings, fix the `DOCS.md` directly (all DOCS.md are documentation).

## Step 6 — Language

Grep every surface (`decisions/`, `OldThemes/`, every `DOCS.md`, `dev/` reports, code comments) for non-English — German tokens, any glossed `(German)` term. Found → translate to English, values + meaning exact (a superseded number stays historical, never silently updated). "soll ich" excepted only as chat, never in an artifact.

## Step 7 — skills Deep-Dive (report-only, last)

`skills/*/SKILL.md` = procedure, not essay: states WHAT (capability + output) and HOW (steps, commands, thresholds, formats, rules incl. "do NOT X"), never WHY.

Removability test per clause: reader still executes exactly the same without it? Yes → WHY → cut. A concrete example stays only when it shows HOW to decide.

Read each `SKILL.md` under `skills/`, flag WHY-content by signature:

| Signature | Example | Action |
|---|---|---|
| Justification clause | "raw and maximal — content not captured is gone for good" | cut clause, keep instruction |
| Cause / mechanism | "the plugin cache has NO venv, so a plugin-relative path fails" | cut |
| Rationale section | a "Why X matters" section | delete section |
| Historical / evidence note | "(verified on 278 files)", "previous runs failed here" | cut |
| Illustrative "what happens otherwise" | "the same anchor just returns the same top sources" | cut |
| `because` / `so that` / `in order to` / `which means` | any clause led by these | cut clause |

Keep — never flag: commands, paths, thresholds, output formats, parameter tables, ordering rules, prohibitions, behavior facts the procedure depends on, decision-examples.

REPORT-ONLY: neither agent edits a SKILL.md here. Hand WHY-findings to the user with the Gate-2 report; strip only after user approval.
