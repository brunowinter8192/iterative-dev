# 2026-09-25 - docs-drift-check report without the Summary section

Owner decision: "Summary kann erstmal raus, das braucht keiner." Removed the `## Summary` block (heading plus four lines Path-Drift / LOC-Drift / Rule-Violation / Total) from `print_report` in `src/docs_drift_check/report.py`. Exit code, section order and the per-check headings `## <Check> (N findings)` are unchanged; the counts live in those headings now.

## Consumers checked

Grep over iterative-dev, monitor-cc and `~/.claude` (code, DOCS.md, process-docs, json) for `Path-Drift:`, `LOC-Drift:`, `Rule-Violation:`: only hits were `report.py` and `dev/docs_drift_check/test_docs_drift_check.py`. No script parses `Total:` or the Summary heading. The refactor skill only says to run the tool and write the remaining drift to a file. Session history of agents that read the old output was not searched.

## Report shape

Before: title, `Project root:`, `## Summary` with four lines, three sections.
After: title, `Project root:`, `## Path-Drift (N findings)`, `## LOC-Drift (N findings)`, `## Rule-Violation (N findings)`.

## Tests

The suite asserted on the summary lines (`Total:          0`, `Path-Drift:     0 findings`, `Rule-Violation: 0 findings`). Replaced by the section headings: clean cases assert all three `(0 findings)` headings; finding cases assert the exact heading count (e.g. `## LOC-Drift (1 findings)`, `## Rule-Violation (2 findings)`). Every case lists `## Summary` in `absent`. 16/16 passed with `CLAUDE_PLUGIN_ROOT` at the worktree (the wrapper otherwise runs the cached copy).

Pitfall hit while editing: a blanket string replace of the old `Path-Drift:     0 findings` line produced a duplicate heading entry in one case; harmless but remove it.
