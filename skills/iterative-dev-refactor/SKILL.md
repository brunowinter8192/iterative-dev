---
name: iterative-dev-refactor
description:
---

# Refactor Scan

## Core Rules

**The rules are the standard, and they win over the project's current state.**
- An existing structure is never a project convention that excuses a deviation.
   - A consistent deviation is still a deviation.
- Every review judges against the rule, never against the neighbouring code or the neighbouring entry.

**Main scans, workers fix.**
- Main runs every scan and every classification itself, by AST walk, grep, or `wc`.
- The worker never scans and never classifies.
- The worker receives one concrete refactor and implements it.

**One Step at a time, one Phase at a time.**
- Per Step: scan, dispatch, evaluate the worker's plan, Go, review the diff, recap, merge.
- One worker per coherent unit, never a bundle of unrelated refactors.
- Step N is merged before Step N+1 is scanned.
- Phase N is closed before Phase N+1 starts.

**Execution is autonomous up to Phase 4.**
- No user stop between Steps in Phases 1 to 3.
- One consolidated summary before Phase 4, per Step: what was found, what was refactored and merged.
- Phase 4 is iterated with the user.

**Thresholds are fixed.**
- No number below is softened to fit a project.
- Cosmetic LOC shrinking is never a split.

## Scope

**The user names the directory.**
- Ask for the source root or a chosen subtree before the first scan.

**Every scan root is an area directory, meaning `dev/<area>/`.**
- The area name matches its `process-docs/<area>/` folder exactly.
- A named subtree spanning several areas is scanned area by area.

## Phase 1 — Cohesion and Concern-Splitting

**File size.**
- Over 400 LOC is a split.

**Function size.**
- 50 LOC or more extracts a helper.
- 100 LOC or more is a hard target.

**Class state.**
- Ten or more distinct `self.<attr>` splits the class by concern.

**Constant clustering.**
- Top-level UPPER_CASE constants are grouped by leading `PREFIX_` token.
- A prefix with three or more constants is a cluster.
- Two or more clusters in one file split, one module per cluster.

**Re-pointing every reference belongs in the worker prompt.**
- The worker greps every reference to each moved symbol and confirms the new access path.
- Names deliberately left in place are listed in the recap.

## Phase 2 — Module Standards Conformance

**The worker code standard is read each run.**
- Main reads `shared-rules/worker/code-standards`, extracts the concrete standards, and checks every module.

**Docstrings and comments are violations.**
- Every module, class, and function docstring.
- Every comment line except the shebang and the three section markers.

**Main scans per file.**
- `ast.get_docstring` on the module node and on every `FunctionDef`, `AsyncFunctionDef`, `ClassDef`.
- Line walk for every line whose stripped form starts with `#`, minus the allowed set.

**Main triages every hit before dispatch.**
- Substance recorded nowhere else goes into a new dated `process-docs/<area>/` entry, one entry per module.
- A module's purpose, reads, writes, callers and calls-out go into the module's `DOCS.md` entry, within § DOCS.md Format.
- Everything else goes into the process-docs entry, including guards on calibrated values and grounding.
- Content already covered by process-docs or `DOCS.md` is deleted.

**The module's `DOCS.md` is rewritten to § DOCS.md Format in the same Step.**
- The existing entries of that directory are brought into the format alongside the relocated hits.
- Everything cut to reach the format goes verbatim into the same process-docs entry, under one `## Salvage from <path>` heading.
- A directory's `DOCS.md` ends the Step shorter than it started.

**The hit list with its triage target per hit belongs in the worker prompt.**
- The worker relocates and deletes, and decides nothing.
- After merge, Main re-scans the module. Zero hits closes the Step.

## Phase 3 — Doc Structure

### Step 1 — Placement

**Phase 2 is merged before the placement scan runs.**
- Every line count and every closure is measured on the post-rewrite state.

**A `DOCS.md` of 400 lines or more splits its directory into unit subfolders.**
- Under 400 lines the directory stays flat and the Phase closes with no finding.
- `__init__.py` is skipped.

**A unit is one entry script plus the modules reached only by that script's import closure.**
- An entry script is a module that no other module in the directory imports.
- Main computes every closure by AST walk over the directory's own imports.
- A module reached by two or more closures is shared.
- A module reached by no closure is reported as unowned, and the user decides it.

**The split.**
- A unit holding one or more exclusive modules moves into `<unit>/`, named after its entry script without the number prefix.
- A unit holding no exclusive module stays as a single file at the area root.
- Every shared module stays at the area root.
- The entry script keeps its number.

**Output directories stay at the area root and never move.**
- `md/`, `png/`, `csv/`, `data/` and `npz/` are the area's bus, read across units.

**Depth-dependent path resolution is removed before any move.**
- Every `parents[N]` walk on `__file__` is replaced by a resolution independent of the module's depth.
- Every output path is anchored at the area root, never at the module's own directory.

**Each new subfolder gets its own `DOCS.md` in the same Step.**
- The area `DOCS.md` keeps Role, Flow, the shared modules, the single-file units, and one line per subfolder.

### Step 2 — Doc-Drift Check

**Workers update the touched DOCS.md with their change.**

**One drift check closes the autonomous part.**
- After Step 1 is merged, `docs-drift-check` runs once in the cwd.
- Residual drift goes to a worker, then the consolidated summary goes to the user and Phase 4 begins.

**The drift findings, file by file, belong in the worker prompt.**

## Phase 4 — Control-Flow Integrity

**Scan only, then iterate with the user.**
- Main scans first, the worker scans second, both report findings and classify nothing.
- The combined list goes to the user; every step from there is decided with the user.

**The classifying question comes from the global testing rule.**
- A branch that produces derived output a second way is a fallback and is eliminated.
- A branch that refuses and surfaces the failure is a tripwire and stays.

**Three passes.**
- Textual: grep comments and names for `fallback`, `legacy path`, `old path`, `best-effort`, `backward-compat`, and function names containing `fallback`, `legacy`, `dedup`, `gated`.
- Structural: AST for `except` handlers that return a non-`None` value without re-raising.
- Cross-module, manual: one value or effect derived or read in two or more places that can diverge.

**The three passes and "classify nothing, fix nothing" belong in the worker prompt.**
