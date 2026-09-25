# Refactor skill: Phase 2 scans module structure and imports (2026-09-25)

Orchestrator entry. Edit to `skills/iterative-dev-refactor/SKILL.md`, commit `88f6e54` on integration. The owner approved the placement in the chat and reviews the wording himself afterwards.

## Why

In the four-repo refactor run of 2026-09-24/25 every violation of § Modulaufbau and § Import-Konvention surfaced only in Phase 6 (four-eyes review): several orchestrators per module (rag-cli retriever had five), logic inside orchestrators, relative imports in all of rag-cli `src/rag`, missing section markers in every shell module of iterative-dev, wrong stepdown order. Phases 1-5 never scanned for that class. The area's earlier entry recorded this as a hypothesis.

## What changed

- Phase 2 header now names § Kommentare und Docstrings, § Modulaufbau and § Import-Konvention, plus one guardrail line (Functional Core, Imperative Shell, Stepdown Rule).
- New Step 3 "Scan nach Modulaufbau und Imports": scan against § Modulaufbau, § Import-Konvention and § Abhängigkeiten zwischen Modulen. One example finding: an orchestrator that computes or filters instead of only calling functions.
- New Step 4 "Dispatch nach Modulaufbau und Imports", same shape as every other dispatch step (findings file in tmp/, path plus prompt to one or more workers, parallel where possible).

## Decisions

- Placed in Phase 2, not as a new phase. Phase 2 was already titled "Konformität mit den Modul-Standards" while covering only comments. A new phase would have shifted all phase numbers and the "Phase 1 bis 5" reference in Phase 6.
- Phase 6 text is unchanged; its worker runs the scan steps of Phases 1-5 and therefore now also runs the new Step 3.
- § Abhängigkeiten zwischen Modulen was added to the scan although the issue named only Modulaufbau and Import-Konvention: the Phase 6 findings of 2026-09-25 included duplicated helpers across modules, which that section governs.

## Open

- Not yet exercised on a real repo. Whether it moves most Phase 6 findings earlier is still a hypothesis until the next refactor run.
- Skill edits reach new sessions only after `plugin-publish`.
