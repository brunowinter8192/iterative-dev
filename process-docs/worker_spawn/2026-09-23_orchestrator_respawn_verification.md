# Same-name respawn: production verification (orchestrator, 2026-09-23)

The fix for a same-name respawn losing its proxy (unique live addon path per spawn, abort when the
proxy does not come up) is described in the worker's own entry of this area. This entry records the
production check the orchestrator ran after merge.

Deployment on 2026-09-23: `src/spawn/tmux_spawn.sh` and `bin/gcommit` were copied from the integration
branch into the plugin cache (`iterative-dev/1.0.0`). Before the copy both cache files were
byte-identical to the integration state before this fix, so the copy changed exactly this fix.

Check: a throwaway worker `rsp` in the canvas project, prompt "Reply with only the word OK". Spawned,
waited for idle, then three rounds of `worker-cli kill rsp` immediately followed by
`worker-cli spawn rsp` with no pause. In every round: exactly one mitmdump process for the worker was
running 12 s after spawn, the worker answered "OK" and went idle, and its proxy error log was empty
(0 bytes). Before the fix the same sequence on 2026-09-23 produced
`mitmdump: No such script: .../.proxy_addon_live_worker_statusbar.py` and a worker looping on
ECONNREFUSED that the monitor-cc kill guard refused to kill.

The kill guard (`block_worker_kill_while_working` in monitor-cc) was left unchanged. The stuck
"working" state was a consequence of the missing proxy, not a guard defect.

gcommit check on 2026-09-23 with the copied `bin/gcommit`: `gcommit "<msg>" .` from inside a scratch
repo under /tmp committed into that scratch repo; the plugin cache HEAD stayed at 0204e35.
`gcommit "<msg>" <plugin dir>` was refused with exit 1.
