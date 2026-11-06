# Workers spawned for a project without a proxy marker ran unproxied and forked (2026-11-06)

## Incident
Seven workers `dev-batch-1..7` in project `BOM1-worker` were spawned from the BOM1 orchestrator with
`PROXY_PROJECT_PATH=<BOM1-worker> worker-cli spawn ...`. Their UI showed several `fork ...` subagent entries, although
the monitor-cc proxy removes the `Agent` tool. No dual-log existed for them.

## Cause (confirmed)
- `_worker_proxy_setup` looked up only `/tmp/.monitor_cc_proxy_<md5(worker project root)>`. The only proxy ran for
  `BOM1` (`1880bce1`); the marker for `BOM1-worker` (`f9f47035`) did not exist.
- A missing marker was a silent `return 0`: no proxy, no error. The worker `claude.exe` processes had no `HTTPS_PROXY`,
  and only two `mitmdump` processes (the orchestrators') were running.
- Without the proxy nothing strips `Agent`, so the workers could start fork subagents.
- The orchestrator's own environment still carried `PROXY_SESSION_ID=1880bce1` (exported by monitor-cc's
  `claude_proxy_start.sh`); only `PROXY_PROJECT_PATH` had been overridden for the spawn.

## Fix
- Marker order: worker project marker, else `/tmp/.monitor_cc_proxy_$PROXY_SESSION_ID`. The worker proxy still gets the
  worker project as `PROXY_PROJECT_PATH`; the log id carries the session id of the marker that was used.
- `PROXY_SESSION_ID` set but no marker found: error and return 1 (spawn and revive abort, no tmux session). No proxy
  context at all (variable unset, no project marker): unchanged, the worker starts without proxy.
- Independent of the proxy, every spawn and revive runner starts claude with `CLAUDE_CODE_FORK_SUBAGENT=0` and
  `--disallowedTools Agent`. In Claude Code 2.1.280 forks are a mode of the `Agent` tool (`Task` is its old alias), and the
  binary reads `CLAUDE_CODE_FORK_SUBAGENT=false` as "disabled". Not verified against a live API request.
- `dev/strand_runner.sh` unsets `PROXY_SESSION_ID` per strand so that a test started from a proxied session stays hermetic.

## Not covered
- Skills with `context: fork` also fork; none exist in the BOM1-worker skills. `SendMessage` is not blocked.
- Running workers keep their old environment. `worker-cli revive` rebuilds the runner with the new rules; a plain
  respawn does too. The plugin cache clone must be synced before `worker-cli` picks the change up.

## Tests
`dev/worker_spawn/test_worker_proxy_routing.sh` (5 strands) passes; against the old `worker_proxy.sh` the session-marker
fallback and the strict refusal strands fail. `render_runner_flags.sh` asserts the fork block in spawn, spawn-file and revive.
