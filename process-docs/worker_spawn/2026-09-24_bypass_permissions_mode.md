# Workers start in bypassPermissions mode (2026-09-24)

## Decision
Workers always start with no permission prompts. Reason (observed 2026-09-23/24, canvas worker logs): Bash calls like `rm node_modules; git status --short; gcommit ...` sat 40 min, `rm node_modules reference && git status --short` 8.4 and 2.5 min, waiting for an unanswered prompt. Edits under ~/.claude also always prompt in acceptEdits.

## Change
- `src/spawn/tmux_spawn.sh`: constant `_WORKER_PERMISSION_FLAGS="--permission-mode bypassPermissions"`, used by the default `extra_flags` of `spawn_claude_worker` and `spawn_claude_worker_from_file`, and by the runner command in `worker_revive` (previously hard-coded `--permission-mode acceptEdits`).
- `spawn.py` passes no flags, so it inherits the shell default. Unchanged.
- `claude-280` is a 400-byte wrapper script exec'ing `~/cc-cache-fix-280/node_modules/@anthropic-ai/claude-code/bin/claude.exe`; `strings`/`grep -a` on the wrapper finds nothing. Use `--help` and scratch runs, not binary greps.
- `claude-280 --help`: `--permission-mode` choices are acceptEdits, auto, bypassPermissions, manual, dontAsk, plan. `--dangerously-skip-permissions` also exists. Not compared past the trust screen.

## Startup dialog (observed)
Scratch tmux session, `CLAUDE_CONFIG_DIR=/tmp/bp_cfg` (copy of ~/.claude.json, empty settings.json):
1. Folder trust: "Quick safety check: Is this a project you created or one you trust?" (`hasTrustDialogAccepted` is written to `.claude.json` under `projects[<path>]`).
2. Then: "WARNING: Claude Code running in Bypass Permissions mode ... No, exit / Yes, I accept".
After accepting, `<config dir>/settings.json` contained exactly `{"skipDangerousModePermissionPrompt": true}`.
The spawn readiness gate (`^❯` at column 0) does NOT match these dialogs (they use " ❯ 1." style or leading spaces), so an unsuppressed dialog makes spawn fail after 30s instead of injecting the prompt into the dialog. The user decided not to auto-confirm via send-keys; suppression is via that settings key.
The user's ~/.claude/settings.json already has `skipDangerousModePermissionPrompt: true` (read 2026-09-24). Untested: that the key alone suppresses the dialog in a fresh run (the scratch run showed the dialog first, then the key was written). Untested: a real worktree path regarding trust dialog.
Scratch config has no login (keychain), shows "Not logged in": model calls need the real config.

## rm deny rules under bypass (observed)
`~/.claude/settings.json` has deny `Bash(rm :*)`, `Bash(rm -rf :*)`, `Bash(rmdir :*)`. `claude-280 -p --permission-mode bypassPermissions` in /tmp/bp_proj with real settings: `rm /tmp/bp_proj/a.txt` ran (no output, file gone); `rm -rf /tmp/bp_proj/b.txt` ran without error. So deny rules are not enforced under bypassPermissions. Untested: whether they ever matched under acceptEdits (the rules have a space before the colon, so they may never have matched). Note: the model refused a prompt that named the file `victim.txt`; use neutral file names in such tests. Passing `CLAUDE_CONFIG_DIR=` (empty) makes claude create its config folders in cwd; do not do that.

## canvas .gitignore (observed)
`node_modules/` and `reference/` (trailing slash) match directories only; symlinks into the worktree showed as `?? reference`. Fix: `node_modules`, `reference` without slash, verified with `git check-ignore -v` and `git status` (scratch repo: old pattern leaves both symlinks untracked, new pattern ignores them; real dirs stay ignored). canvas `.git/info/exclude` already contains `node_modules`, which masks that pattern in `git check-ignore` inside canvas worktrees; use a scratch repo to test .gitignore rules. Committed in canvas as a6b212d.

## Test
`dev/worker_spawn/render_runner_flags.sh` sources tmux_spawn.sh with stubbed tmux, viewer, proxy, logger and a fake HOME, calls `spawn_claude_worker`, `spawn_claude_worker_from_file`, `worker_revive`, greps the generated runner scripts, writes `dev/worker_spawn/md/render_runner_flags.md`. Output:
```
spawn:      /fake/claude --model 'claude-sonnet-5' --permission-mode bypassPermissions
spawn_file: /fake/claude --model 'claude-sonnet-5' --permission-mode bypassPermissions
revive:     /fake/claude --model 'claude-sonnet-5' --permission-mode bypassPermissions --resume '11111111-2222-3333-4444-555555555555'
```
Pitfall: `spawn_claude_worker_from_file` tests `[ -f ]` on the prompt file, so process substitution (`<(...)`) fails; use a real file.

## Verification checklist for a real worker (done by the user after merge)
- Status bar: `⏵⏵ bypass permissions on (shift+tab to cycle)`; acceptEdits would say "accept edits on".
- No bypass warning screen; prompt `❯` reached within 30s.
- Bash commands run without a prompt.
- `ps -o command=` of the claude process shows `--permission-mode bypassPermissions` (before `--resume` for revive).
