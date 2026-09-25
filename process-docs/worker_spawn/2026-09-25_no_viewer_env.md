# WORKER_NO_VIEWER: test spawns without a Ghostty window (2026-09-25)

## Incident
14 Ghostty windows stayed open, titled `tmux attach -t worker-e2e_project_mstestnomodel<pid>-mstestnomodel<pid>; exit` (and `...mstestexplicit<pid>...`), each showing `can't find session` and "Ghostty failed to launch the requested command ... Press any key to close the window". 7 pids, two windows each (one per run of the e2e_no_model and e2e_explicit strands).

## Cause
spawn (`tmux_spawn.sh`) and revive (`worker_revive.sh`) start `open_tmux_viewer "$session" &`. It opens a Ghostty window via osascript that types `tmux attach -t <session>; exit`. `dev/model_selector/verify_worker_model_precedence.sh` runs the real `worker-cli spawn ... --no-worktree` with a mock claude, reads the model, and kills the session about 1s later. The window attaches after the kill, tmux errors, the window stays.

## Decision
`open_tmux_viewer` (`src/spawn/worker_io.sh`) returns 0 immediately when `WORKER_NO_VIEWER` is non-empty. An env var, not a CLI flag: it flows unchanged through `worker-cli spawn` -> `python3 -m src.spawn.spawn` -> `bash -c` -> `tmux_spawn.sh`, needs no positional-arg plumbing in `cmd_spawn` (whose 5th positional is `--no-worktree`), and also covers the revive call site. Unset = old behaviour, byte-identical code path. `_spawn_via_cli` in the model precedence script exports it.

## Verification
- `dev/worker_spawn/verify_no_viewer.sh`: three parallel strands on `dev/strand_runner.sh` (private HOME, private tmux socket). osascript and ghostty are PATH stubs; the osascript stub only logs. Chosen over counting windows because a stub is deterministic, independent of the user's own Ghostty windows, and cannot open a window even if the guard is broken.
  - default spawn: exactly one osascript call containing `tmux attach -t <session>; exit`.
  - `WORKER_NO_VIEWER=1` spawn: session exists, zero osascript calls.
  - `open_tmux_viewer` called directly, set vs unset (the function revive shares).
- Negative control: with the guard stashed away, the two suppression strands fail with `calls=1`.
- Final real run of `verify_worker_model_precedence.sh` (real osascript): System Events window count of Ghostty was 9 before and 9 after, 5 strands passed.
- Pitfall: the osascript argument is a multi-line script, so count the `tmux attach` lines in the log, not lines.
- Revive was not exercised end to end (needs a dead pane and a session JSONL); it shares the guarded function.

## Not done
The 9 windows present during the run were not touched. The plugin cache copy of worker-cli was not touched; the guard takes effect for the real cache only after a publish by the user.

## Merge with integration (2026-09-25)
Integration moved by 9 commits while this work ran (single worker-model resolution, plugin-sync.sh dropped, list_agents fix). It rewrote `dev/model_selector/verify_worker_model_precedence.sh` (strands now: explicit_model, missing_model, e2e_no_model, e2e_explicit, e2e_malformed, structural). Merge `34215d7` had one conflict, the LOC heading in `dev/model_selector/DOCS.md` (227 vs 211); resolved to 212 = their 211 plus the one-line `WORKER_NO_VIEWER=1` export, which git merged into their rewrite without a conflict.
Re-run after the merge: `verify_no_viewer.sh` 3/3 strands; `verify_worker_model_precedence.sh` 6/6 strands with the real osascript; Ghostty windows 3 before, 2 after (the drop came from a window closed elsewhere, no increase).
Pitfall: piping the precedence script through `grep -v` loses its exit code (`${PIPESTATUS[0]}` was empty in a non-interactive eval); judge by the strand lines and the summary line.
