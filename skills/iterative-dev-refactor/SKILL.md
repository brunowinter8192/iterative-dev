---
name: iterative-dev-refactor
description:
---

# Refactor Scan

**Opus checks, workers only fix.** Opus runs every scan and classification itself — AST walk, grep, or `wc`, whichever fits — and decides what changes. The worker NEVER checks or scans; it receives ONE concrete refactor and implements it. (This is the difference from the doc-check skill, where the worker re-runs the audit — here it does not.)

**One Step at a time.** Per Step: run its scan → dispatch the fix through workers (one worker per coherent unit, never bundle unrelated refactors) → evaluate the worker's plan against your own model → Go → review the diff → recap → merge. Step N's fix is merged before Step N+1 starts. Never scan ahead.

**Run autonomously — report once.** No user stop between Steps; drive the run end-to-end and give ONE consolidated prose summary at the very end (per Step: what was found, what was refactored + merged). Every report is written in German; all artifacts (code, DOCS.md) stay English.

**Thresholds are fixed.** The numbers below are exact — never soften one to fit a project; only the way you write the scan adapts. Cosmetic LOC shrinking (trimming blanks, merging comments) is never a split.

## Scope

ASK the user which directory to refactor (the source root — `src/` or a chosen subtree).

## Phase 1 — Architectural Form

### Step 1 — Placement

Is every top-level module in the right place? A `src/*.py` at the root (skip `__init__`) is justified only if ≥2 subdirectories import it OR an external entry-point loads it (`python -m x`, a uvicorn `x:app` path, `mitmproxy -s`). Imported by a single subdir with no entry-point → move it into that subdir.

### Step 2 — Cohesion & Concern-Splitting

Does one place carry too much and want to split?

- **File size.** >400 LOC = hard (split); 300–400 = watch. Largest first.
- **Function size.** ≥50 LOC = extract a helper; ≥100 = hard target. Longest first, with file:line.
- **Class state.** ≥10 distinct `self.<attr>` (plain + annotated) → split by concern.
- **Constant clustering.** Per module, group top-level UPPER_CASE constants by leading `PREFIX_` token; a prefix with ≥3 constants is a cluster; ≥2 clusters in one file → split, each cluster its own module.

### Step 3 — Control-Flow Integrity

A branch that, on missing input or failure, PRODUCES alternative output by a second method is a **fallback** → eliminate. A branch that REFUSES to produce output and surfaces the failure (raise / flag / render-plain-with-marker) is a **tripwire** → keep, it is the cure. The classifying question per hit: does it produce derived output a second way (fallback), or refuse and surface (tripwire)? A cache-miss returning `None` is a tripwire, not a fallback.

Three passes:

- **Pass 1 — Textual:** grep comments and names for `fallback`, `legacy path`, `old path`, `best-effort`, `backward-compat`, and function names containing `fallback` / `legacy` / `dedup` / `gated`.
- **Pass 2 — Structural (AST):** `except` handlers that return a non-`None` value without re-raising — an `except` that produces output instead of surfacing failure.
- **Pass 3 — Cross-module (manual — the AST pass misses this):** one conceptual value or effect derived/read in ≥2 places that can diverge. Patterns: two periodic loops doing the same op; one value read from two sources (idle from two mtimes; "is X running" from state-file vs port-scan vs process-scan); the same op in two places with divergent behavior; a hardcoded default consulted when the canonical source is absent; a sentinel `if <key> in x: <new> else: <old>`.

**Verify at the source before classifying:** read BOTH paths and confirm they derive the same value; for external/library behavior read the vendored source for the categorical answer (never infer from training knowledge); where cheap, confirm with a live probe (lsof, curl, one-shot call).

Do NOT auto-fix. Route every genuine fallback to the One-Way Redesign Evaluation (below).

### Step 4 — Operational Form

Prototype-to-prod readiness at the project level.

- **Ungated diagnostic writes.** In production paths (skip `tests/`, `dev/`), `open(path, …)` in write/append mode whose path (literal or f-string) hints diagnostic — `/tmp/`, `.log`, `debug`, `trace`, `diag` — and is NOT gated by an env-var / debug-flag / log-level check up the call tree. Manual per hit.
- **Installation friction.** Non-Python config (plist, yaml, yml, toml, json, conf, ini) carrying `<UPPER_CASE>` placeholder tokens in a directory with no `setup_*.py` / `install_*.py`. Show the tokens.
- **Scattered application state.** ≥3 entries in `$HOME` matching `.<project-prefix>*` (prefix = lowercased project dir name) → list them, recommend grouping under `~/.config/<project>/`.

## Phase 2 — Module Standards Conformance

The worker coding rules (`shared-rules/worker/`: `code-organization`, `code-standards`, `dev-convention`) define how a single module is written. Opus does NOT get these rules in context — READ all three each run (they change), extract the concrete standards, and check every module against them. This catches what the worker was supposed to do but did not. Among the standards:

- **Section order** — INFRASTRUCTURE → ORCHESTRATOR → FUNCTIONS; exactly one orchestrator; every function reachable from it.
- **Comments** — only section markers, one-line function headers, cross-module import comments; NO inline comments.
- **Imports** — absolute style; cross-module imports carry `# From <module>.py: …`; no stray relative imports (flag only when the project is absolute-consistent).
- **Constants** — module-specific in the module, shared in the config module, none duplicated across files.
- **Immutability** — no function mutates its arguments.
- **Error handling** — no bare `except`, no `except Exception: pass`, no silent swallow of business-logic failures.
- **Naming & markers** — snake_case folders/modules, `__init__.py` present.
- **Artifacts** — no test files in root, no git-tracked `debug/` or `logs/`, no emojis in production code/docs/logs.

Most standards are mechanical; a few need judgment (orchestrator "calls only", one-responsibility-per-function, console conciseness) — read the code and decide.

## Doc-Drift Check (final step)

Refactor workers update the touched DOCS.md alongside their code change as they go. At the very END — after every Step's fix is merged — run `docs-drift-check` (cwd) ONCE. Clean → done. Residual drift → fix it (worker), then done.

## Companions

### One-Way Redesign Evaluation (Phase 1 Step 3 fallbacks)

A silent fallback cannot be auto-fixed by a worker. The fix is a redesign so a SINGLE deterministic route produces the output — correctness guaranteed structurally, not guarded at runtime. Worked through WITH the user.

1. **Record once at the source.** Capture the data at the point of truth with enough information (position, identity, order) that a single deterministic path produces the output later — no re-derivation downstream.
2. **Completeness is a CODE property, not an INPUT property.** Operations happen at a finite, enumerable set of code sites; completeness is verified across those sites, not hoped for at runtime.
3. **Move the safety check from runtime to test.** Replace the runtime fallback with a test-time invariant — `source + recorded operations == produced output` — asserted over a real corpus and kept as a CI regression. A failure there = a code site that forgot to record → fix the site.
4. **Production runs one way.** One deterministic route — no fallback, no dedup-patch, no "best-effort". Any retained tripwire refuses-and-surfaces; it never guesses.

**Validate in `dev/` before touching `src/`.** Build the redesign as a `dev/` probe, prove exact equivalence on real data across ALL cases, THEN port to `src/` and delete the fallback chain. Never ship a runtime fallback "just in case" after a passing `dev/` proof — at most a refuse-and-surface tripwire for genuinely-novel input.

### Symbol-Relocation Reference Audit

When a refactor moves WHERE a symbol lives — an attribute to a different owner, a function or constant to a different module, a name into a namespace — EVERY reference must move to the new access path. Import + entry-point smoke tests validate only the load path; references in conditionally-executed code (event handlers, error branches, rare CLI flags, lazy imports) stay stale and fail only at runtime, and `docs-drift-check` does not catch a syntactically-valid stale access. The worker (post-implementation, before recap) greps every reference to each relocated symbol and confirms it resolves to the new path; whitelist names deliberately left in place so they are not false-flagged.

## Anti-Patterns

- Scanning all Steps up front instead of scan-then-fix, one at a time
- Stopping for the user between Steps — the run is autonomous with one end-of-run summary (except a Phase 1 Step 3 fallback redesign)
- Softening a threshold to fit a project
- Cosmetic LOC shrinking treated as a split
- A worker checking or scanning anything — the worker only implements Opus's dispatched fix
- Refactoring without a worker, or bundling unrelated refactors in one worker
- Removing a silent fallback by hand without the one-way redesign + `dev/` proof
