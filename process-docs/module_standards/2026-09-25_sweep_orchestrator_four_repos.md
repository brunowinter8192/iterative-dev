# Refactor sweep over gh-cli, rag-cli, reddit-cli and iterative-dev, orchestrator record (2026-09-24/25)

Main-agent entry for a full, autonomous run of the refactor skill (Phases 0-6) over four repositories. The workers' own entries sit in each repo: gh-cli area `code_cohesion`, rag-cli area `module_standards`, reddit-cli area `refactor_sweep`, iterative-dev area `module_standards` (worker files for core and dev) and `docs_drift_check`. This entry holds what only the orchestrator saw: the decisions, the incidents and how the work was cut.

## Starting state, measured 2026-09-24

- gh-cli, rag-cli, reddit-cli: Phase 1 and Phase 2 clean (no file over 400 LOC, no function at or over 50 LOC, zero comments/docstrings) thanks to the 2026-09-16 sweep. Work started at Phase 3 (gh, rag) or Phase 4 (reddit, which has no tests in dev/).
- iterative-dev: all Python clean, but the shell side had never been swept. `bin/worker-cli` 895 LOC, `src/spawn/tmux_spawn.sh` 937 LOC, `dev/worker_wait/test_worker_wait.sh` 739 LOC, six shell functions over 50 LOC, 978 comment lines in shell files.

## How the work was cut

- One worker per repo, reused across phases (ghcli, ragcli, redditcli). iterative-dev got two workers split by directory: itdevcore (bin/, src/, root) and itdevdev (dev/), because dev/ tests source src/spawn functions and would otherwise collide. Rule given to itdevcore: never rename a function that is called from outside its file.
- Per phase: Main scans with scripts in /tmp (size via AST/awk, comments via tokenize, DOCS.md format, docs-drift-check, a fallback candidate list via AST + regex), writes a findings file to /tmp/refactor/, sends the path. For Phase 5 the worker returns a per-line verdict table first; Main decides, then the worker implements.
- Phase 6: a fresh worker per repo, prompt "activate the skill, run only the scan steps, report". Main assessed every finding; confirmed ones went back to the repo's implementation worker.

## Decisions a successor will face again

- **Observed means observed.** For Phase 5 a nullable field in the GitHub schema was not accepted as evidence. Evidence = a real occurrence in a dev/ report, process-docs, a fixture, or the indexed corpora under `rag-cli/data/documents`. Example that justified a fallback: gh-cli's trending probe saw repositories without a description (10 of 522), so `get_repo_tree` shows `(none)` and logs instead of raising. Example that did not: primaryLanguage null never seen, so it raises.
- **Live verification finds real bugs.** The strict-access run against live GitHub found that trending pages print `1 star today` in the singular; the regex only accepted `stars`, so trending aborted on those days. Fixed with a real single-star fixture.
- **Kept on purpose despite the rule:** rag-cli `retrieval_log.py` catches around log writes (earlier documented decision 2026-09-18, traced to errors.jsonl, covered by tests). gh-cli `raw_logging.py` warning-swallow (same reasoning). `CLAUDE_SESSION_ID:-unknown` in tmux_spawn metadata: the variable is unset in a normal Main-agent Bash, so the fallback fires on every spawn; it is observed and visible.
- **Shared test runners live in the dev/ root.** rag-cli `dev/strand_runner.py`, iterative-dev `dev/strand_runner.sh` and `dev/strand_runner.py`. The alternative was ~20 duplicated lines in about ten suites.
- **One orchestrator per module wins over module count.** rag-cli's split added about 15 small modules (retriever and server_lifecycle dissolved). Accepted.
- **Lazy imports:** rag-cli moved every import to module scope; `time rag-cli status` stayed at 0.27-0.31 s, so no import needed to stay lazy.

## Incidents

- **Production corpus written by a live check.** redditcli's Phase 5 end-to-end run fetched 13 real posts into `rag-cli/data/documents/reddit-cli-posts/` (with `--skip-index`, so never indexed). It then tried `rm "$D/$f"` in a loop; Main interrupted with Escape via tmux because `worker-cli send` refuses to talk to a working worker. `rag-cli delete --document` was later blocked by a hook after one call. Main removed the remaining 12 files by explicit list after confirming `rag-cli list_documents reddit-cli-posts --document 'espresso__%'` showed none of them indexed. For the Phase 6 smoke the worker redirected `RAG_DOC_DIR` to a scratch dir via `python -c`. Instruction for any future live check: the output directory must not be the production corpus.
- gh-cli's live check indexed 2 real discussions into `github_discussions` (1 chunk). Left in place; it is real data.
- **Trust dialog.** A Claude Code worker spawned in a fresh scratch path blocks on the folder-trust dialog (trust is stored per exact path in `~/.claude.json`). itdevcore's live spawn test failed four times for this reason, not because of the code. The fifth run used an already-trusted path with `--no-worktree` and passed. Main's own spawns after the publish served as production verification.
- **Suites that touched the real hooks.json.** Before Phase 3, the wait and status suites backed up and restored the menubar's global hooks.json while a second session's workers were live. Both iterative-dev workers ran such suites only under `lockf /tmp/itdev-suite.lock`. After Phase 3 every strand has its own HOME and `tmux -L` socket, and the suites no longer touch real state.
- **`test_spawn_flow.sh` never tested the code.** It failed 3 of 7 checks before any change: a non-existent `Monitor_CC` project path, a proxy marker that only exists while a real proxy runs, and a mock `claude-patched` that production never launches (it launches `CLAUDE_BIN`, so a real claude-280 started at the user's cost). Rebuilt as three self-contained strands.
- **Unknown worker name returned garbage.** `grep -c ... || echo 0` printed `0\n0`, so `worker-cli status <unknown>` resolved an error text as project path with exit 0. Fixed in Phase 5; it now prints "not found in registry or tmux" with exit 1.

## Deploy order for iterative-dev (live infrastructure)

- `bin/worker-cli` is symlinked from `~/.local/bin` into the checkout, and it loads `src/worker_cli/` relative to its real path. It is live the moment integration changes.
- `src/spawn/*.sh` is loaded from the plugin cache (`$PLUGIN/src/spawn/tmux_spawn.sh`), which only changes on `plugin-publish`. After the split `tmux_spawn.sh` sources five sibling files, so all six must be published together. `plugin-publish` rsyncs the whole repo, which guarantees that.
- After each merge Main ran `worker-cli list`, `status` on a known and an unknown name, and a real spawn.

## Left open

- `plugin-sync.sh` in the iterative-dev root has no caller; it is flagged as dead code in the root DOCS.md, not deleted (the user may run it by hand).
- reddit-cli `dev/discovery/09_garbage_filter_probe.py` prints `garbage_recall=43%` while its stored report says 48% (pre-existing, not investigated).
- gh-cli `dev/content_cleaning/05_strip_build_logs.py` still has functions inside INFRASTRUCTURE (not in the confirmed findings).
