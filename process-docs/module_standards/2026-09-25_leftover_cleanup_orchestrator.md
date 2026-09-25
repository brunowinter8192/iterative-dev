# Leftover cleanup after the refactor sweep, orchestrator record (2026-09-25)

Orchestrator entry for the follow-up session that closed the open items of the 2026-09-24/25 refactor sweep. Worker entries: area `module_standards` (worker itdevspawn, model resolution and plugin-sync.sh), area `session_pipeline` (worker itdevpath, list_agents path encoding), area `skill_maintenance` (refactor skill Phase 2), and in reddit-cli area `discovery` (garbage filter numbers).

## Owner decisions taken in the chat

- Delete the shell `_resolve_worker_model`; the model argument of `spawn_claude_worker` and `spawn_claude_worker_from_file` is mandatory. Evidence given to the owner: no code caller omits the model except the dev/model_selector tests; `worker-cli spawn` always resolves in `spawn.py`; `worker_revive` reads the stored `WORKER_MODEL`.
- Delete `plugin-sync.sh`. Evidence: a scan of every session JSONL under `~/.claude/projects` (all tool_use Bash commands, 2026-09-25) found zero executions of the script, only reads, edits and mentions. The root `DOCS.md` documented only this script and was deleted with it (one DOCS.md per module directory; the root holds no module anymore).

## Done directly by the orchestrator

- `~/.local/bin/dev-sync` and `~/.local/bin/show` re-pointed from the removed `Meta/blank/bin/` to `Meta/iterative-dev/bin/`. Checked: `dev-sync` runs and refuses correctly when not on a dev branch; `show /nonexistent_xyz` prints `show: not found`. No other symlink in `~/.local/bin` points into `Meta/blank`.

## Traps seen in this session

- `worker-cli merge <name> <monitor-cc path>` for a worker that was spawned in monitor-cc but committed in a worktree of iterative-dev or reddit-cli is a no-op ("carried no commits"). The project_path must be the repo that holds the branch, e.g. `worker-cli merge itdevspawn ~/Documents/ai/Meta/iterative-dev`.
- A hook blocks `cd <worktree>` from the orchestrator; run worktree scripts by absolute path or use `git -C`.
- zsh expands a bare `=====` argument to `echo` as a command lookup and aborts the chain; use quoted separators.

## Verification state on 2026-09-25

- `src/spawn/*.sh` is loaded from the plugin cache. The model-argument change is live only after `plugin-publish`; the production check (a real spawn with and without explicit model) is due after the publish.
- `list_agents` could not be verified against real data: no directory under `~/.claude/projects` contains `*/subagents/agent-*.jsonl` on 2026-09-25. The hermetic test in dev/session_pipeline is the only evidence.

## Afternoon of 2026-09-25: rules, docs-drift-check, worker-cli, gcommit

Owner decisions taken in the chat (the code parts are documented by the workers in areas `docs_drift_check` and `worker_cli`):

- **Principles with sources in skill and rules.** Every technical term in the refactor skill and in `~/.claude/shared-rules` carries author and year, e.g. "Single Responsibility Principle (Robert C. Martin, 2003)". Only principles that fit the rule exactly were added; loose fits were removed again (Stage-Gate, Retrospective, Tim Pope's 50/72, Newspaper Metaphor). Terms without a single source (Package by Feature, Documentation Drift, Error Swallowing, four-eyes principle, transitive closure) were replaced by plain German sentences. No sentence like "there is no literature term for this" goes into a skill.
- **Output directories** sit on the level of the script that produces them (dev-convention rule); the refactor skill no longer says "output directories stay in the root".
- **Environment variables and CLI flags are allowed in DOCS.md** (documentation rule, interface vs implementation, David Parnas, 1972). Describing such a name in prose instead was rejected by the owner: it bloats the docs.
- **docs-drift-check maps 1:1 to the DOCS.md rules.** The generic path check was removed (no rule behind it). First run of the new version: 2 findings in iterative-dev, 21 in monitor-cc; it also caught `bin/DOCS.md` claiming 68 LOC for `worker-cli` (69), a heading the old version never checked because it has no file extension.
- **DOCS.md pages without own modules are deleted**, not exempted (owner, option 1). Affected: iterative-dev `src/DOCS.md`, monitor-cc `dev/`, `dev/cc_internals`, `dev/pipeline`, `dev/rag_helpfulness`, `dev/tool_injection/ToolsSystemPrompts`.
- **worker-cli without project_path and without model** (Poka-Yoke, Shigeo Shingo, 1986). Branch `wcli` (3112afc) is finished and reviewed, not merged.
- **gcommit replaced** in the rules by `git -C <repo> add -A && git -C <repo> commit -m "<msg>"`. Test on 2026-09-25 in a scratch repo: new folder with umlaut, file with umlaut and ß, file with a space, rename plus edit, all committed by `git add -A`, nothing left over. In September there were about 2100 gcommit calls vs 112 raw `git commit`; gcommit had three incidents that month.
- **Verification before session end is allowed**: publish first, verify, roll back if needed (testing rule).

Deferred until a second Claude Code session active on the same machine (merging `mc*`, `idwin`, `mcsrcid`) is finished, because `~/.local/bin/worker-cli` is live from the integration checkout and that session still uses the old forms:
1. Merge `wcli`, then plugin-publish (this order; the reverse breaks every spawn), then update `main/tool-use.md` and `main/workers.md` (project_path and model forms) and verify with a real spawn and a cross-project merge.
2. monitor-cc hooks: `rewrite_worker_wait.py` must stop rewriting `cd X; worker-cli wait` into `worker-cli wait X`; `block_worker_spawn_placement.py` keeps only the `--no-worktree` block.
3. Delete the DOCS.md pages without own modules listed above; fix the remaining monitor-cc findings of the new docs-drift-check.
4. Remove `bin/gcommit` and `src/git/commit.py` from iterative-dev (`git-check` shares `src/git/check.py` and stays).

Observed, not yet handled: `dev/worker_wait` and `dev/worker_spawn/test_spawn_flow.sh` fail partly when all suites run in parallel and pass alone (suspected fixed sleeps, unconfirmed).
