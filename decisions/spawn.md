# Worker Spawning

## Status Quo (IST)

Architecture: one tmux session per worker, named `worker-<project>-<name>`. Project-scoped — workers from different projects never collide.

**Spawning:**
- `spawn_claude_worker()` — creates tmux session with direct command arg (no shell-ready polling), writes prompt to temp file, launches `claude-patched --model <model>` with prompt from file
- `spawn_claude_worker_from_file()` — same but reads prompt from existing file
- Direct command execution: command passed as arg to `tmux new-session` — env vars inherited automatically
- `remain-on-exit on` set atomically via `;` chain — pane stays open after process exit for status detection
- After Claude exits: `touch /tmp/worker-<name>.done` (semicolon-chained, fires even on crash)

**Viewer:**
- `open_tmux_viewer()` — opens Ghostty window attached to worker's tmux session
- Ghostty 1.3+: native AppleScript API (`new window`, `input text`, `send key`)
- Ghostty 1.2.x: fallback via `open -na` with `--quit-after-last-window-closed` and `--window-save-state=never`

**Orchestration:**
- `worker_list()` — lists active workers with status (running/exited) for current project
- `worker_status()` — returns status of a single worker via `#{pane_dead}` query
- `worker_capture()` — captures pane content to `/tmp/worker-<name>-pane.txt` (configurable scrollback lines)
- `worker_send()` — sends text input to worker's Claude session (tmux send-keys + Enter)

**Signal:**
- `.done` file written on Claude exit for manual checking (`ls /tmp/worker-*.done`)
- No automatic notification to parent session (PostToolUse hook removed — overhead without value)

**Communication — Main → Worker:**
- Main spawnt Worker mit Task-Prompt (CLI argument oder Prompt-File)
- `worker_send()` kann Text an laufenden Worker schicken (tmux send-keys)
- Funktioniert NUR wenn Worker auf User-Input wartet (Claude Code idle)
- Einschränkung: tmux send-keys schickt Keystrokes, Claude Code erkennt es als User-Input — funktioniert in der Praxis

**Communication — Worker → Main: NICHT MÖGLICH**
- Kein Mechanismus um dem Parent-Agent programmatisch mitzuteilen dass der Worker fertig ist
- `.done` File existiert, aber kein automatischer Consumer im Parent
- PostToolUse Hook (worker-done-check.sh) wurde entfernt — Overhead bei jedem Tool-Call ohne Nutzen
- `claude inject` (anthropics/claude-code#24947) würde das lösen: programmatischer Input an laufende Session. OPEN, high-priority, kein Implementierungszeitplan.
- Programmatic Input Submission (#15553) bestätigt: Claude Code ignoriert programmatischen stdin als Submit
- Community-Konsens (Reddit, GitHub): Niemand hat einen funktionierenden Workaround. Alle warten auf `claude inject`.

**Dev-Branch Workflow:**
- Opus works on `dev` branch during IMPLEMENT. Workers branch from `dev` (worktrees at `.claude/worktrees/<name>/`).
- `worker_merge` merges worker branch into whatever branch is currently checked out (dynamic via `git rev-parse --abbrev-ref HEAD`). No hardcoded `main`.
- Opus reviews on `dev` — shared-rules use `.claude/worktrees/**` paths, so reading files on `dev` (normal project path) does NOT trigger execution rules.
- Session end: `git checkout main && git merge dev` (fast-forward sync).

**`claude-patched` (MANDATORY):**
- Workers ALWAYS use `claude-patched` instead of `claude`. The patch fixes cache behavior (Cache Read instead of Cache Create per turn), preventing massive usage spikes.

**File:** `src/spawn/tmux_spawn.sh` (245 lines)

## Recommendation (SOLL)

**Shell-Ready Detection:** Keep (implemented) — Direct command arg to `tmux new-session`. Env vars inherited automatically (verified in dev/spawn/test_direct_command.sh). Polling loop eliminated.

**Worker Status Detection:** Keep (implemented) — `worker_status()` via `#{pane_dead}` query. `worker_list()` shows status per worker. `remain-on-exit on` keeps pane open after exit (verified in dev/spawn/test_status_detection.sh).

**Worker → Main Notification:** Pending — blockiert durch fehlendes `claude inject`. Kein Workaround möglich. `.done` File bleibt als manuelles Signal. Automatische Notification erst wenn #24947 implementiert ist.

## Offene Fragen

- `claude inject` Timeline: Issue ist high-priority aber ohne ETA. Regelmäßig prüfen.

## Evidenz

Siehe sources/sources.md — Spalte "Decision: spawn":
- agent-of-empires: Shell-Ready Pattern + Status Detection
- cmux: Community-Validierung tmux+worktree Pattern
- recon: tmux-native Status Monitoring
- claude-tmux: capture-pane Status Detection
- #24947, #15553: Upstream-Blocker für Worker→Main
