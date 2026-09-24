# 2026-09-24 - docs-drift-check moved into iterative-dev and aligned with the DOCS.md rules

Branch `driftcheck`. Origin: standalone script `~/.local/bin/docs-drift-check` (not versioned) was rewritten as `bin/docs-drift-check` + `src/docs_drift_check/`. The old file was not touched; the user switches the symlink after merge.

## Decisions

1. **LOC exact.** Finding whenever claimed != count of newline bytes (`wc -l`). Old tolerance of 4 removed. Any extension in the heading (`.py`, `.sh`, ...), headings may carry a relative subpath (`tests/x.py`). A heading whose module file does not exist is its own finding.
2. **Scope = DOCS.md only.** `decisions/**` and `sources/sources.md` removed, OldThemes special cases removed. Excluded directories: `.claude/worktrees`, `logs`, `src/logs`, `.git`, venvs, `node_modules`, `__pycache__`, `dist`, `build`.
3. **`dist`/`build` excluded because observed:** monitor-cc has `dist/monitor-cc-menubar.app/.../DOCS.md` copies (gitignored build artifact) that produced 208 duplicate findings on the first run.
4. **Symbol check became a rule-violation check.** Existence is irrelevant; a DOCS.md must not name functions or constants. To avoid false positives on external tokens (`EXIT`, `CONFLICT`, `THIS`), only references to symbols DEFINED in the project's `.py`/`.sh` sources are reported:
   - function: `def name` (py) or `name() {` (sh), referenced as `name(`.
   - constant: `NAME = ...` at column 0 (py) or `NAME=...` optionally after export/readonly/local/declare (sh), referenced as bare token. Env vars count once assigned in the project (user decision, no exception list).
   - module-dot-function: token `x.y` or `path/x.y` where `x` is a source file stem or a defined class and `y` is not a known file extension. Reported regardless of whether `y` exists. Example: `src/panes/cache_turns.build_cache_turns` (monitor-cc `src/dual_log_cli/DOCS.md:226`) was previously "path NOT FOUND", now "function-level reference". The path check skips such tokens.
5. **Whitelist mechanism removed** together with `.drift-whitelist.txt`. It existed only because the old check demanded symbols exist in `.py` sources. Hypothesis not observed: a legitimately needed exception; if one appears, fix the DOCS.md, not the tool.
6. **Bash sources are part of the symbol index** (`.py` and `.sh` across the whole project, replaces the hard-coded `src/**`, `dev/**`, `cli.py`, `start.sh`).

## Wrapper pitfall (do not repeat)

Agreed plan was `PYTHONPATH=$PLUGIN python3 -m src.docs_drift_check` in the caller's cwd. That breaks: `-m` puts cwd first on `sys.path`, and monitor-cc has `src/__init__.py`, so `src` resolves to the project's package. Implemented instead: wrapper exports `DOCS_DRIFT_ROOT="$PWD"`, then `cd "$PLUGIN"` like `bin/poread`; `project_root.resolve_root` reads the variable (fallback cwd for direct runs). Test case `shadowing_project_src_package` pins this.

## Tests

`dev/docs_drift_check/test_docs_drift_check.py`: 13 fixture cases, each in its own temp dir, all run in parallel threads (subprocess of the real wrapper), each case stops at its first failed assertion, others continue. No pytest. All 13 passed. Only observed situations are covered.

## Verification, 2026-09-24 (read-only)

iterative-dev worktree: Path 0, LOC 0, Rule-Violation 40 (all real: DOCS.md name functions or constants, e.g. `src/poread_cli/DOCS.md` names four POREAD_* constants). Not fixed, out of scope.

monitor-cc: Path 3, LOC 4, Rule-Violation 596 (393 function, 206 constant, counted on lines) after the dist/build exclusion (before: 826).
- Path (3, all real): missing report file in `dev/sleep_pattern_analysis/DOCS.md:18`, dead `src/proxy_forensics.py` in `dev/tool_use_analysis/DOCS.md:37`, cross-repo `src/poread_cli/__main__.py` without `(Iterative_Dev)`-style marker in `src/proxy/DOCS.md:418`.
- LOC (4, all real under strict rule): 128 vs 171, 120 vs 138, 83 vs 92 (`dev/proxy/DOCS.md:117`), 213 vs 212.
- Questionable rule findings: `PATH` (argparse metavar in `--baseline PATH`, matched only because some script assigns `PATH=`). `PASS`/`FAIL`/`ERROR`: shell counters in dev scripts; DOCS name them as such, technically violations. mitmproxy hook names (`request()`, `response()`, `error()`) are real defined functions, real violations.

## Review fixes, 2026-09-24

- Wrapper comment lines removed (shebang only).
- `config.py` deleted; each constant now sits in the single module that uses it (collect, project_root, symbols, markdown_scan).
- `resolve_root` no longer falls back to cwd: missing `DOCS_DRIFT_ROOT` prints an error to stderr and exits 2. Test case `missing_root_variable_aborts` runs `python3 -m src.docs_drift_check` without the variable.
- Argparse metavars handled structurally: an ALL_CAPS token directly after `--flag` (space or `=`) inside one backtick span is not a constant reference. Fixture `argparse_metavar_not_constant`, with a project that assigns `PATH=` in a script.
- Tests: 15/15 passed. Rerun (read-only): iterative-dev worktree Path 0, LOC 0, Rule-Violation 40. monitor-cc Path 3, LOC 4, Rule-Violation 593 (390 function, 203 constant), down from 596. The two remaining `PATH` hits in monitor-cc (`dev/menubar_per_project`-style launchd PATH prose) are real env var references, not metavars.
- Pitfall: macOS `wc -l` pads its number with spaces; strip it before pasting into a DOCS.md heading, otherwise the heading no longer matches the LOC pattern and the check silently skips it.

## Recap, 2026-09-24

DOCS.md LOC headings in `src/docs_drift_check/` and `dev/docs_drift_check/` were checked against `wc -l` and all equal (the tool itself reports LOC-Drift 0 for this repo). `skills/iterative-dev-refactor/SKILL.md` shows up in `git diff integration` only because integration advanced after the branch point; this work did not edit it. What a successor should know: the rule-violation count in this repo (40) and in monitor-cc (593) is the remaining DOCS.md cleanup backlog, not tool defects; the tool has no exception mechanism by design.

## Follow-up: brace-template spans, 2026-09-24

Observed in rag-cli: `dev/eval_suite/DOCS.md:12` has the span `queries/pass_{a,b,c,d}_runs/`; the path check reported `queries/pass_` NOT FOUND because the path pattern stops at the brace, so the brace skip inside the per-path filter never saw it. Fix: a span containing a brace is skipped as a whole in the span-level exclusion, like spans with angle-bracket templates. Fixture `brace_template_span_skipped` pins it. Integration (05609b9) was merged into the branch first (fast-forward).
