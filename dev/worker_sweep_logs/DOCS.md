# dev/worker_sweep_logs/

## Role

Smoke test for `worker-cli sweep-logs` (`bin/worker-cli`, `sweep-logs` case; implementation
`sweep_stale_logs` in `src/spawn/tmux_spawn.sh`) — the log-DIRECTORY retention sweep. Distinct
from `worker-cli janitor` (`dev/worker_janitor/`), which sweeps stale tmux WORKER SESSIONS —
the two share no code, no log file, and no naming.

## Modules

### test_sweep_logs.sh

**Purpose:** Exercise the real `worker-cli sweep-logs` binary, and the real
`_start_worker_logger` auto-trigger, against a throwaway `WORKER_LOGGER_DIR`. Covers:
`--dry-run` listing a stale file without deleting it; a real run deleting a stale file while
sparing a fresh one, with a matching `log_sweep.log` line; `wait_trace.log` surviving even
`--max-age-hours 0` (it has its own line-count self-trim instead, see
`process-docs/worker_sweep_logs/`); the default threshold being 72h specifically (a 71h file
spared, a 73h file removed in the same run, no `--max-age-hours` passed); and a real
`_start_worker_logger` call sweeping a pre-existing stale file in the same directory it then
writes its own new log into — the actual spawn/revive trigger path, not just the CLI.

**Ages are faked, not waited for:** `touch -t` with the `date -v-<N>H` (macOS) /
`date -d "-<N> hours"` (GNU) fallback, same idiom as `dev/worker_janitor/test_janitor.sh`'s
own age-faking for `session_created`.

**Usage:** `bash dev/worker_sweep_logs/test_sweep_logs.sh` (a few seconds; all I/O confined to
one `mktemp -d`, torn down via `trap ... EXIT`. Never touches the real log directory).
