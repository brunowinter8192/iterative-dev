# Same-name respawn right after kill lost the worker proxy (2026-09-23)

## Incident
`worker-cli kill statusbar` immediately followed by `worker-cli spawn statusbar ...`: the new worker's log said
`mitmdump: No such script: <monitor-cc>/src/logs/.proxy_addon_live_worker_statusbar.py`. The worker then looped on
ECONNREFUSED, counted as working, and the monitor-cc kill guard refused to kill it. Waiting 10 s between kill and
spawn avoided it.

## Cause (confirmed by code reading, not by live reproduction)
- `worker-cli kill` only runs `tmux kill-session`. The runner script's `_cleanup` trap (spawn and revive) fires
  asynchronously: bash defers a trap until the foreground child (claude) has exited, which takes seconds.
- `_cleanup` does `rm -f` on the live addon and `rm -rf` on the live proxy dir. Both paths were derived from the
  worker name alone (`.proxy_addon_live_worker_<name>.py`).
- A new spawn in that window copies a fresh addon to the same path; the old trap then deletes it. The old dedup
  guard (`lsof` on the addon) did not help because nothing had the file open yet.
- Nothing checked that mitmdump actually came up.

## Fix (src/spawn/tmux_spawn.sh, `_worker_proxy_setup`)
- Live-copy id is `worker_<name>_<epoch>_<pid>`; each spawn/revive owns unique paths, so an old trap can only
  delete its own copies. The old dedup guard was removed (unique paths make it moot; ports are picked free).
- New `_worker_proxy_wait_ready PID PORT`: waits up to 15 s until the mitmdump pid is alive and the port listens.
  If not: message with the proxy error log path, mitmdump killed, copies removed, globals cleared, return 1.
  `spawn_claude_worker` and `worker_revive` already do `|| return 1`, so no tmux session is created and no worker
  starts without proxy. Spawn additionally removes its prompt tmp file on that path.
- Only applies when the proxy marker exists; without marker behaviour is unchanged (no proxy, no error).

## Isolated test (/tmp/t_proxy.sh, fake marker + fake MONITOR_CC_ROOT under /tmp/fakemcc)
- Marker `/tmp/.monitor_cc_proxy_<md5(project)[:8]>`: line 1 port, line 3 root. Root has minimal
  `src/proxy_addon.py` and `src/proxy/`.
- 3 rounds: setup A, setup B (same name), then simulate A's late trap (kill A, rm A's addon and dir), check B: addon
  present, pid alive, port listening. Result 3/3 B intact, addon names differ per round.
- Broken addon (not valid python): setup printed the ERROR, returned 1, no stray mitmdump, no leftover live copy
  in logs dir.
- Not tested here: real tmux/claude kill + respawn back to back; the orchestrator verifies this after merge and
  cache sync.

## Notes for successors
- tmux_spawn.sh sets `set -euo pipefail`; when sourcing it in a test script, a failing `_worker_proxy_setup` exits the
  shell unless called with `||`/`if`.
- Old live copies leaked by a SIGKILLed runner are not cleaned up (pre-existing, unobserved as a problem).
  With unique names they now accumulate in monitor-cc `src/logs` instead of being overwritten; hypothesis only.
