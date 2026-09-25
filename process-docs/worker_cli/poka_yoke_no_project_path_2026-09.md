# worker-cli: project_path and model argument removed

2026-09-25, iterative-dev. Area worker_cli.

## Decision (owner)

worker-cli leaves no room for interpretation (Poka-Yoke): the wrong call is made impossible instead of forbidden by instruction. No subcommand takes a project path any more; the only path arguments left are `<target_repo>` of `worktree` and `worktree-rm`, and the log directory of `sweep-logs`. `spawn` takes no model. Any surplus argument aborts with exit 2 and prints the correct form (tripwire, fail fast).

## Forms

```
list | status <name> | status --all | capture <name> [--raw] | response <name> [count]
send <name> <message> | kill <name> | revive <name> | merge <name>
spawn <name> <prompt_file> [--no-worktree] | wait [--timeout SEC]
worktree <name> <target_repo> [branch] | worktree-rm <target_repo> <name> [branch]
```

Observed old-style calls and the error they now get:
- `worker-cli merge itdevspawn /repo` -> `unexpected argument '/repo'. A project_path argument was removed; worker-cli resolves the project itself. Correct form: worker-cli merge <name>`
- `worker-cli wait /path` -> `unexpected argument '/path'. wait takes no path and uses the current project. Correct form: worker-cli wait [--timeout SEC]`
- `worker-cli spawn n p.txt /repo claude-x` -> `unexpected argument '/repo'. spawn takes no project_path and no model ... Correct form: worker-cli spawn <name> <prompt_file> [--no-worktree]`

The check lives in `src/worker_cli/args.sh` (`require_arity`, `arg_unexpected`); `capture`, `spawn` and `sweep-logs` strip their flags first and check the remaining positionals.

## Project resolution

- Every command except spawn, wait, list and status --all finds the project through the registry (`resolve_worker_project`, no override any more).
- `spawn`: `PROXY_PROJECT_PATH` if set, else the git root of the cwd. A cwd outside any git repo aborts (exit 1): `resolve_project_path` alone falls back to the plain directory, which would have created a registry entry for a non-repo.
- `wait`: the git root of the cwd (fallback: the cwd itself, as before). Test fixtures that used `wait <dir>` now run wait with `cd <dir>`.
- `list` and `status --all` without arguments already listed the whole registry; only the optional path was dropped.

## spawn model

`spawn.py` lost the `model` positional; the model is always `_resolve_worker_model()` (config `worker`, hardcoded fallback). `tmux_spawn.sh` still requires a model in `spawn_claude_worker*`: that is the internal API between spawn.py and the shell layer, covered by the `explicit_model`/`missing_model` strands, not user surface.

## merge across repos

Observed 2026-09-25: a worker spawned in monitor-cc that committed in an iterative-dev worktree: `merge <name> <monitor-cc>` was a no-op ("carried no commits"), only `merge <name> <iterative-dev>` worked.

Now `merge <name>` builds the target list: the registry project with branch `<name>`, plus every `<repo>\t<branch>` line of the sidecar `<name>.worktrees`, deduplicated by repo, only repos where the branch exists. Per repo:
- `git rev-list --count <current>..<branch>` is 0 -> line `skipped: branch ... carries no commits`, merge not run. (This replaces the old parse of "Already up to date": the spawn-project branch of a cross-project worker is empty by design and must not fail the whole merge.)
- otherwise `git merge --no-ff`, then the existing `diff ORIG_HEAD --name-only` check.
- conflict: abort at once with `merge failed in <repo>, stopping`; repos merged before stay merged.
Exit 1 when no repo holds the branch, or when every repo was skipped (`carried no commits in any of its repos`). Merge still does not remove worktrees; only kill does.

## janitor

`janitor.sh` used to call `"$0" kill <name> <project>`. `cmd_kill` is split into the guarded command and `_kill_worker <name> <project>`; janitor calls `_kill_worker` directly, so the janitor keeps working with the project it resolved (including the pane-path fallback, hypothesis: never observed) without a project argument on the CLI.

## Deployment

`bin/worker-cli` and `src/worker_cli/` are live for every session on the machine at merge (symlink into the integration checkout). `src/spawn/spawn.py` comes from the plugin cache until plugin-publish. The new `cmd_spawn` passes no model argument, which the old cached spawn.py accepts (`model` was `nargs="?"`), so merge first, publish second is safe. The reverse order breaks: the old cmd_spawn passed an empty model positional that the new spawn.py rejects.

## Callers outside iterative-dev that break (read only, monitor-cc not edited)

- `monitor-cc/src/hooks/rewrite_worker_wait.py`: `_collapse_cd` rewrites `cd X && worker-cli wait [args]` into `worker-cli wait X [args]`, and `_BLOCK_MESSAGE` recommends `worker-cli wait /path/to/project`. Both now hit the wait tripwire. Needed change: `_collapse_cd` must drop the path and emit `worker-cli wait [args]` (a leading `cd` is not preserved by a rewritten single command, so the rewrite has to either block with "run wait from the project directory" or emit `cd X && worker-cli wait [args]` accepted by the canonical form); the block message must stop recommending a positional path.
- `monitor-cc/src/hooks/block_worker_spawn_placement.py`: `_SPAWN_RE` needs three positionals and no longer matches the new two-positional form, so the wrong-project check is dead. `spawn n p --no-worktree` is still blocked (the third token matches). Messages still quote `<prompt_file> c` and `<prompt_file> <project_path>`. Needed change: keep only the `--no-worktree` block, regex `spawn\s+(\S+)\s+(\S+)`, new messages.
- `~/.claude/shared-rules/main/tool-use.md` lines 13-16, 18-20, 23 and `workers.md` lines 290, 334 still list `[project_path]` and `[model]`.
- Not searched: CLAUDE.md files and project-level rules.

## Test evidence

Suites run as parallel strands with CLAUDE_PLUGIN_ROOT at the worktree: worker_cli (5), worker_merge (4, including cross-project without path and cross-project conflict), model_selector (6 shell + 6 python), worker_spawn (xproject 3, viewer 3, flow 3), worker_janitor (4), worker_sweep_logs (5), worker_wait (15). Running all suites at once produced load timeouts in worker_spawn/test_spawn_flow (viewer took 10s, spawn 12.7s) and five worker_wait strands (four of them run into fixed timing windows; two were wait calls on non-existent directories that needed `mkdir` and `cd`); both passed when run alone. Lesson: run the timing-sensitive suites (worker_wait, test_spawn_flow) on their own.

## Recap (2026-09-25)

Status: committed on branch `wcli`, not merged. The merge waits until another Claude Code session on the machine, which still calls worker-cli with project_path and a wait path, is finished. Once `bin/worker-cli` is merged to integration it is live for every session immediately, and those old-style calls then abort with exit 2.

Files of this task (`git diff integration --name-only`, the `docs_drift_check` entries in that list come from integration having moved on, not from this task): `bin/worker-cli`, `src/worker_cli/{args,cmd_lifecycle,cmd_query,janitor,registry,wait}.sh`, `src/spawn/spawn.py`, the DOCS.md of `src/worker_cli`, `src/spawn`, `dev`, `dev/worker_cli`, `dev/worker_merge`, `dev/model_selector`, `dev/worker_spawn`, `dev/worker_wait`, and the dev suites named in the test evidence section.

Order after the other session is done: merge `wcli` to integration, plugin-publish, then verify with real workers. Include the hook, rule and skill follow-ups listed above (monitor-cc hooks `rewrite_worker_wait.py` and `block_worker_spawn_placement.py`, shared-rules `tool-use.md` and `workers.md`) before or together with the merge, otherwise the `cd X && worker-cli wait` rewrite by the hook produces a tripwire error.

Working lessons: (1) a Python rewrite of a file with `open(p,'w')` before `open(p).read()` truncated `tests_transitions.sh` once; restore with `git checkout` and read first. (2) `sed -i` on macOS needs an empty suffix argument. (3) Run `worker_wait` and `test_spawn_flow` alone; in a 9-suite parallel run they hit their fixed timing windows.

## Follow-up 2026-09-25: gcommit removed

Owner decision: `bin/gcommit` and `src/git/commit.py` are removed. The rules now commit with `git -C <repo> add -A && git -C <repo> commit -m "<msg>"`. A scratch test on 2026-09-25 showed `git add -A` commits new files with umlauts, sharp s and spaces, and a rename plus edit, with nothing left over; so the skip list and the plugin-dir refusal of gcommit are gone on purpose.

Removed together with them, because they existed only for gcommit: the `gcommit` entry of `bin/DOCS.md`, the `commit.py` entry and all gcommit wording of `src/git/DOCS.md`, and in `dev/git_automation/` six of the seven probe cases (they drove `src.git.commit`) plus the two timestamped reports of the old probe. The remaining case, `git-check --auto-stage` on umlaut and space paths, lives in `probe_git_check_staging.py` (renamed from `probe_umlaut_staging.py`; reports are named after the script). Kept: `bin/git-check` and `src/git/check.py` (its `stage_all` is used by `--auto-stage`), `bin/gc` (separate `git commit -am` shortcut).

Not touched: the plugin cache still holds `bin/gcommit`, which stays on PATH until the next plugin-publish. Historic process-docs entries about gcommit are left as they are.

Monitor-cc side of the wcli change: see area worker_cli in the monitor-cc process-docs.
