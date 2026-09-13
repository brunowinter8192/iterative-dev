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

### Step 1 — Scan

**Main scans every module against the two size thresholds.**
- File size: over 400 LOC is a split.
- Function size: 50 LOC or more extracts a helper, and 100 LOC or more is a hard target.

### Step 2 — Dispatch

**The worker splits along the concerns it finds, and Main names no target modules.**
- After merge, Main re-scans. Zero hits closes the Phase.

## Phase 2 — Module Standards Conformance

### Step 1 — Read the standard

**The worker code standard is read each run.**
- Main reads `shared-rules/worker/code-standards`, extracts the concrete standards, and checks every module.

### Step 2 — Scan

**Main scans per file, and every docstring and every comment is a violation.**
- `ast.get_docstring` on the module node and on every `FunctionDef`, `AsyncFunctionDef`, `ClassDef`.
- `tokenize.COMMENT` for every comment token, minus the shebang and the three section markers.
   - A `#` inside a string literal is not a comment, and a raw line-prefix test reports it as one.

### Step 3 — Triage

**Main checks every hit against process-docs and `DOCS.md`.**
- A hit already covered there is deleted.
- Every other hit is relocated into the author's own dated `process-docs/<area>/` file, then deleted.

### Step 4 — Dispatch

**The worker relocates and deletes, and decides nothing.**
- The prompt also carries the directory's `DOCS.md` rewrite to § DOCS.md Format, in the same run.
   - Everything cut to reach the format goes verbatim into the same process-docs file, under one `## Salvage from <path>` heading.
- After merge, Main re-scans the directory. Zero hits closes the Phase.

## Phase 3 — Doc Structure

### Step 1 — Check

**Phase 2 is merged before the check runs, and is merged now if it is not.**

**Every `DOCS.md` in scope is checked against the 400-line threshold.**
- 400 lines or more splits its directory into unit subfolders.
- Under 400 lines the directory stays flat.

**A unit is one entry script plus the modules reached only by that script's import closure.**
- An entry script is a module that no other module in the directory imports.
- A module reached by two or more closures is shared.
- A module reached by no closure is unowned, and the user decides it.
- `__init__.py` is skipped.

### Step 2 — Plan

**Main plans the split before any file moves.**
- A unit holding one or more exclusive modules moves into `<unit>/`, named after its entry script without the number prefix.
- A unit holding no exclusive module stays as a single file at the area root, and so does every shared module.
- The entry script keeps its number.

**Output directories stay at the area root and never move.**
- `md/`, `png/`, `csv/`, `data/` and `npz/` are the area's bus, read across units.

**Depth-dependent path resolution is removed before any move.**
- Every `parents[N]` walk on `__file__` is replaced by a resolution independent of the module's depth.
- Every output path is anchored at the area root, never at the module's own directory.

**Every new subfolder gets its own `DOCS.md`.**
- The area `DOCS.md` keeps Role, Flow, the shared modules, the single-file units, and one line per subfolder.

### Step 3 — Dispatch

**The worker executes the plan.**
- After merge, Main re-checks. Every `DOCS.md` under 400 lines closes the Step.

### Step 4 — Doc-Drift Check

**Workers update the touched DOCS.md with their change.**

**One drift check closes the autonomous part.**
- After Step 3 is merged, `docs-drift-check` runs once in the cwd.
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
