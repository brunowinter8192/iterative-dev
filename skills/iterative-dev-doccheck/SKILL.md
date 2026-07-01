---
name: iterative-dev-doccheck
description: Systematic documentation & structure compliance check. Use when the user asks to check/audit a project's docs and folder structure against the documentation rules. Runs six sequential steps — structure, then deep-dives into decisions, OldThemes, DOCS, dev, skills — findings and fixes one step at a time. The doc-side counterpart to iterative-dev-refactor.
---

# Doc & Structure Check

Audit of a project's documentation and folder structure against the documentation rules. The whole skill is executed by Opus — findings and fixes, doc content and folders alike. It dispatches no workers.

## Scope

Project root (cwd). Surfaces:
- `decisions/` and `decisions/OldThemes/`
- `dev/`
- every `DOCS.md`
- `skills/*/SKILL.md`

Filter runtime artifacts in every step: `__pycache__/`, `.git/`, `venv/`, `.venv/`, `node_modules/`, `.claude/worktrees/`.

## Workflow

Six steps, run ONE AT A TIME. For each step: gather the findings, present them, apply the fixes, then move to the next step. Never run all six at once — Step N's fixes land before Step N+1 starts. Findings go inline in chat; no file is written.

1. Structure — the folder skeleton
2. decisions — deep dive
3. OldThemes — deep dive
4. DOCS — deep dive
5. dev — deep dive
6. skills — deep dive

## Step 1 — Structure

The folder skeleton only, not file contents. An area carries the SAME name in `decisions/<area>.md`, `decisions/OldThemes/<area>/`, and `dev/<area>/`; OldThemes is always a subfolder.

Collect three name sets: the decision-file stems (every `*.md` directly in `decisions/`, excluding the `OldThemes/` subtree), the OldThemes folder names (the subdirectories of `decisions/OldThemes/`), and the dev area names (the subdirectories of `dev/`, excluding `cleanup/`). Compare the sets and flag:

- a decision-file stem with no matching OldThemes folder
- an OldThemes folder with no matching decision file
- a dev area with no matching decision file

Then hunt stragglers — anything hanging outside the area skeleton:

- any `.md` sitting directly in `decisions/OldThemes/` instead of inside an area subfolder — a stray OldThemes file
- any loose file or folder in `dev/` that is neither an area subfolder nor `cleanup/` — a stray script or report with no area home

## Step 2 — decisions Deep-Dive

Read each `decisions/<area>.md` against the decision-file rules:

- Sections present appear in order: Status Quo (IST), Evidenz, Offene Fragen, Quellen. Sections are optional — an empty one is omitted, never padded with filler. Flag filler and out-of-order sections.
- No SOLL — no `SOLL` token, no `Recommendation (SOLL)` section, nothing about a desired future state (that belongs in an issue). Ignore the German phrase "soll ich".
- No issue references — no `#`-number, no `/issues/` URL.
- Every IST claim that has evidence lists it in Evidenz — flag an IST assertion standing without any backing.
- Evidenz cites the dev report (script, report-MD, dataset) and carries only the key result — flag a full report copied into the file.

## Step 3 — OldThemes Deep-Dive

Read the files inside each `decisions/OldThemes/<area>/` folder:

- They hold the process trail — what was tried, rejected, superseded, the iteration history.
- No issue references — not even for an issue that was part of the flow at the time.
- Superseded measurements are kept as historical record, never presented as the current IST.
- English throughout.

## Step 4 — DOCS Deep-Dive

Read each `DOCS.md` against the DOCS.md format:

- Placement — it sits at the level of the `.py` files it documents.
- Structure — Role, Public Interface, Flow, Modules (each: Purpose, Reads, Writes, Called-by, Calls-out), State, Gotchas. Sections optional; entries are module-level, no function-level docs.
- LOC numbers in module headings match the actual `wc -l` of each file.
- Describes WHAT, not HOW. No issue references.

Then run the `docs-drift-check` binary (`~/.local/bin/docs-drift-check`) in the project root: path-existence in indexed docs, LOC-drift in DOCS.md headings, symbol-existence in src, honoring the whitelist at `<cwd>/scripts/docs_drift_whitelist.txt` or `<cwd>/.drift-whitelist.txt`. Exit 0 = clean; exit 1 = drift → list the drifted entries.

## Step 5 — dev Deep-Dive

Inside each `dev/<area>/`, check the report convention:

- A report-producing script is numbered (`01_`, `02_`, …); a script that produces no report is not numbered.
- Its report carries the same number and lives in a `md/`, `csv/`, or `png/` folder — flag a report file outside those type-folders, and a file inside them without a `NN_` number prefix.
- Reports never go to console — open each numbered `[0-9]*_*.py` and confirm its results go to a file, not `print`.
- dev scripts are documented at their own level (dev `DOCS.md`): purpose, usage, CLI flags, expected output.

## Step 6 — skills Deep-Dive

`skills/*/SKILL.md` files are procedures, not essays. A skill states WHAT it does (capability + output) and HOW (steps, commands, thresholds, output formats, rules — including "do NOT X"). It does NOT explain WHY.

Removability test (per sentence/clause): can the reader still execute exactly what the skill describes if this clause is removed? Yes → it is WHY → cut it. A concrete example stays only when it shows HOW to decide.

For each `SKILL.md` under the repo's `skills/` tree, read it and flag WHY-content by signature:

| Signature | Example | Action |
|---|---|---|
| Justification clause | "raw and maximal — content not captured here is gone for good" | cut the clause, keep the instruction |
| Cause / mechanism explanation | "the plugin cache has NO venv, so a plugin-relative path fails" | cut |
| Rationale section | a section titled "Why X matters" | delete the whole section |
| Historical / evidence note | "(verified on 278 files)", "previous runs failed here" | cut the note |
| Illustrative "what happens otherwise" | "the same anchor on every query just returns the same top sources" | cut |
| `because` / `so that` / `in order to` / `which means` | any clause led by these | cut the clause |

Keep — never flag as why: commands, file paths, thresholds, output formats, parameter tables, ordering rules, prohibitions ("do NOT X"), behavior facts the procedure depends on, and decision-examples.

Findings: strip the why in place — keep every procedure, command, threshold, and rule intact. `SKILL.md` is documentation-class — Opus edits it directly. Re-read each edited skill end-to-end to confirm it still reads as an executable procedure.

## Anti-Patterns

- Running all six steps at once instead of findings-then-fix, one step at a time
- Treating a stray root-level OldThemes `.md` as acceptable — it must live inside an area subfolder
- Lifting a full dev report into a decision file — key evidence only; the report stays in `dev/<area>/`
- "Fixing" a flagged empty section by writing filler — empty beats invented
