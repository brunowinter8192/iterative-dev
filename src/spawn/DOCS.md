# src/spawn/

## Role

Worker spawning and orchestration — tmux sessions, git worktrees, Ghostty viewers, proxy injection. Touch this package when changing how workers are spawned, how worktrees are set up, or how the proxy is injected into worker environments.

## Public Interface

Sourced by `~/.local/bin/worker-cli` (all subcommands):
- `tmux_spawn.sh` — bash library for worker lifecycle ops

Invoked via `python3 -m src.spawn.spawn` by `worker-cli spawn`:
- `spawn.py` — worktree setup + tmux session launch (stdlib only)

## Modules

### tmux_spawn.sh (728 LOC)

**Purpose:** Bash library — worker lifecycle: spawn, list, status, capture, send. Handles proxy injection for Monitor_CC sessions automatically when `/tmp/.monitor_cc_proxy_*` marker exists.
**Reads:** tmux session list, proxy marker `/tmp/.monitor_cc_proxy_<session_id>`, project path, `~/Library/Application Support/com.brunowinter.monitor-cc-menubar/hooks.json` (working/idle source).
**Writes:** tmux sessions, Ghostty windows, worker mitmproxy processes, `/tmp/worker-<name>.done` signal file.
**Called by:** `~/.local/bin/worker-cli` (all subcommands via `source`); `spawn.py` (via subprocess for `spawn_claude_worker_from_file`).
**Calls out:** tmux, osascript/Ghostty, mitmdump, `~/.local/bin/claude-114`.

**Status detection (`_worker_detect_status`):** Thin client — `exited` from local pane/process checks (`pane_dead`, child PIDs, `claude` descendant); `working`/`idle` verbatim from `hooks.json[session_id].status`; `unknown` if no authoritative data (missing file, no entry, no JSONL). No `window_activity` demote. All paths return exit 0.

**spawn_claude_worker — Prompt-Inject Flow:**
claude starts bare (no positional prompt arg — prompt never touches the cmdline).
After session creation, a readiness gate polls `tmux capture-pane` for `^❯`
(U+276F at col 0 = CC input-ready). 30s deadline; timeout → `return 1`.
Prompt is injected via `load-buffer / paste-buffer / send-keys Enter` (same
as `worker_send`). Fragility: `^❯` marker is CC-version-dependent — if the
glyph changes, gate times out and spawn fails explicitly; update the grep
pattern. See `decisions/OldThemes/worker_spawn_prompt_injection.md`.

### spawn.py (117 LOC)

**Purpose:** Worktree setup + worker session launch. Stdlib only — no fastmcp, no external deps.
**Reads:** prompt file, project dir (`.claude/settings.local.json`, `venv/`).
**Writes:** git worktree at `.claude/worktrees/<name>`, copies `settings.local.json`, symlinks `venv/`, then calls `spawn_claude_worker_from_file` via bash subprocess.
**Called by:** `~/.local/bin/worker-cli spawn` (via `cd "$PLUGIN" && python3 -m src.spawn.spawn`).
**Calls out:** git (via subprocess), bash + tmux_spawn.sh (via subprocess).

## Usage

```bash
# Via worker-cli (standard)
worker-cli spawn <name> <prompt_file> <project_path> [model] [--no-worktree]

# Direct (from plugin root)
python3 -m src.spawn.spawn <name> <prompt_file> <project_path> [model] [--no-worktree]
```

## Gotchas

- `spawn.py` derives `PLUGIN_DIR` from `__file__` — call `python3 -m` from any cwd, `TMUX_SPAWN_SH` resolves correctly.
- `worker-cli spawn` converts relative paths to absolute before `cd "$PLUGIN"` to avoid path drift.
- Proxy injection: `spawn_claude_worker` reads `/tmp/.monitor_cc_proxy_<md5(project_path)>`. If marker absent → worker spawns without proxy (silent, no error).
