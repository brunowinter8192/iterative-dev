# Worker Spawning

## Status Quo (IST)

Architecture: one tmux session per worker, named `worker-<project>-<name>`. Project-scoped — workers from different projects never collide.

**Spawning:**
- `spawn_claude_worker()` — creates tmux session, waits for shell ready (marker-based, 10s timeout), writes prompt to temp file, launches `claude --model <model>` with prompt from file
- `spawn_claude_worker_from_file()` — same but reads prompt from existing file
- Shell ready detection: sends echo marker, polls capture-pane for marker string (0.3s intervals)
- After Claude exits: `touch /tmp/worker-<name>.done` (semicolon-chained, fires even on crash)

**Viewer:**
- `open_tmux_viewer()` — opens Ghostty window attached to worker's tmux session
- Ghostty 1.3+: native AppleScript API (`new window`, `input text`, `send key`)
- Ghostty 1.2.x: fallback via `open -na` with `--quit-after-last-window-closed` and `--window-save-state=never`

**Orchestration:**
- `worker_list()` — lists active workers for current project (filters by project prefix)
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

**File:** `src/spawn/tmux_spawn.sh` (229 lines)

## Recommendation (SOLL)

**Shell-Ready Detection:** Change — Polling eliminieren. Command direkt als Argument an `tmux new-session` übergeben statt `send-keys` nach Shell-Ready-Polling. Pattern von agent-of-empires (1.2k ⭐). Muss getestet werden ob Env-Vars (GH_TOKEN, PATH) ohne Login-Shell verfügbar sind.

**Worker Status Detection:** Change — `worker_status()` Funktion mit tmux-nativer Detection: `#{pane_dead}` (Prozess beendet) + `#{pane_current_command}` (Shell = Agent fertig). Pattern von agent-of-empires. `worker_list()` erweitern um Status pro Worker.

**Worker → Main Notification:** Pending — blockiert durch fehlendes `claude inject`. Kein Workaround möglich. `.done` File bleibt als manuelles Signal. Automatische Notification erst wenn #24947 implementiert ist.

## Offene Fragen

- Env-Passthrough bei `tmux new-session` mit direktem Command: Ist GH_TOKEN verfügbar ohne Login-Shell? → dev/spawn/ Test nötig.
- `claude inject` Timeline: Issue ist high-priority aber ohne ETA. Regelmäßig prüfen.
- `remain-on-exit on` (tmux Option): Soll die Pane nach Worker-Exit offen bleiben für Output-Lesen? agent-of-empires nutzt das.

## Evidenz

Siehe sources/sources.md — Spalte "Decision: spawn":
- agent-of-empires: Shell-Ready Pattern + Status Detection
- cmux: Community-Validierung tmux+worktree Pattern
- recon: tmux-native Status Monitoring
- claude-tmux: capture-pane Status Detection
- #24947, #15553: Upstream-Blocker für Worker→Main
