# Skill maintenance: doccheck in German, rule references instead of copies (2026-09-24)

New area. Covers edits to `skills/iterative-dev-doccheck/SKILL.md` and `skills/iterative-dev-refactor/SKILL.md` made by the orchestrator on the user's instruction. The user edits the refactor skill himself in parallel and reviews both skills in full afterwards; the state of the refactor skill after 2026-09-24 is his.

## Reference convention (user instruction, verbatim intent)

When a skill points at a rule instead of repeating it:

- A heading is referenced as `§ <heading text>`, e.g. `§ Aufbau von Tests`.
- A bold core statement under a heading is referenced as `§ <heading text> (**<bold statement>**)`, e.g. `§ Konvention für das dev/-Verzeichnis (**In welchem dev/-Ordner du arbeitest richtet sich ausschließlich nach der Area, in der sich die Session bewegt.**)`.

## What was changed

- Doccheck translated from English to German in the style of the rules (bold core statement, plain bullets).
  - While translating, rule references were corrected to the current headings: `§ Dokumentationshierarchie`, `§ process-docs`, `§ DOCS.md`, `§ Konvention für das dev/-Verzeichnis`, `§ Issues`. The pointer to the refactor skill named an old phase; it now names `§ Phase 4 — Struktur der Doku` of iterative-dev-refactor.
- Duplications of global rules replaced by references in the convention above:
  - doccheck Phase 2: the dev folder naming rule and the "loose .md belongs in process-docs" rule repeated `shared-rules/global/dev-convention.md` almost verbatim. Only the remedy (rename/fold, move/delete) stays in the skill.
  - refactor Phase 3: the hit list repeated `shared-rules/global/testing.md`, § Aufbau von Tests, in inverted form. It is now three references to its bold statements plus one example of a typical finding.
- Refactor got a core rule "Main findet, ein Worker behebt, ein frischer Worker prüft gegen" and every phase ended with a cross-check by a freshly spawned worker. The user's own rework of the skill later removed that core rule again; whether the cross-check comes back is his decision.

## Open, observed 2026-09-24

- Doccheck Phase 4 checks skills "against every block of § Artifact Density". No section of that name exists in `~/.claude/shared-rules`. The user said the skills are not to be touched further in that session, so the dangling reference stayed.
- The duallog skill has no counterpart in the global rules at all.
- Plugin cache: skill edits reach new sessions only after `plugin-publish`.
