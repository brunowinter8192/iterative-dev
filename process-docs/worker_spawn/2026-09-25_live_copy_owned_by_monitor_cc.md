# Worker proxy live copy: monitor-cc owns the layout (2026-09-25, worker mcsrcid)

## What broke

monitor-cc changed the proxy live-copy layout: `.proxy_live_<id>/` now holds `src/{__init__.py,constants.py,monitor_root.py,proxy/}` and the shim `proxy_addon.py` imports `src.proxy.addon` from that directory. `_proxy_launch` in `src/spawn/worker_proxy.sh` still copied `src/proxy` to `.proxy_live_<id>/proxy` itself. The shim raised `FileNotFoundError: proxy package not found`, mitmdump exited during startup, and every worker spawn aborted with `Worker proxy for <name> did not come up on port <port>`. Running sessions were unaffected.

## Change

`_proxy_launch` no longer copies anything. It runs `<monitor_cc_root>/src/copy_proxy_live.sh <live_addon_path> <live_dir_path>`, where `monitor_cc_root` is line 3 of the proxy marker, which `_worker_proxy_setup` already read. If the script is missing or not executable (monitor-cc checkout older than the layout change) or fails, `_proxy_launch` removes its partial live files, prints an error and returns 1, and `_worker_proxy_setup` returns 1 before starting mitmdump. `dev/worker_spawn/test_spawn_flow.sh` stubs `copy_proxy_live.sh` in its fake monitor root.

## Proof

monitor-cc `dev/refactoring/worker_proxy_sandbox.py <iterative-dev tree>` builds a temp monitor root (copy of monitor-cc `src/`), a temp project with a matching marker, a temp `mitmdump` shim on PATH, private ports 18940 (main), 18941 (worker), 18942 (local upstream), and runs the real `_worker_proxy_setup`.

- Tree at iterative-dev `integration` (old copy code): `setup_rc=1`, message `Worker proxy for 'vproxy' did not come up on port 18941`. Reproduces the production symptom.
- Tree of this change: `setup_rc=0`, live dir holds `__init__.py constants.py monitor_root.py proxy`, a POST through the worker proxy is forwarded, five dual-log files appear for `worker_<sid>_vproxy_<ts>`.
- `dev/worker_spawn/test_spawn_flow.sh`: 3 of 3 strands pass.

## Deployment

The running copy under the plugin cache is not touched by this change. Until the plugin is published and the cache refreshed, every new spawn from that cache still fails against a monitor-cc that has the new layout.
