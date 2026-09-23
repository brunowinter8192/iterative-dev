# dev/worker_message_delivery/

## Role

Live-CC probe for text delivery into a worker tmux pane (`src/spawn/tmux_spawn.sh`'s `worker_send` and the `spawn_claude_worker` prompt inject) — verifies bracketed-paste (`tmux paste-buffer -p`) delivers and submits complete messages on Claude Code 2.1.280, and measures paste-to-render latency against the fixed pre-Enter sleep. Runs a real `claude-280` binary (not mocked) — the bug this guards against is TUI-level paste parsing, not reproducible with a dummy command.

## Public Interface

Each script is run manually, no importable interface: `bash dev/worker_message_delivery/probe_bracketed_paste.sh`.

## Flow

No shared input — the script generates its own test messages, boots throwaway `claude-280` sessions in scratch git dirs, delivers each message through the real `worker_send()` (sourced from `src/spawn/tmux_spawn.sh`), reads the worker's own session JSONL to verify complete/correct delivery, then writes a report to `md/`.

## Modules

### probe_bracketed_paste.sh (314 LOC)

**Purpose:** Verifies bracketed-paste delivery across four message sizes plus one contrasting run of the pre-fix (no `-p`) method; measures paste-render latency.
**Reads:** `src/spawn/tmux_spawn.sh` (sourced for the real `worker_send`), `~/.local/bin/claude-280`.
**Writes:** stdout; throwaway tmux sessions and scratch git dirs (both removed on exit); `md/probe_bracketed_paste_report.md`.
**Called by:** run manually.
**Calls out:** tmux, git, `~/.local/bin/claude-280`, python3.

---

### _verify_user_message.py (58 LOC)

**Purpose:** Reads a worker session JSONL, extracts the last `type=="user"` entry, strips CC's `<pasted_content>` wrapper, and checks it against the expected message.
**Reads:** JSONL path and expected-message file path (argv).
**Writes:** stdout (key=value diagnostic lines); exit code 0 on exact match, 1 otherwise.
**Called by:** `probe_bracketed_paste.sh` (via subprocess).
**Calls out:** nothing (stdlib only).
