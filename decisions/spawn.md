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
- `worker_list()` — lists active workers with status (working/idle/exited/unknown) for current project
- `worker_status()` — returns status of a single worker (working/idle/exited/unknown); reads Monitor_CC menubar's `hooks.json` + applies the `#{window_activity}` demote (normalizes the internal `idle-demoted` sentinel to `idle`)
- `worker_capture()` — captures raw pane to `/tmp/worker-<name>-pane.txt`; legacy / `--raw` fallback
- `worker_capture_clean()` — scoped+cleaned capture: slices to output since last real `❯` prompt, applies clean filter (strip: boot box, spinners, diff body, widget chrome; keep: tool headers, counters, prose, Bash output); prints to stdout. Default for `worker-cli capture`.
- `worker_send()` — sends text input to worker's Claude session (tmux send-keys + Enter)

**`worker-cli capture` (IST):** defaults to `worker_capture_clean` (clean+scoped output to stdout). `--raw` falls back to `worker_capture` (raw pane to file, prints path). Implemented in `_capture_clean.py` (`src/spawn/`), called from `worker_capture_clean()` in `tmux_spawn.sh`.

**Status Detection (IST):**
Single authoritative source: `~/Library/Application Support/com.brunowinter.monitor-cc-menubar/hooks.json`.
Schema: `{ "<session_id>": { "status": "working"|"idle", ... } }` — written by Monitor_CC lifecycle hooks.
`_worker_detect_status` logic:
- **exited** — local process checks: `pane_dead=1`, OR no child PIDs under pane PID, OR no `claude` descendant
- **working** — hook status `working` AND tmux `#{window_activity}` fresh (≤ 10s)
- **idle** — hook status `idle` (Stop hook fired — normal finish)
- **idle-demoted** (internal sentinel) — hook status `working` BUT `#{window_activity}` stale (> 10s): forcefully stopped (ESC / crash / context-limit with alive process). Mirrors Monitor_CC menubar `discover.py:178-181`. Display callers (`worker_status`, `worker_list`) normalize `idle-demoted`→`idle`; `context_pct` reads it raw to suppress the %.
- **unknown** — honest: hooks.json missing, no entry for session_id, no JSONL yet, or pane unreadable
Fail-open: `#{window_activity}` unreadable → no demote (status stays `working`). All paths return exit 0 (verdict, not error).

**Context-% (`context_pct`, `bin/worker-cli`):** context-used = `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` of the last usage entry (true occupied context — cache_read-only undercounted turn-1, where the input sits in cache_creation, → false 100%). `pct = 100*(170000-used)/170000`, clamp ≥ 0. Output: `—%` for exited/unknown/no-usage; empty (suppressed, NOT `—%`) for `idle-demoted`; `<pct>%` otherwise.

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

**Files:** `src/spawn/tmux_spawn.sh` (788 LOC), `src/spawn/_capture_clean.py` (148 LOC)

## Recommendation (SOLL)

**Shell-Ready Detection:** Keep (implemented) — Direct command arg to `tmux new-session`. Env vars inherited automatically (verified in dev/spawn/test_direct_command.sh). Polling loop eliminated.

**Worker Status Detection:** Implemented — reads Monitor_CC's `hooks.json` (hyphen bundle-id path) AND demotes `working`→`idle-demoted` when tmux `#{window_activity}` is stale > 10s, mirroring the menubar (`discover.py:178-181`). This REVERSES the prior "no demote / verbatim" decision: the kill-while-working guard requires a forcefully-stopped worker (ESC / context-limit, CC alive, Stop never fired) to resolve to idle so it can be killed. The drift that motivated the earlier thin-client redesign was the hooks.json **path** (stable, unchanged here); the demote's only added signal is the rename-proof tmux `#{window_activity}`. `exited` from local pane/process checks; `unknown` when no authoritative data; `remain-on-exit on` keeps pane open for `exited` detection. See `OldThemes/worker_force_stop_detection.md`.

**Worker → Main Notification:** Pending — blockiert durch fehlendes `claude inject`. Kein Workaround möglich. `.done` File bleibt als manuelles Signal. Automatische Notification erst wenn #24947 implementiert ist.

## Offene Fragen

- `claude inject` Timeline: Issue ist high-priority aber ohne ETA. Regelmäßig prüfen.

## Evidenz

- Live repro 2026-06-19 (`status-demo`, ESC-interrupted, full context, claude alive): hooks.json=`working`, `#{window_activity}` age 384s→975s (≫10s) → pre-fix `worker-cli status` = `working`, menubar = `idle` (diverged); post-fix = `idle`. `context_pct`: status-demo last usage `{input:3, cache_read:0, cache_creation:19452}` → cache_read-only formula gave 100%, summed formula gives 88%. Post-publish verification: `status-demo`→`idle` (no %), `status-fix` (normal idle)→`idle 59%` (with %). Detail: `OldThemes/worker_force_stop_detection.md`.
- agent-of-empires: Shell-Ready Pattern + Status Detection
- cmux: Community-Validierung tmux+worktree Pattern
- recon: tmux-native Status Monitoring
- claude-tmux: capture-pane Status Detection
- #24947, #15553: Upstream-Blocker für Worker→Main
