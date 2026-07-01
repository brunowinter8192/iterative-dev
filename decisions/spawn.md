# Worker Spawning

## Status Quo (IST)

Architecture: one tmux session per worker, named `worker-<project>-<name>`. Project-scoped — workers from different projects never collide.

**Spawning:**
- `spawn_claude_worker()` — creates tmux session with direct command arg (no shell-ready polling), writes prompt to temp file, launches `claude-patched --model <model>` with prompt from file
- `spawn_claude_worker_from_file()` — same but reads prompt from existing file
- Direct command execution: command passed as arg to `tmux new-session` — env vars inherited automatically
- `remain-on-exit on` set atomically via `;` chain — pane stays open after process exit for status detection
- `history-limit 50000` set at spawn and revive — ensures the prompt anchor (`❯ <non-whitespace>`) stays in scrollback even after a long worker turn
- After Claude exits: `touch /tmp/worker-<name>.done` (semicolon-chained, fires even on crash)

**Viewer:**
- `open_tmux_viewer()` — opens Ghostty window attached to worker's tmux session
- Ghostty 1.3+: native AppleScript API (`new window`, `input text`, `send key`)
- Ghostty 1.2.x: fallback via `open -na` with `--quit-after-last-window-closed` and `--window-save-state=never`

**Orchestration:**
- `worker_list()` — lists active workers with status (working/idle/limit reached/unknown) for current project
- `worker_status()` — returns status of a single worker (working/idle/limit reached/unknown); reads Monitor_CC menubar's `hooks.json` + detects force-stops via `#{window_activity}` stale > 10s
- `worker_capture()` — captures raw pane to `/tmp/worker-<name>-pane.txt`; legacy / `--raw` fallback
- `worker_capture_clean()` — scoped+cleaned capture: slices to output since last real `❯` prompt, applies clean filter (strip: boot box, spinners, diff body, widget chrome; keep: tool headers, counters, prose, Bash output); prints to stdout. Default for `worker-cli capture`.
- `worker_send()` — sends text input to worker's Claude session (tmux send-keys + Enter)

**Cross-project Worktree Tracking (`bin/worker-cli`):**
Registry dir: `${WORKER_REGISTRY_DIR:-$HOME/.claude/.worker-registry}` — env-overridable (test isolation).
- `worker-cli worktree <name> <target-repo> [branch]` — creates `.claude/worktrees/<name>` in target repo on `<branch>` (default `<name>`); validates target is a git repo and worktree doesn't already exist (fails non-zero); appends `<target-repo>\t<branch>` to `$REGISTRY_DIR/<name>.worktrees` (sidecar); echoes the absolute worktree path.
- `worker-cli kill <name>` (extended) — after spawn-side cleanup, reads `$REGISTRY_DIR/<name>.worktrees` line-by-line; for each entry: `git worktree remove --force` + `git branch -D` in the target repo (both best-effort: `2>/dev/null || echo not-found`); deletes the sidecar file. `registry_delete` always executes regardless of sidecar results.
- `worker-cli worktree-rm <target-repo> <name> [branch]` — removes cross-project worktree + branch directly (best-effort); for orphans predating sidecar registration.
- `list` / `status --all` — skip `*.worktrees` files in registry dir loop; only plain-name files are treated as worker entries.

Sidecar format: `$REGISTRY_DIR/<name>.worktrees`, one `<abs-target-path>\t<branch>` per line (tab-separated). Multiple cross-project worktrees for one worker = multiple lines.

**`worker-cli capture` (IST):** defaults to `worker_capture_clean` (clean+scoped output to stdout). `--raw` falls back to `worker_capture` (raw pane to file, prints path). Implemented in `_capture_clean.py` (`src/spawn/`), called from `worker_capture_clean()` in `tmux_spawn.sh`.

**Status Detection (IST):**
Single authoritative source: `~/Library/Application Support/com.brunowinter.monitor-cc-menubar/hooks.json`.
Schema: `{ "<session_id>": { "status": "working"|"idle", ... } }` — written by Monitor_CC lifecycle hooks.
`_worker_detect_status` logic:
- **limit reached** — local process checks: `pane_dead=1`, OR no child PIDs under pane PID, OR no `claude` descendant (process gone: context-limit death, crash, quit); OR hook status `working` BUT `#{window_activity}` stale (> 10s) — forcefully stopped (ESC / crash / context-limit with alive process). Mirrors Monitor_CC menubar `discover.py:178-181`.
- **working** — hook status `working` AND tmux `#{window_activity}` fresh (≤ 10s)
- **idle** — hook status `idle` (Stop hook fired — normal finish)
- **unknown** — honest: hooks.json missing, no entry for session_id, no JSONL yet, or pane unreadable
Fail-open: `#{window_activity}` unreadable → no demote (status stays `working`). All paths return exit 0 (verdict, not error).

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
- Session end: `dev_sync` MCP tool updates main/master ref to dev HEAD via `git update-ref` (no checkout needed — avoids beads-worktree conflict).

**`claude-patched` (MANDATORY):**
- Workers ALWAYS use `claude-patched` instead of `claude`. The patch fixes cache behavior (Cache Read instead of Cache Create per turn), preventing massive usage spikes.

**Files:** `src/spawn/tmux_spawn.sh` (788 LOC), `src/spawn/_capture_clean.py` (153 LOC)

## Recommendation (SOLL)

**Shell-Ready Detection:** Keep (implemented) — Direct command arg to `tmux new-session`. Env vars inherited automatically (verified in dev/spawn/test_direct_command.sh). Polling loop eliminated.

**Worker Status Detection:** Keep (implemented) — reads Monitor_CC's `hooks.json` + detects force-stops via `#{window_activity}` stale > 10s. Three states + unknown: `limit reached` for all abnormally/forcefully stopped workers (pane_dead, no claude child, stale window_activity); `idle` for normal Stop-hook finish; `working` for active CC. `unknown` when no authoritative data. `remain-on-exit on` keeps pane open for detection. See `OldThemes/worker_force_stop_detection.md`.

**Worker → Main Notification:** Pending — blockiert durch fehlendes `claude inject`. Kein Workaround möglich. `.done` File bleibt als manuelles Signal. Automatische Notification erst wenn #24947 implementiert ist.

## Offene Fragen

- `claude inject` Timeline: Issue ist high-priority aber ohne ETA. Regelmäßig prüfen.

## Evidenz

- Live repro 2026-06-19 (`status-demo`, ESC-interrupted, full context, claude alive): hooks.json=`working`, `#{window_activity}` age 384s→975s (≫10s) → pre-fix `worker-cli status` = `working`, menubar = `idle` (diverged); post-fix = `limit reached`. Detail: `OldThemes/worker_force_stop_detection.md`.
- agent-of-empires: Shell-Ready Pattern + Status Detection
- cmux: Community-Validierung tmux+worktree Pattern
- recon: tmux-native Status Monitoring
- claude-tmux: capture-pane Status Detection
- #24947, #15553: Upstream-Blocker für Worker→Main
