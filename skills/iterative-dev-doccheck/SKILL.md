---
name: iterative-dev-doccheck
description:
---

# Doc & Structure Check

Audit docs + folder structure against § Documentation Hierarchy. Run the steps in order; per step read/grep, state findings, fix what you find.

**Report language: German.** Every report is written in German. This governs the chat surface only; all ARTIFACTS (process-docs, DOCS.md, code) stay English per § Documentation Hierarchy, regardless of the German chat.

## The rule is the fence

The rules are the standard, not the project's current state. NEVER accept an existing structure as a "project convention" that excuses a deviation — "it's consistent everywhere" is not a defense; a consistent deviation is still a deviation. Diverges from a rule → the rule wins: flag it, bring it into line. A deviation stays only on an explicit user decision, never on your own "it already works".

## Workflow

### Step 1 — process-docs

#### Stage 1 — structure

`process-docs/` sits at project root, one folder per thematic area, no loose top-level `.md`. Loose top-level `.md` → home it into an area folder. An area split across differently-named folders → flag as a consolidation candidate (report only; consolidation is a user call, not an auto-move).

#### Stage 2 — invariants

Grep the tree — never read whole files. Check every process-docs entry complies with § Language, § No Issue References, and § process docs (no present-tense current/production claims, dense/dated/thematic, no cross-references to another process-docs entry, evidence inline). State findings, fix directly — editing a write-once entry for compliance is one-time normalization, allowed here. Non-English is flagged here, fixed in Step 4.

### Step 2 — dev Deep-Dive

Three stages, all source-level (folder renames, in-code paths, report moves).

#### Stage 1 — structure

Match `dev/` folder names against `process-docs/<area>/` area folders where they exist. Flag: a dev folder or a file loose in `dev/` with no area home — incl. a maintenance/utility script (reclean, one-shot fixer): it goes in its thematic `dev/<area>/`. No exempt catch-all folder. A loose `.md` in `dev/` that **no script produces** (a hand-written run summary / analysis) is NOT a dev report → it belongs in `process-docs/` if still relevant, or is deleted if stale — never left loose at dev root.

#### Stage 2 — assignment

Per unassigned dev folder: read that folder's `DOCS.md` (or the root module docstring if none) — its own doc states its area. Rename to the area name.

#### Stage 3 — report convention

Every report goes in the area's shared `md/` / `csv/` / `png/` folder (by output type) with a DESCRIPTIVE name traceable to its producing script — **dev scripts are NOT numbered**. A per-script `NN_<name>_reports/` folder (or a shared `NN_reports/` dump) is wrong → reports move into the shared type-folder, the script's in-code output path points there. Reports never to console — a report-producing script writes to a file.

Clarifications (recurring cases):
- **Report vs DATA.** The convention governs REPORTS — a human-readable analysis a script emits (`.md` summary, `.csv` table, `.png` chart; a JSON *analysis* output counts, → `md/`). It does NOT govern bulk DATA outputs (scraped-page corpora, raw sweep dumps, per-URL review dumps, cached job data). Data-output folders stay put — never moved into `md/`. Distinguish by content: a report is a readable analysis; data is the run's raw payload.
- **Type → type-folder.** `.md`→`md/`, `.csv`→`csv/`, `.png`→`png/`. Never mix report + data in one output folder — a folder holding both `.md` reports and `.json` data is split (reports → `md/`, data stays separate).
- **Cumulative logs stay.** An append-only log tracked + compared across runs (institutional history, not a single-run analysis) is NOT a report → leave in place.
- **Sub-suite own `md/`.** A self-contained sub-eval folder (`garbage_eval/`, `browser_eval/`) gets its OWN `md/`, not the parent area's.
- **Existing `NN_` script names.** No numbering is required or added. Pre-existing number prefixes on script/report names are just part of the name — neither a violation to keep nor mandated; do not add new ones, and strip them only if the user asks for a normalization pass.

### Step 3 — DOCS Deep-Dive

The central maintained surface. Two stages, both run. Use heredoc / `/tmp` scripts — not by reading every `DOCS.md`. Do NOT be timid — flag every deviation.

#### Stage 1 — placement & coverage

- Every `DOCS.md` sits at the level of the `.py` files it documents (a module-bearing directory). A `DOCS.md` at a level with no `.py`, or `.py` modules at a level with no `DOCS.md`, is a deviation.
- Each `DOCS.md` documents EXACTLY the modules at its own level — every `.py` at the level appears; it names no module from a different level. A root `DOCS.md` describing the whole project — pipeline overview, project tree, other directories — instead of only its own-level `.py` → flag for removal (or reduction to own-level module docs).

**Root files.** `README.md` → flag for removal. A root `DOCS.md` that is a project overview → flag for removal. A root `CLAUDE.md` documenting project-only interactive working areas → allowed, do not flag.

#### Stage 2 — internal structure

- **Schema** — each `DOCS.md` follows the format exactly: Role, Public Interface, Flow, Modules (each: Purpose, Reads, Writes, Called-by, Calls-out), State, Gotchas; module-level only. Anything OUTSIDE the format is a deviation → flag it (project-structure tree, overview / "Pipeline Components" section, "Key Files" table, any free-form section).
- **References resolve** — every file a `DOCS.md` names exists on disk.
- **LOC** — each module heading's `<LOC>` matches the file's `wc -l`.

State findings, fix the `DOCS.md` directly.

### Step 4 — Language

Grep every surface (`process-docs/`, every `DOCS.md`, `dev/` reports, code comments) for non-English — German tokens, any glossed `(German)` term. Found → translate to English, values + meaning exact (a superseded number stays historical, never silently updated). "soll ich" excepted only as chat, never in an artifact.

### Step 5 — skills Deep-Dive (report-only)

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

REPORT-ONLY: do not edit a SKILL.md here — hand the WHY-findings over; strip only after user approval.

### Step 6 — Hand off

Report your findings. Then, if you are Opus: commit your doc fixes, sync them to RAG (`rag-cli update_docs`), and spawn a worker to activate this skill (`iterative-dev-doccheck`) — it re-runs the audit on the committed state and applies the flagged source fixes. If you are a worker, you're done — no spawn.
