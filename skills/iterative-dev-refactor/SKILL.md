---
name: iterative-dev-refactor
description:
---

# Refactor Scan

## Core Rules

**Opus scans, workers fix.**
- Opus runs every scan and every classification itself, by AST walk, grep, or `wc`.
- The worker never scans and never classifies.
- The worker receives one concrete refactor and implements it.

**One Step at a time, one Phase at a time.**
- Per Step: scan, dispatch, evaluate the worker's plan, Go, review the diff, recap, merge.
- One worker per coherent unit, never a bundle of unrelated refactors.
- Step N is merged before Step N+1 is scanned.
- Phase N is closed before Phase N+1 starts; its worker prompt template is the one at the end of that Phase.

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

## Phase 1 — Architectural Form

### Step 1 — Placement

**A root-level module stays at the root only with a justification.**
- Justification is import by two or more subdirectories, or load by an external entry point.
- A module imported by a single subdirectory without an entry point moves into that subdirectory.
- `__init__.py` is skipped.

### Step 2 — Cohesion and Concern-Splitting

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

### Worker Prompt — Phase 1

```markdown
You are a WORKER.

Your worktree is `<project>/.claude/worktrees/<name>/`. Read, edit, test, and commit here.

## Task
<one refactor, abstractly: what is split, moved, or eliminated, and the desired end state>

## Files
<the modules involved, plus the DOCS.md of their directory; read every one completely>

## Scope
Do NOT add features or improvements beyond this refactor. Do NOT touch other modules except to re-point references.

## Completion Checklist
- Every reference to each moved symbol re-pointed; names deliberately left in place listed.
- Existing tests pass; one real invocation per affected entry point before/after identical.
- Touched DOCS.md updated, LOC per touched module.
```

## Phase 2 — Module Standards Conformance

**The worker code standard is read each run.**
- Opus reads `shared-rules/worker/code-standards`, extracts the concrete standards, and checks every module.
- A deviating module gets a worker.

**Docstrings and comments are violations.**
- Every module, class, and function docstring.
- Every comment line except the shebang and the three section markers.

**Opus scans per file.**
- `ast.get_docstring` on the module node and on every `FunctionDef`, `AsyncFunctionDef`, `ClassDef`.
- Line walk for every line whose stripped form starts with `#`, minus the allowed set.
- Files sorted by violation lines, largest first, is the dispatch order.

**Opus triages every hit before dispatch.**
- Substance recorded nowhere else goes into a new dated `process-docs/<area>/` entry, one entry per module.
- A guard on a calibrated value goes into the module's `DOCS.md` Gotchas.
- A module's purpose, reads, writes, callers, and grounding entry go into the module's `DOCS.md` entry.
- Content already covered by process-docs or `DOCS.md` is deleted.

**The worker relocates and deletes, and decides nothing.**
- The worker receives one module's hit list with the triage target per hit.
- After merge, Opus re-scans the module. Zero hits closes the Step.

### Worker Prompt — Phase 2

```markdown
You are a WORKER.

Your worktree is `<project>/.claude/worktrees/<name>/`. Read, edit, test, and commit here.

## Task
Bring `<module>` to the worker code standard: relocate or delete every listed hit. Decide nothing; the triage target per hit is given.

## Hits
<line: text → target>  (target is one of: process-docs/<area>/<entry>.md, DOCS.md Gotchas, DOCS.md module entry, delete)

## Scope
Do NOT change behavior. Do NOT touch lines not in the list.

## Completion Checklist
- Zero docstrings and zero comment lines outside the allowed set in `<module>`.
- Each relocated hit present at its target, quoted.
- Tests pass; module compiles.
```

## Phase 3 — Doc-Drift Check

**Workers update the touched DOCS.md with their change.**

**One drift check closes the autonomous part.**
- After the last Phase 2 merge, `docs-drift-check` runs once in the cwd.
- Residual drift goes to a worker, then the consolidated summary goes to the user and Phase 4 begins.

### Worker Prompt — Phase 3

```markdown
You are a WORKER.

Your worktree is `<project>/.claude/worktrees/<name>/`. Read, edit, test, and commit here.

## Task
Close the residual doc drift listed below in the named DOCS.md files.

## Drift
<file: finding>

## Scope
Do NOT edit source code. Do NOT rewrite sections not named.

## Completion Checklist
- Every listed finding resolved, quoted.
- LOC per module heading matches `wc -l`.
```

## Phase 4 — Control-Flow Integrity

**Scan only, then iterate with the user.**
- Opus scans first, the worker scans second, both report findings and classify nothing.
- The combined list goes to the user; every step from there is decided with the user.

**The classifying question comes from the global testing rule.**
- A branch that produces derived output a second way is a fallback and is eliminated.
- A branch that refuses and surfaces the failure is a tripwire and stays.

**Three passes.**
- Textual: grep comments and names for `fallback`, `legacy path`, `old path`, `best-effort`, `backward-compat`, and function names containing `fallback`, `legacy`, `dedup`, `gated`.
- Structural: AST for `except` handlers that return a non-`None` value without re-raising.
- Cross-module, manual: one value or effect derived or read in two or more places that can diverge.

### Worker Prompt — Phase 4

```markdown
You are a WORKER.

Your worktree is `<project>/.claude/worktrees/<name>/`. Read here; do not edit.

## Task
Scan `<source root>` for control-flow findings and report them. Classify nothing, fix nothing.

## Passes
- Textual: `fallback`, `legacy path`, `old path`, `best-effort`, `backward-compat`; function names containing `fallback`, `legacy`, `dedup`, `gated`.
- Structural: `except` handlers returning a non-`None` value without re-raising.
- Cross-module: one value or effect derived or read in two or more places.

## Files
<the modules in scope; read every one completely>

## Completion Checklist
- One line per finding: file, line, the two paths or the handler, quoted.
- Findings already listed in the attached Opus scan marked as confirmed.
```
