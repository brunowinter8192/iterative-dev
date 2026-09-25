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

## Incident: padded LOC in headings went unchecked (2026-09-25)

Observed: after the change, the two DOCS.md headings were written as `### report.py (      27 LOC)` and `### test_docs_drift_check.py (     225 LOC)`. Cause: the LOC came from `wc -l < file` captured in a shell variable and substituted by `sed`; macOS `wc -l` pads its number with spaces. `docs-drift-check` reported 0 findings anyway, because its heading pattern requires a digit directly after the opening parenthesis; a heading that does not match is silently skipped, not reported. Caught in review, not by the tool.

Fix: headings rewritten to `(27 LOC)` and `(225 LOC)`; tool unchanged by decision. Rule for a successor: strip the padding when writing a LOC into a heading (`$(wc -l < f | tr -d ' ')`), and do not read "0 findings" as proof that every module heading was compared. The same pitfall was already recorded in the earlier docs_drift_check entry (macOS padding) and was repeated here.

# Rule-aligned rewrite: every check maps to a DOCS.md rule (2026-09-25)

Owner goal: the tool corresponds 1:1 to the DOCS.md rules of the shared documentation rules (section "## DOCS.md" incl. the format template). Every report section is named after the rule it checks; the old `Path-Drift / LOC-Drift / Rule-Violation` sections are gone.

## Rule -> check

| Section title (starts with "Rule:") | Module | What it checks |
|---|---|---|
| module heading `### <file> (<N> LOC)` | `check_modules.py` | Every `###` heading under `## Modules` matches the pattern exactly (bare file name, single spaces), names a file next to the DOCS.md, and N equals `wc -l` (newline bytes). A non-matching heading is a finding, not skipped. |
| one DOCS.md per module directory | `check_directories.py` | A DOCS.md needs at least one module heading resolving to a file in its own directory; every directory holding `.py` or `.sh` files (dev/ included) needs a DOCS.md. |
| title `# <dir>/` | `check_template.py` | First `# ` line equals the directory relative to the project root plus `/` (`./` for the root). |
| no function-level references | `check_rules.py` | `name(` and `module.function` tokens for functions defined in project sources. |
| no constant references | `check_rules.py` | ALL_CAPS tokens defined as constants in project sources, except names read as environment variables (Python `environ`/`getenv` access, shell `export NAME`, `${NAME:-...}`) and a metavar directly after `--flag`. |
| word limits | `check_template.py` | Role at most 50 words, each Purpose at most 25 words (tokens without a letter or digit, like a dash, do not count). |
| Called by | `check_called_by.py` | Field must not be empty; each backticked path-like entry (contains `/` or a file extension) must exist, resolved by path suffix anywhere in the project. Entries starting with `~/` or `/`, containing `<`, or carrying a cross-project marker are skipped. |
| no references to issues | `check_issues.py` | `#<digits>` or `/issues/<digits>` in a DOCS.md line. |

Fenced code blocks are never scanned. Scope exclusions (worktrees, logs, dist, build, venvs) are scanning scope, not rules.

## Decisions

- Removed: the generic path-existence check (no rule backed it; it skipped bare names like `spawn.py`) with all its skip heuristics, and the relative-subpath module headings. `check_paths.py` and `check_loc.py` are deleted; `check_modules.py` replaces the LOC check.
- Row "Flow 3-5 lines" left out: physical line count depends on wrapping. The English-language check was left out: not reliably mechanical. "Called by" is only required to be non-empty (a text like "Run manually" is accepted); DEAD CODE is not verified.
- Unknown command-line arguments now abort with exit 2 (before: a path argument was silently ignored, the tool always uses `$PWD`).
- A module directory is any directory with `.py` or `.sh` files, `dev/` included.
- Environment-variable exception: derived from the sources, not from the doc text. Observed: `MONITOR_CC_ROOT` in monitor-cc `dev/refactoring/DOCS.md:67` was flagged before; it is read via `os.environ.get` in Python sources and is no longer flagged.

## Tests

`dev/docs_drift_check/test_docs_drift_check.py`, 26 cases in parallel, each in its own temp project: at least one per check (LOC mismatch, missing module file, padded heading, module directory without DOCS.md, DOCS.md without module, wrong title, Role 51 words, Purpose 26 words, empty Called by, missing Called by file, bare Called by name that resolves, issue reference, function and constant references, environment variables not constants, argparse metavar, exclusions, argument rejection, missing root variable). Every case also asserts that no `## Summary` appears. Clean cases assert all eight sections with `(0 findings)`.

## Read-only runs with this version (2026-09-25, base integration 5291633)

| Section | iterative-dev (worktree root) | monitor-cc |
|---|---|---|
| module headings | 1 | 0 |
| one DOCS.md per module directory | 1 | 9 |
| title | 0 | 1 |
| function-level references | 0 | 0 |
| constant references | 0 | 0 |
| word limits | 0 | 5 |
| Called by | 0 | 6 |
| issue references | 0 | 0 |

Findings seen (not fixed, outside the scope of this change):
- iterative-dev: `dev/worker_spawn/DOCS.md:37` claims `test_spawn_flow.sh` = 169, actual 171 (came in with the integration merge); `src/DOCS.md` names no module (it is an index of subdirectories).
- monitor-cc: five DOCS.md without a module heading (`dev/`, `dev/cc_internals`, `dev/pipeline`, `dev/rag_helpfulness`, `dev/tool_injection/ToolsSystemPrompts`); four module directories without DOCS.md, all under a `repo/` directory; root title `# ./ (project root)`; five Purpose texts of 27 to 38 words; Called by entries naming files that no longer exist (`worker_proxy.sh` under the old name, `_cases.py`, `_report.py`, `workers/worker_search.py`) and `./venv/bin/python`.
- Hypothesis, not judged: `./venv/bin/python` is a runtime path inside an excluded venv directory, so the Called by check can never resolve it; whether such entries should be exempt is an owner decision.

# Two false positives from the first monitor-cc run, 2026-09-25

Observed in monitor-cc: (1) `repo/`, `repo/.github/travis`, `repo/regress`, `repo/tools` reported as module directories without DOCS.md. `repo/` is a gitignored clone of the tmux sources (`.gitignore:48`). (2) `dev/refactoring/DOCS.md:69` Called by names `src.proxy`; the entry pattern read `.proxy` as a file extension and looked for a file `src.proxy`.

## Fixes

- **Gitignored paths are not part of the project.** `collect.py` asks git for the untracked ignored paths (`git ls-files --others --ignored --exclude-standard --directory -z` in the root) and prunes ignored directories and files from the one walk that feeds DOCS.md files, sources and the path index. Tracked files that match an ignore pattern stay in. The hand-written scan exclusions (worktrees, logs, dist, build, venvs) stay.
- **Tripwire, no fallback.** A root outside a git repository aborts with exit 2 and `is not inside a git repository` (`require_git_repo`, called right after the root is resolved). Owner decision: a plain temp dir as fixture is not a production condition, so every test fixture is a `git init` repo (one case, `root_outside_git_repository_aborts`, deliberately is not). The tests set `GIT_CONFIG_GLOBAL=/dev/null` so the user's global excludes cannot leak in.
- **Dotted package names in Called by.** A token is an entry when it contains `/` or ends in a dotted identifier (no more one-to-five-letter extension limit). It resolves when the entry, the entry with dots turned into slashes (`src.proxy` -> `src/proxy`), or that with `.py` appended exists in the path index. External dotted names such as `mitmproxy.http` get no special handling (never observed; they would be reported as missing).

## Tests

30 of 30 cases pass (with `CLAUDE_PLUGIN_ROOT` at the worktree). New: `gitignored_directory_not_a_module_directory`, `called_by_dotted_package_resolves`, `called_by_dotted_package_missing`, `root_outside_git_repository_aborts`.

# Empty __init__.py is not a module (2026-09-25)

Observed in this repo after `src/DOCS.md` (an index page without modules) was deleted: the tool reported "`src` holds .py or .sh modules but has no DOCS.md"; the only file there is an empty `src/__init__.py`. Owner decision: an empty `__init__.py` is not a module, so a directory whose only source files are empty `__init__.py` files is not a module directory. "Empty" means size 0 bytes. `check_directories.py` skips such files when collecting module directories; a non-empty `__init__.py` still makes its directory a module directory. Cases `empty_init_is_not_a_module` and `nonempty_init_is_a_module` pin both sides (32 of 32 pass).
