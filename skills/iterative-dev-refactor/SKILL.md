---
name: iterative-dev-refactor
description: Systematic codebase refactor scan in two parts — the architectural form of the whole project (placement, coupling, cohesion/splitting, control-flow, operational, structure), then per-module conformance against the worker coding rules. Runs phase by phase, findings then worker-refactor per phase. Opus analyzes, workers implement. NOT for on-the-fly code review (those checks fire through worker rules); this is the heavyweight session-level audit.
---

# Refactor Scan

Two parts. Part 1 audits the architectural form of the project as a whole — the form a worker cannot keep in view while coding a single module, checked only here after the code runs. Part 2 verifies each module against the worker coding rules — what the worker was supposed to follow while writing it. Opus does the analysis; workers refactor.

## Scope

Python codebases. Source root is the project's `src/` (or equivalent). Filter out runtime artifacts:
- `__pycache__/`
- `logs/` (projects that store live runtime copies there, e.g. Monitor_CC's `.proxy_live_*`)
- `.claude/worktrees/` (in-flight worker copies)
- `venv/`, `.venv/`, `node_modules/`

Every scan honors this SKIP scope. Opus writes each scan itself from the description below — AST walk, grep, or `wc` as fits. Keep the thresholds exact: they are the deterministic part that makes findings comparable across projects; only the way the scan is written adapts to the project. For non-Python codebases, use the equivalent parser.

## Workflow

Run the phases in order, one at a time. For each phase: run its scan, dispatch the refactor through workers (one worker per coherent unit — do not bundle unrelated refactors), and only once that phase's refactors are merged move to the next phase. Never scan all phases up front — Phase N's fixes land before Phase N+1 starts. Part 2 runs last, with the same rhythm.

**Run autonomously — report once at the end.** Do NOT stop for user remarks after each phase. Drive the whole scan end-to-end with the worker step by step (scan → dispatch → cross-model evaluate → Go → review → recap → merge → next phase), and surface ONE consolidated summary to the user at the very end: what each phase found and which refactors were implemented and merged. The single exception is a Phase 4 genuine-fallback finding routed to the One-Way Redesign Evaluation — that redesign is a scope decision worked through WITH the user, so it interrupts the autonomous run.

Before dispatching ANY worker, run the doc-drift gate (below). Opus does the analysis and the dispatch; workers refactor; Opus does not edit source code.

# Part 1 — Architectural Form

## Phase 1 — Placement

Is every module in the right place in the project structure?

**Root-module justification.** Standalone modules at `src/` root are only justified if used by ≥2 subdirectories OR they're entry points loaded externally (e.g. mitmproxy `-s`, workflow runner imports). For each top-level `src/*.py` (skip `__init__`), count how many distinct subdirectories import it and whether any external entry-point references it. ≥2 subdirs or an entry-point = JUSTIFIED. A single subdir with no entry-point = MOVE candidate into that subdir.

**Scripts in the library tree.** A source file with an `if __name__ == "__main__"` block AND whose own module name is imported by nobody is a script, not library code — it belongs in `scripts/`, `dev/`, or `bin/`. Build the set of module names imported anywhere in the tree, then flag any non-`__init__` `.py` that has a `__main__` block and is imported by no one.

## Phase 2 — Coupling

How tangled are the inter-module dependencies?

Per `.py`, count the distinct imported modules (collapse each import to its leading one-or-two path segments). Flag files importing more than 5; list the imported modules per flagged file. >5 cross-module imports = review dependencies.

## Phase 3 — Cohesion & Concern-Splitting

Does one place carry too much and want to split? These thresholds are skill-owned — a worker does not watch them while coding; they are caught here.

- **File size.** ≤400 LOC per file is the hard ceiling. Flag files over 400 (hard) and in the 300-400 band (watch). Report largest first.
- **Function size.** Flag functions ≥50 LOC (extract a helper); mark ≥100 LOC as hard refactor targets. Report longest first, with file and line.
- **Class state sprawl.** Per class, collect the distinct `self.<attr>` targets (plain and annotated). Flag classes with ≥10 instance attributes — split by concern.
- **Constant concern-clustering.** Per module, group top-level UPPER_CASE constants by their leading `PREFIX_` token. A prefix carrying ≥3 constants is a cluster; a file with ≥2 such clusters is a split candidate, each cluster a concern for its own module.

## Phase 4 — Control-Flow Integrity

A code path that, on missing input or failure, produces alternative output through a second method — a fallback — is a refactor target. Distinguish from a **tripwire/assertion** — a check that REFUSES to produce output and surfaces the failure (raise / flag / render-plain-with-marker). The tripwire is the cure, not a violation; the violation is the route that GUESSES an alternative output to keep going.

Per hit, the classifying question: does the flagged branch PRODUCE derived output by a second method (fallback → eliminate), or does it REFUSE and surface (tripwire → keep)? Manual review per hit — a cache-miss returning `None` is a tripwire, not a fallback.

Three passes:

**Pass 1 — Textual signatures:** grep the source for fallback markers in comments and names — `fallback`, `legacy path`, `old path`, `best-effort`, `backward-compat` — and function definitions whose name contains `fallback`, `legacy`, `dedup`, or `gated`.

**Pass 2 — Structural signature (AST):** find `try` handlers that return a non-`None` value without re-raising — an `except` that produces output instead of surfacing the failure.

**Pass 3 — Cross-module behavioral redundancy (manual — the AST pass does NOT catch this):** for each conceptual value or effect the system produces, map every code site that PRODUCES or READS it. ≥2 independent derivations of the same value/effect = candidate. Patterns:
- Two periodic threads/functions performing the same operation (e.g. two heartbeat loops bumping the same lock).
- One conceptual value read from two sources that can diverge (idle from two file mtimes; "is X running" from state-file vs port-scan vs process-scan).
- The same operation in two places with divergent behavior (one health probe retries, the other does not).
- A hardcoded fallback consulted when the canonical source is absent (a default port/path another process can occupy and masquerade as the real thing).

A sentinel branch feeding two derivations of one output (`if <key> in x: <new path> else: <old path>`) is not reliably AST-detectable; surface it here and during any "are there two ways to compute X" read.

**Verify at the source before classifying any Pass-3 candidate:**
- Read the actual code of BOTH paths; confirm they produce/derive the same value/effect.
- For external or library behavior the verdict depends on, read the vendored/external source for the categorical answer. Do NOT infer from training knowledge.
- Where cheap, confirm with a live probe (lsof, curl, a one-shot call).

This phase does NOT auto-produce a mechanical refactor. Route every hit to the One-Way Redesign Evaluation companion below.

## Phase 5 — Operational Form

Prototype-to-prod readiness at the project level.

**Ungated diagnostic writes.** In production paths (skip `tests/` and `dev/`), find `open(path, …)` calls in append/write mode whose path — literal or f-string — carries a diagnostic hint (`/tmp/`, `.log`, `debug`, `trace`, `diag`). Heuristic: verify each hit is actually ungated (no env-var, debug-flag, or log-level check up the call tree). Manual review per hit.

**Installation friction.** Find non-Python config files (plist, yaml, yml, toml, json, conf, ini) containing `<UPPER_CASE>` placeholder tokens, and flag any whose directory has no `setup_*.py` / `install_*.py`. Show the offending tokens.

**Scattered application state.** Count entries in `$HOME` matching `.<project-prefix>*` (prefix defaults to the lowercased project dir name). At ≥3, list them and recommend grouping under `~/.config/<project>/`.

## Phase 6 — Structure Mapping

Does the dev/ tree mirror the active source tree? For each `src/<module>/` with a git commit in the last 30 days, flag it if there is no `dev/<module>*` counterpart (script or subdir). Heuristic — not every module needs one.

# Part 2 — Module Standards Conformance

The worker coding rules — `code-organization`, `code-standards`, `dev-convention` (in `shared-rules/worker/`) — define how a single module is written. Opus does NOT get these rules in context; READ all three, extract the concrete standards, and check each module against them. This catches what the worker was supposed to do but did not.

Per module, verify against the standards the rules define, among them:
- **Section order** — INFRASTRUCTURE → ORCHESTRATOR → FUNCTIONS; exactly one orchestrator; every function reachable from it.
- **Comments** — only section markers, one-line function headers, and cross-module import comments; no inline comments.
- **Imports** — absolute style, cross-module imports carry the `# From <module>.py: …` comment, no stray relative imports.
- **Constants** — module-specific in the module, shared in the config module, no constant duplicated across files.
- **Immutability** — no function mutates its arguments.
- **Error handling** — no bare `except`, no `except Exception: pass`, no silent swallow of business-logic failures.
- **Naming & markers** — snake_case folders/modules, `__init__.py` present, one `DOCS.md` per domain.
- **Artifacts** — no test files in root, no git-tracked `debug/` or `logs/`, no emojis in production code/docs/logs.
- **dev/ reports** — report-producing scripts numbered, reports in `md/`/`csv/`/`png/` with the same number prefix, never console.

The rules are the source of truth — re-read them each run, since they change. Most standards are mechanical; a few need judgment (orchestrator "calls only", one-responsibility-per-function, console conciseness) — read the code and decide.

# Companions

## Doc-Drift Gate (MANDATORY, before every dispatch)

Before dispatching a phase's refactor workers, run `docs-drift-check` (cwd). Exit 0 = clean → dispatch. Exit 1 = drift → fix FIRST (separate worker), then dispatch. Full doc/structure verification lives in the `iterative-dev-doccheck` skill. Refactor workers update affected DOCS.md alongside the code change.

## Symbol-Relocation Reference Audit

When a refactor relocates WHERE a symbol lives — an attribute to a different owner, a function or constant to a different module, a name into a namespace — EVERY reference must be updated to the new access path. Import + entry-point smoke tests validate only the load path; references inside conditionally-executed code (event handlers, error branches, rarely-hit CLI flags, lazy imports) stay stale and fail only at runtime, and `docs-drift-check` does not catch a syntactically-valid stale access either.

The audit (worker runs post-implementation, before recap): for each relocated symbol, grep every reference across the affected tree and verify each resolves to the new path, not the old. Whitelist symbols deliberately left in place (name them so they are not false-flagged). Belongs in the refactor deliverables for any relocation, alongside the doc-drift gate.

## One-Way Redesign Evaluation (Phase 4 findings)

A silent-fallback finding cannot be auto-fixed by a worker. The fix is a redesign so a SINGLE deterministic route produces the output, correctness guaranteed structurally not guarded at runtime. Evaluated WITH the user.

**First classify:**
- **Fallback** (eliminate): primary route fails / input missing → produce alternative output by a second method.
- **Tripwire / assertion** (keep, shaped right): check a property; on violation REFUSE to produce output and surface it. Never a second derivation.

**One-way redesign — work through with the user:**
1. **Record once at the source.** Capture the data at the point of truth with enough information — position, identity, order — that a single deterministic path produces the output later, no re-derivation downstream.
2. **Completeness is a CODE property, not an INPUT property.** Operations happen at a finite, enumerable set of code sites; completeness is VERIFIED across those sites, not hoped for at runtime.
3. **Move the safety check from runtime to test.** Replace the runtime fallback with a test-time invariant — `source + recorded operations == produced output` — asserted over a real corpus and kept as a CI regression test. A failure there = a code site that forgot to record = fix the site.
4. **Production runs one way.** One deterministic route, no fallback, no dedup-patch, no "best-effort". Any retained tripwire refuses-and-surfaces; it never guesses.

**Validate in `dev/` before touching `src/`.** Build the redesign as a `dev/` probe, prove exact equivalence on real data across ALL operation types, THEN port to `src/` and delete the fallback chain. Do not modify `src/` during the exploration.

**Anti-pattern — the self-defeating hedge:** proving the one-way path in `dev/` and then STILL shipping a runtime fallback "just in case". After a passing `dev/` proof with the invariant in CI, production needs no fallback — at most a refuse-and-surface tripwire for genuinely-novel input.

## Output Format

One consolidated summary at the END of the run — not per phase. Opus runs each phase's scan, dispatches, reviews, and merges autonomously, and only at the very end presents the user a single prose summary: per phase what was found, and which refactors were implemented and merged. No file is written. For ad-hoc invocations (one phase or one dimension only), present that single finding and skip the rest.

## Anti-Patterns

- Scanning all phases up front instead of findings-then-refactor, one phase at a time
- Stopping to ask the user after each phase — the run is autonomous with one end-of-run summary (except a Phase 4 fallback redesign, which is worked through with the user)
- Softening a threshold to fit a project — the numbers are fixed; only the way the scan is written adapts
- Cosmetic LOC shrinking (trim blanks, merge comments) treated as a split — never counts
- Mixing rule-violations with personal style preferences — this skill audits against codified rules only
- Refactoring without a worker — Opus reviews findings, workers implement
- Bundling unrelated refactors in one worker
- Removing a silent fallback by hand without the one-way redesign + dev/ proof
- Shipping a runtime fallback "just in case" after a passing dev/ proof
