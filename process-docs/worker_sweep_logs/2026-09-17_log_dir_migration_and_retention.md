# Log directory moved off Meta/blank; a 72h retention sweep added

## Problem

Three code paths defaulted their log directory to `$HOME/Documents/ai/Meta/blank/src/logs`:
`bin/worker-cli` (`_WAIT_TRACE_FILE`, `wait_trace.log`), `bin/worker-cli`
(`_JANITOR_LOG_FILE`, `janitor.log`), and `src/spawn/tmux_spawn.sh`
(`_start_worker_logger`'s `log_dir`, the per-spawn diagnostic logs and `_DEATH.txt`
snapshots). `bin/worker-cli` line 3 also still credited `Meta/blank/bin/worker-cli` as its
own source.

`Meta/blank` held nothing else: no `bin/`, no other source, not even a git repo. It existed
only as a destination these three defaults happened to point at, kept alive purely by that
fact. Measured before this change: 333 files, 49MB, oldest 2026-08-01, newest the day of this
change, nothing had ever cleaned it. The intended destination,
`Meta/iterative-dev/src/logs`, already existed with a `.gitkeep` and was already covered by
`.gitignore` (`src/logs/*.log`, `src/logs/*_DEATH.txt`) — it held 92 stale files of its own,
newest 2026-06-08, left over from before the redirect to `Meta/blank` was introduced
(2026-05-25, `process-docs/worker_spawn/worker_revive_proxy_and_logger.md`).

## Decision — destination

All three defaults now point at `$HOME/Documents/ai/Meta/iterative-dev/src/logs`, this
repo's own checkout, unconditionally (not derived from `$CLAUDE_PLUGIN_ROOT`, same as
before) — the plugin executes from a cache copy that a publish overwrites, so the log
destination has always deliberately been the source-repo path, never the cache path. The
stale `Meta/blank/bin/worker-cli` source comment on line 3 was corrected to
`Meta/iterative-dev/bin/worker-cli`, which is what `~/.local/bin/worker-cli` actually
symlinks to (`readlink` confirmed live). `dev/worker_wait/test_worker_wait.sh`'s
`TRACE_FILE` default was updated to match — it reads the same real, shared file `wait`
itself writes, so a stale default there would silently diff against the wrong path. A grep
across both repos, before making this change, found exactly these three files as the only
code referencing `Meta/blank`.

## Decision — naming, so this cannot be confused with `worker-cli janitor`

`worker-cli janitor` already exists and sweeps stale tmux WORKER SESSIONS on a 12h default,
writing `janitor.log`. This is a different sweep over a different resource on a different
default, so it got a different name end to end: CLI subcommand `sweep-logs` (not
`log-janitor`, not `janitor-logs`), backing function `sweep_stale_logs` (not
`_janitor_sweep_logs`), own audit file `log_sweep.log` (not appended to `janitor.log`). None
of the three names share a token with `janitor`, deliberately, so a reader grepping for
either sweep's name can never pull in the other's lines.

## Decision — what the 72h rule applies to, and what happens to the existing self-trim

Measured the actual composition of the 49MB pile before deciding: `wait_trace.log` was
1.3MB, `janitor.log` was 28KB, the remaining 331 per-spawn `*.log`/`*_DEATH.txt` files were
47MB — the entire size problem was in files that had never had any rotation at all, not in
the two files that get read for live diagnostics.

`wait_trace.log` already self-trims by LINE COUNT (`_wait_trace_init` in `bin/worker-cli`,
20000 lines down to 10000, unchanged since 2026-08-18) — a different axis than age, and
already adequate for what the file is: a single continuously-relevant trace read for live
`wait` diagnostics, not a one-shot dateable snapshot. `sweep_stale_logs` excludes it by name,
unconditionally, regardless of age. This is not a second bound stacked on the first; it is a
deliberate non-interaction. An age bound on top of the line-count bound would either never
fire (mtime refreshes on every poll while `wait` is in active use, which is most of the time
this file is growing at all) or, during a lull, delete the one file still worth reading for a
few hundred KB of saved space. Verified in the test suite (`dev/worker_sweep_logs/`):
`wait_trace.log` survives even `--max-age-hours 0`, which deletes every other file in the
same directory in the same run.

Everything else in the log directory — the per-spawn files, `_DEATH.txt` snapshots,
`janitor.log`, and `sweep_stale_logs`'s own `log_sweep.log` — gets one rule: delete by mtime
if older than 72h (`sweep_stale_logs`, default parameter, no separate constant duplicated
elsewhere). `janitor.log` and `log_sweep.log` both keep rewriting themselves every time their
respective sweep runs, so in an environment where either sweep still fires at all, neither
ages out; they would only be swept if the whole mechanism around them stopped running for
72h, which is the same "genuinely stale" signal the per-spawn files are swept on.

## Decision — trigger

`worker-cli janitor` is triggered externally, from `monitor-cc`'s `claude_proxy_start.sh`, at
every main-session start (`monitor-cc/process-docs/worker_janitor/2026-08-19_janitor_trigger_on_session_start.md`)
— a different repo, not touched here and not needed here. `sweep_stale_logs` is called
in-process from `_start_worker_logger` (`src/spawn/tmux_spawn.sh`), once per `spawn` and once
per `revive`, immediately after `mkdir -p "$log_dir"` and before the new per-worker log file
is created. This ties the sweep to the exact action that produces the clutter — spawning or
reviving a worker is what creates a new per-spawn log file, so sweeping the directory right
before adding to it is symmetric, self-contained inside this repo, and — given how often
workers get spawned in this environment (hundreds of `*_spawn.log` files accumulated between
2026-08-01 and today) — fires far more often than the 72h window it enforces. The call is
`|| true`-guarded at the call site; `sweep_stale_logs` itself guards every risky step
(`mkdir`, `stat`, `rm`, the `find` that feeds its delete loop) the same way, so a sweep
hiccup can never abort a spawn under this file's `set -euo pipefail`.

`sweep_stale_logs` is also exposed directly as `worker-cli sweep-logs [--dry-run]
[--max-age-hours N] [log_dir]` — both the automatic call and the manual CLI case route
through the one function (`bin/worker-cli`'s case is a thin delegate via the same
`source "$SPAWN" && fn` pattern every other delegated case already uses), so there is exactly
one implementation of the rule, not two.

## Testing a time-based sweep without waiting 72 hours

`dev/worker_sweep_logs/test_sweep_logs.sh`: ages are faked with `touch -t`, using the same
`date -v-<N>H` (macOS) / `date -d "-<N> hours"` (GNU) fallback `dev/worker_janitor/test_janitor.sh`
already established for faking `session_created`. A file backdated 200h and one left at its
real (fresh) mtime prove dry-run lists the former without deleting either, and a real run
deletes the former while sparing the latter. A file at 71h and one at 73h, swept with no
`--max-age-hours` flag at all, prove the default is actually 72 and not some other round
number. A `wait_trace.log` backdated 999h, swept at `--max-age-hours 0` (which matches every
other file), proves the exclusion is unconditional. The last case sources
`src/spawn/tmux_spawn.sh` directly and calls the real `_start_worker_logger` with a
non-existent session name (`worker_logger.sh` itself exits immediately and harmlessly on a
missing session, via its own pre-existing `tmux has-session` check) — proving the actual
spawn/revive trigger sweeps a pre-existing stale file in the same call that writes the new
one, not just the CLI path. All 12 checks pass, a few seconds, one `mktemp -d`.

`dev/worker_wait/test_worker_wait.sh` (22 checks, unrelated to this change except for its
`TRACE_FILE` default) was re-run in full after the path edits, to confirm nothing in that
suite silently started reading the old, now-unwritten `Meta/blank` path. All pass.

## Real-path verification and cleanup, in the order the user specified

Moved the defaults, then verified new writes actually land in the new place, then deleted —
not the reverse, since deleting first would have let the next spawn recreate `Meta/blank`
behind the change.

1. Ran `worker-cli sweep-logs` with no directory override — hits the real, now-corrected
   default, `Meta/iterative-dev/src/logs`, no `WORKER_LOGGER_DIR` set. This both confirmed
   the new default resolves correctly outside any test harness AND was the actual cleanup
   mechanism for the 92 pre-existing stale files there (all of them, newest 2026-06-08, were
   already far past 72h — a real, non-synthetic exercise of the sweep, not a fixture).
2. Confirmed `Meta/iterative-dev/src/logs` held only `.gitkeep` and `log_sweep.log`
   afterward.
3. `Meta/blank/src/logs` (333 files) and the `Meta/blank` directory itself were deleted
   outright (`rm -rf`), not routed through `sweep_stale_logs` — that function deliberately
   spares anything under 72h old and anything named `wait_trace.log`, which is the right
   behavior for the new, permanent location but the wrong one for a full retirement: several
   of the 333 files were from the same day as this change, and `Meta/blank`'s own copies of
   `wait_trace.log`/`janitor.log` needed to go too, not be preserved by the exclusion rule
   that only makes sense for the file still being written to. Explicit user authorization
   named both paths and the directory removal directly; nothing was deleted before that
   authorization, and nothing on this host was deleted from outside the repos named.

## Cross-reference

The orchestrator-side trigger for `worker-cli janitor` (session-start, `monitor-cc`
`claude_proxy_start.sh`) is documented in that repo's `timer-loop`/`worker_janitor` areas —
referenced above for context, not touched or duplicated here.
