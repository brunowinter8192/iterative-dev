# Main session 2026-09-25 (afternoon): test viewer windows and the proxy live copy

Orchestrator record from a Main session that ran in the websearch repo. Worker entries of this area dated 2026-09-25 hold the details.

## Test viewer windows (observed)

On 2026-09-25, 14 Ghostty windows stayed open, titled `tmux attach -t worker-e2e_project_mstestnomodel<pid>-mstestnomodel<pid>; exit` and the `mstestexplicit` equivalent, each showing `can't find session`. Seven distinct pids, two windows each, all from runs of `dev/model_selector/verify_worker_model_precedence.sh`, whose e2e strands spawn through the real `worker-cli spawn` and kill the session about one second later. The windows were closed via System Events (`click` on the AXCloseButton of every window whose name starts with `tmux attach -t worker-e2e_project`; iterate one window at a time, because the window list shifts while closing). `WORKER_NO_VIEWER` now suppresses the viewer for test spawns.

## Proxy live copy owned by monitor-cc

`src/spawn/worker_proxy.sh` no longer copies monitor-cc's proxy itself; it calls monitor-cc `src/copy_proxy_live.sh` found via marker line 3. Before this change a monitor-cc layout change broke every worker spawn (details in the monitor-cc area refactoring). A missing or non-executable copy script aborts the spawn with an error.

## Publishing while another session works in the repo

`plugin-publish` refuses a dirty tree. When another session holds uncommitted changes in the main checkout, publish from a clean worktree of the branch to go live (`git worktree add --detach <dir> integration`, then `plugin-publish --no-push` inside it). Publishing makes every commit on that branch live, including the other session's.
