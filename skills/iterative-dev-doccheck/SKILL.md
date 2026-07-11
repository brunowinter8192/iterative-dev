---
name: iterative-dev-doccheck
description:
---

# Doc & Structure Check

Audit docs + folder structure against the documentation rules, in two passes. Both passes investigate EVERYTHING identically and flag the same findings; they differ only in who may APPLY a fix (§ What each agent does). Two user gates: Opus reports after Pass 1 (before spawning the worker) and after Pass 2. Step 6 (skills) is report-only — SKILL.md edits need user approval.

**Model.** Current state lives in CODE, not docs. `process-docs/` (project root) is write-once process history — one folder per area, never maintained after writing. `DOCS.md` is the ONLY continuously-maintained doc surface (module map, in lockstep with code). Issues carry targets / open questions; docs never reference issues.

**Report language: German.** Every report to the user — both gate reports and any interim status — is written in German. This governs the chat surface only; all ARTIFACTS (process-docs, DOCS.md, code) stay English per the documentation rules, regardless of the German chat.

## The rule is the fence

The rules are the standard, not the project's current state. NEVER accept an existing structure as a "project convention" that excuses a deviation — "it's consistent everywhere" is not a defense; a consistent deviation is still a deviation. Diverges from a rule → the rule wins: flag it, bring it into line. A deviation stays only on an explicit user decision, never on your own "it already works".

## Scope

Project root (cwd). Surfaces: `process-docs/`, every `DOCS.md`, `dev/`, `skills/*/SKILL.md`.
Filter runtime artifacts every step: `__pycache__/`, `.git/`, `venv/`, `.venv/`, `node_modules/`, `.claude/worktrees/`.

## What each agent does

Investigation + flagging: IDENTICAL for both — same surfaces, same findings. They differ in one thing, who APPLIES a fix:

- Documentation fixes (`process-docs/`, every `DOCS.md` incl. dev) — either agent; whoever finds it fixes it.
- Source-code fixes (`dev/` scripts, `.py`, in-code paths, file/folder renames) — WORKER only; Opus never edits source.

Editing a `process-docs/` entry for COMPLIANCE (strip a rot-prone ref, translate, date-frame a stale claim) is one-time normalization, NOT maintenance — allowed and required here, even though entries are write-once in normal operation.

Pass 1: Opus fixes the docs it finds, flags the source fixes. Pass 2: the worker re-checks everything on Opus's committed state, fixes any doc miss, applies the flagged source fixes.

## Workflow

### Pass 1 — Opus solo → Gate 1

Run all steps across every surface. Per step: read/grep → state findings in chat → fix (docs you apply directly; source fixes you flag for the worker). Do NOT go idle between steps. Step 6 is report-only. Then COMMIT the doc work (the worker branches from it) → report fixes + what you flagged for the worker → **Gate 1**. Wait for approval before spawning the worker.

### Pass 2 — Worker step-by-step → Gate 2

On approval, spawn one worker on the committed state, have it activate this skill. It branches from the Pass-1 commit: your doc fixes are already in place, it checks that fixed state. It runs the steps one at a time, reports after each. Left for it: doc misses you left + the flagged source fixes. Review each report vs your Pass-1 work; where you agree, send it to apply (move a report into the area's `md/` and repoint its in-code path, move/merge/delete a dev file — confirm deletions with the user). Converge first — never send a fix you and it disagree on. Step 6: worker reports only, no skill edit. Timer after each send. At Step 6, read the skill yourself to judge its findings → report → **Gate 2**.

Steps (both passes):
1. Structure
2. process-docs — invariants (grep)
3. dev — deep dive
4. DOCS — placement / schema / coverage via scripts
5. Language — non-English sweep
6. skills — deep dive (report-only, last)

## Step 1 — Structure

- **No current-state doc mirror.** No doc may duplicate live config/state as an authoritative "current state" — that is the code's job. A doc asserting present-tense production state as if maintained (anything outside DOCS.md's module map) → flag.
- **process-docs shape.** `process-docs/` sits at project root, one folder per thematic area, no loose top-level `.md`. Loose top-level `.md` → home it into an area folder. An area split across differently-named folders → flag as a consolidation candidate (report only; consolidation is a user call, not an auto-move).

## Step 2 — process-docs Invariants

Grep the tree — never read whole files. Per invariant: grep, state findings, fix directly (process-docs are docs; compliance edits are allowed here).

- **No doc-to-doc cross-references.** Strip any reference to another doc/report FILE: `decisions/...`, `process-docs/...`, a bare sibling `.md` filename naming another entry (`NN_*.md`, `<slug>.md`, `<folder>/NN_*.md`), a `DOCS.md` / `SKILL.md` / rule-file path. KEEP: `dev/...` refs (evidence provenance — incl. bare `NN_reports/...md` report names), `src/...` paths and code symbols, `/tmp/...`, and generated pipeline data/log artifact filenames (a file a script produces, not a doc entry — judge by whether a script emits it). Fix: keep the finding, drop the path, reword; delete pure pointer lines / Sources-list bullets.
- **No issue references.** Strip our issue-tracker / task-tracker (bead) tokens: `issue #<1-3 digits>`, `bead <id>`, tracker-ID list/header lines. KEEP external upstream citations (another project's `#<4+ digits>`, `PR #...`) and tool/CLI names that share the tracker prefix. Fix: drop the token, keep the content.
- **No present-tense current/production claims.** Entries are write-once history → reframe "X is the production value / current state" to dated framing ("as of <date>, X was …"). A former-decision snapshot file carries a one-line dated snapshot header directly below its H1; strip any stale `decisions/<x>.md —` prefix from such an H1.
- **Structure.** Entries dense, dated, thematic. Non-English is flagged here but fixed in Step 5.

## Step 3 — dev Deep-Dive

Three sub-steps. Opus FLAGS only; the worker applies every source change (folder renames, in-code paths, report moves).

**3a — structure.** Match `dev/` folder names against `process-docs/<area>/` area folders where they exist. Flag: a dev folder or a file loose in `dev/` with no area home — incl. a maintenance/utility script (reclean, one-shot fixer): it goes in its thematic `dev/<area>/`. No exempt catch-all folder. A loose `.md` in `dev/` that **no script produces** (a hand-written run summary / analysis) is NOT a dev report → it belongs in `process-docs/` if still relevant, or is deleted if stale — never left loose at dev root.

**3b — assignment.** Per unassigned dev folder: read that folder's `DOCS.md` (or the root module docstring if none) — its own doc states its area. Rename to the area name.

**3c — report convention.** Every report goes in the area's shared `md/` / `csv/` / `png/` folder (by output type) with a DESCRIPTIVE name traceable to its producing script — **dev scripts are NOT numbered**. A per-script `NN_<name>_reports/` folder (or a shared `NN_reports/` dump) is wrong → reports move into the shared type-folder, the script's in-code output path points there. Reports never to console — a report-producing script writes to a file. Opus flags; the worker applies the moves + in-code paths.

Clarifications (recurring cases):
- **Report vs DATA.** The convention governs REPORTS — a human-readable analysis a script emits (`.md` summary, `.csv` table, `.png` chart; a JSON *analysis* output counts, → `md/`). It does NOT govern bulk DATA outputs (scraped-page corpora, raw sweep dumps, per-URL review dumps, cached job data). Data-output folders stay put — never moved into `md/`. Distinguish by content: a report is a readable analysis; data is the run's raw payload.
- **Type → type-folder.** `.md`→`md/`, `.csv`→`csv/`, `.png`→`png/`. Never mix report + data in one output folder — a folder holding both `.md` reports and `.json` data is split (reports → `md/`, data stays separate).
- **Cumulative logs stay.** An append-only log tracked + compared across runs (institutional history, not a single-run analysis) is NOT a report → leave in place.
- **Sub-suite own `md/`.** A self-contained sub-eval folder (`garbage_eval/`, `browser_eval/`) gets its OWN `md/`, not the parent area's.
- **Existing `NN_` script names.** No numbering is required or added. Pre-existing number prefixes on script/report names are just part of the name — neither a violation to keep nor mandated; do not add new ones, and strip them only if the user asks for a normalization pass.

## Step 4 — DOCS Deep-Dive

The central maintained surface. Two stages, both run. Use heredoc / `/tmp` scripts — not by reading every `DOCS.md`. Do NOT be timid — flag every deviation.

### Stage 1 — placement & coverage

- Every `DOCS.md` sits at the level of the `.py` files it documents (a module-bearing directory). A `DOCS.md` at a level with no `.py`, or `.py` modules at a level with no `DOCS.md`, is a deviation.
- Each `DOCS.md` documents EXACTLY the modules at its own level — every `.py` at the level appears; it names no module from a different level. A root `DOCS.md` describing the whole project — pipeline overview, project tree, other directories — instead of only its own-level `.py` → flag for removal (or reduction to own-level module docs).

**Root files.** `README.md` → flag for removal. A root `DOCS.md` that is a project overview → flag for removal. A root `CLAUDE.md` documenting project-only interactive working areas → allowed, do not flag.

### Stage 2 — internal structure

- **Schema** — each `DOCS.md` follows the format exactly: Role, Public Interface, Flow, Modules (each: Purpose, Reads, Writes, Called-by, Calls-out), State, Gotchas; module-level only. Anything OUTSIDE the format is a deviation → flag it (project-structure tree, overview / "Pipeline Components" section, "Key Files" table, any free-form section).
- **References resolve** — every file a `DOCS.md` names exists on disk.
- **LOC** — each module heading's `<LOC>` matches the file's `wc -l`.

State findings, fix the `DOCS.md` directly (all `DOCS.md` are documentation).

## Step 5 — Language

Grep every surface (`process-docs/`, every `DOCS.md`, `dev/` reports, code comments) for non-English — German tokens, any glossed `(German)` term. Found → translate to English, values + meaning exact (a superseded number stays historical, never silently updated). "soll ich" excepted only as chat, never in an artifact.

## Step 6 — skills Deep-Dive (report-only, last)

`skills/*/SKILL.md` = procedure, not essay: states WHAT (capability + output) and HOW (steps, commands, thresholds, formats, rules incl. "do NOT X"), never WHY.

**Frontmatter.** `description:` is present but empty — flag any non-empty `description` and blank it.

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
