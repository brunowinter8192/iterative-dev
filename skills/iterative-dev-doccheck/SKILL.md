---
name: iterative-dev-doccheck
description:
---

# Doc & Structure Check

**Subject.** A project's documentation surface: `process-docs/**`, every `DOCS.md`, `dev/` reports, `skills/*/SKILL.md`. The skill systematically verifies this surface complies with the rules defined in § Documentation Hierarchy.

**Reference.** § Documentation Hierarchy is THE standard — the sole source of what correct docs + structure look like, and it wins over the project's current state. NEVER accept an existing structure as a "project convention" that excuses a deviation — "it's consistent everywhere" is not a defense; a consistent deviation is still a deviation. Diverges from a rule → flag it, bring it into line; a deviation stays only on an explicit user decision, never on your own "it already works". The Workflow below adds no rules of its own; its Steps and Stages only fix the ORDER of what to check, mirroring the split of § Documentation Hierarchy. Work Step by Step: read/grep across all a Step's Stages, then fix at the end of the Step — one fix pass per Step, not per Stage. Run the whole audit through without pausing: apply the fixes and move on, NEVER stop to ask per finding — the size of a fix, or that it is not purely mechanical, is no reason to pause; a fix that follows from the rules gets applied in full, however substantial the reshaping. A fix that triggers a second violation is not a dilemma to report — resolve that one too in the same pass, the rules compose to a fully compliant surface. Report ONCE, at the very end (Step 5 — Hand off). "A deviation stays only on an explicit user decision" governs KEEPING a deviation, not fixing one — fixing is the default and needs no confirmation. Exception: Step 4 (skills) is flag-only — collect the findings there, never fix.

**Report language: German.** Every report is written in German. This governs the chat surface only; all ARTIFACTS (process-docs, DOCS.md, code) stay English per § Documentation Hierarchy, regardless of the German chat.

## Workflow

### Step 1 — process-docs

Touch ONLY process-docs in this Step — NEVER migrate its content into a `DOCS.md` or any other surface. process-docs are write-once, potentially-stale snapshots; `DOCS.md` is maintained from the CODE, not copied from process-docs prose. "In process-docs but not in DOCS.md" is NOT a portable gap. A present-tense "current state" entry (§ process docs violation) is fixed within process-docs and needs no code — it is binary: reframe it as a dated snapshot in its thematic area folder, or delete it if it holds no historical value. process-docs MAY be historical, so its currency is irrelevant here.

#### Stage 1 — structure

Check § process docs (Root-anchored, one fixed name).

#### Stage 2 — invariants

Check § No Issue References and § process docs (no present-tense current/production claims, dense/dated/thematic, no cross-references to another process-docs entry, evidence inline).

#### Stage 3 — language

Check § Language across every `process-docs/` entry.

### Step 2 — dev

Check § dev reports. Beyond the rule, apply on invocation:

- A maintenance/utility script (reclean, one-shot fixer) goes in its thematic `dev/<area>/` — no exempt catch-all folder. A loose `.md` in `dev/` that **no script produces** (a hand-written run summary / analysis) is NOT a dev report → it belongs in `process-docs/` if still relevant, or is deleted if stale.
- Assign each dev folder to its area (determine the fit from its `DOCS.md` / module docstring / contents). Belongs to ONE area → rename the folder to that area name. Contents spanning MULTIPLE areas is the real fix and the hard one → split the folder, routing each part into its own `dev/<area>/`.
- **Report vs DATA** — distinguish by content: a report is a readable analysis (a JSON *analysis* output counts → `md/`); data is the run's raw payload (scraped corpora, raw dumps, cached job data).
- **Cumulative logs stay.** An append-only log tracked + compared across runs (institutional history, not a single-run analysis) is NOT a report → leave in place.
- **Sub-suite own `md/`.** A self-contained sub-eval folder (`garbage_eval/`, `browser_eval/`) gets its OWN `md/`, not the parent area's.

### Step 3 — DOCS

Use heredoc / `/tmp` scripts — do not read every `DOCS.md` by hand.

#### Stage 1 — placement

Check § docs (Placement). Beyond the rule: **Root files** — `README.md` → flag for removal; a root `DOCS.md` that is a project overview → flag for removal; a root `CLAUDE.md` documenting project-only interactive working areas → allowed, do not flag.

#### Stage 2 — format

Check § docs (DOCS.md Format). Beyond the rule: **References resolve** — every file a `DOCS.md` names exists on disk.

#### Stage 3 — language

Check § Language across every `DOCS.md`.

### Step 4 — skills (flag-only)

Check § Artifact Density against each `skills/*/SKILL.md`. Beyond the rule:

`skills/*/SKILL.md` = procedure, not essay: WHAT (capability + output) and HOW (steps, commands, thresholds, formats, rules incl. "do NOT X"), never WHY.

**Frontmatter.** `description:` is present but empty — flag any non-empty `description` and blank it.

Removability test per clause: reader still executes exactly the same without it? Yes → WHY → cut. A concrete example stays only when it shows HOW to decide.

Flag WHY-content by signature:

| Signature | Example | Action |
|---|---|---|
| Justification clause | "raw and maximal — content not captured is gone for good" | cut clause, keep instruction |
| Cause / mechanism | "the plugin cache has NO venv, so a plugin-relative path fails" | cut |
| Rationale section | a "Why X matters" section | delete section |
| Historical / evidence note | "(verified on 278 files)", "previous runs failed here" | cut |
| Illustrative "what happens otherwise" | "the same anchor just returns the same top sources" | cut |
| `because` / `so that` / `in order to` / `which means` | any clause led by these | cut clause |

Keep — never flag: commands, paths, thresholds, output formats, parameter tables, ordering rules, prohibitions, behavior facts the procedure depends on, decision-examples.

### Step 5 — Hand off

Report your findings. Then, if you are Opus: commit your doc fixes, sync them to RAG (`rag-cli update_docs`), and spawn a worker to activate this skill (`iterative-dev-doccheck`) — it re-runs the audit on the committed state and applies the flagged source fixes (source edits are worker-only). Hand the worker, in its prompt, every source fix you already established — concrete file, location, and change — so it carries them through for certain instead of leaving them to re-discovery. If you are a worker, you're done — no spawn.
