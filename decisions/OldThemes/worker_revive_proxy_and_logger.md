# Worker Revive: Proxy Attachment + Diagnostic Logger Sidecar

**Datum:** 2026-05-25
**Commits:** b48b5bb (feat), 231f206 (path-encoding fix)
**Scope:** `src/spawn/tmux_spawn.sh`, `src/spawn/worker_logger.sh` (NEW), `bin/worker-cli`, `src/logs/` (NEW)

## Problem

`worker-cli revive` setzte beim Reanimieren keinen Worker-spezifischen mitmproxy auf. Folge:
- Reanimierte Worker hingen direkt an api.anthropic.com (ohne Monitor_CC Proxy-Addon)
- Proxy-injected Rules fehlten in den Worker-Requests
- Cache-Prefix-Hash gegenüber Anthropic änderte sich (Prefix enthält die injected Rules)
- **Anthropic sah Cache-Miss → vollständiger Re-Upload der gesamten Konversations-History bei jedem Revive**

Plus: zwei aufeinanderfolgende Worker-Deaths in der Session (status 143 = SIGTERM) ohne erkennbare Ursache. Ohne forensische Daten kein Diagnose-Pfad bei zukünftigen Vorfällen.

## Lösung — drei zusammenhängende Bausteine

### 1. Refactor: `_worker_proxy_setup` Helper extrahiert

Proxy-Setup-Block aus `spawn_claude_worker` (Zeilen 378-435 alt) in standalone Funktion. Schreibt Globals `WORKER_PROXY_PID`, `WORKER_PROXY_ENV_PREFIX`, `WORKER_PROXY_LIVE_ADDON`, `WORKER_PROXY_LIVE_DIR`. Return 0 immer (auch no-proxy-active), 1 nur bei Dedup-Error.

`spawn_claude_worker` ruft den Helper, übernimmt Globals in lokale Vars (rückwärts-kompatibel zur alten Heredoc-Variable-Interpolation).

### 2. Neue Funktion `worker_revive` in `tmux_spawn.sh`

Aus `bin/worker-cli` ausgelagert. 4 Gates (tmux-session exists, pane_dead=1, worktree exists, JSONL exists), env-vars aus alter Session retten (WORKER_MODEL, WORKER_PURPOSE, WORKER_PARENT), alte session killen, **`_worker_proxy_setup` aufrufen**, Runner-Script mit `proxy_env_prefix` bauen, neue tmux-session starten, env-vars + pane-died-hook restoren, viewer öffnen.

`bin/worker-cli revive`-Handler reduziert auf einen Delegate-Call: `bash -c "source $SPAWN && worker_revive $NAME $PROJECT"`.

### 3. Diagnostic Logger Sidecar — `worker_logger.sh`

Background-Daemon spawned in `_start_worker_logger` (von spawn UND revive aufgerufen). Sampling alle 10s:
- `tmux display-message "#{pane_dead}"` — death-detection
- claude.exe PID via pane-pid descendants walk
- claude.exe RSS via `ps -o rss=`
- Total system RSS via `ps -axo rss=`
- JSONL last-write-age via `stat -f %m`

Output: `src/logs/<worker>_<timestamp>_<event>.log` (event = "spawn" oder "revive"), eine Sample-Zeile pro 10s.

Bei detected `pane_dead=1`: `_capture_death` schreibt forensik-snapshot `<...>_DEATH.txt` mit:
- tmux pane state (`pane_dead_status`, `pane_dead_signal`, `pane_pid`)
- voller `ps -axo pid,ppid,user,rss,etime,command | sort -k4 -rn | head -50`
- `vm_stat`
- letzte 30 Zeilen `~/.oom-watchdog.log`
- letzte 30 Zeilen `/tmp/menubar-abort.log`
- letzte 20 Einträge aus Worker-Session-JSONL
- letzte 30 Samples des Loggers selbst

Lifecycle:
- `worker_spawn` → `_start_worker_logger "$name" "$session" "spawn"`
- `worker_revive` → `_start_worker_logger "$name" "$session" "revive"`
- `worker-cli kill` → `_stop_worker_logger` vor `tmux kill-session` (sonst spurious DEATH-snapshot)

PID-File `/tmp/worker-logger-<name>.pid`. Logger trapt SIGTERM und entfernt PID-File beim cleanup.

Log-Dir default `$HOME/Documents/ai/Meta/blank/src/logs` (user-specific, override via `WORKER_LOGGER_DIR`).

### 4. Pfad-Encoding-Bug (Commit 231f206)

Erste Revive-Implementation nutzte `sed 's|/|-|g'` für encoded_dir-Lookup unter `~/.claude/projects/`. Claude Code's Encoding ersetzt aber zusätzlich `.` und `_` durch `-`. Worktree-Pfad `.claude/worktrees/eval-sweep` encoded `--claude-worktrees-eval-sweep`, nicht `-.claude-worktrees-eval-sweep`. Fix: drei Shell-Parameter-Expansions `${p//\//-}; ${p//\./-}; ${p//_/-}` analog zur `encode_worktree_path` Funktion in `bin/worker-cli`.

## Evidenz

- **Smoke-Test der neuen Revive-Logik (2026-05-25 19:48):** Worker `eval-sweep` reanimiert nach Death. claude.exe PID 2022 hat sofort `HTTPS_PROXY=http://localhost:8082` gesetzt (via `ps -E` verified), Worker-spezifische mitmproxy PID 2013 auf Port 8082 mit `_worker_eval-sweep` Live-Addon-Datei sichtbar. State-File-Lookup für JSONL hat session-ID `5eb09390-f67a-44c3-a707-66f8030eb5c8` korrekt zurückgegeben. `claude --resume` hat den Kontext geladen ohne Cache-Miss.
- **Logger captured DEATH event sauber:** beim zweiten Death (2026-05-25 19:31:14) hat `worker_logger.sh` `pane_dead` 0→1 Transition detektiert, Death-Snapshot mit komplettem Process-Tree + vm_stat + Watchdog/Menubar-Logs + JSONL-Tail geschrieben. Datei: `src/logs/eval-sweep_20260525_192702_revive_DEATH.txt`. Snapshot war essentiell für die anschließende Root-Cause-Analyse (siehe RAG-Projekt OldThemes/server_stop_self_kill_bug.md).

## Folgen

- Reanimation kostet Anthropic-Cache nicht mehr (Proxy-Prefix bleibt stabil)
- Worker-Deaths werden ab jetzt automatisch dokumentiert; nächste Death-Diagnose ohne Live-Debugging möglich
- Code-Duplikation zwischen spawn und revive eliminiert (gemeinsame Helper)

## Quellen

- Diff-Reviews: commits b48b5bb (Haupt-Feature), 231f206 (Path-Encoding-Fix)
- Cross-Projekt: `decisions/OldThemes/server_stop_self_kill_bug.md (Monitor_CC RAG)` — Death-Snapshots aus diesem Logger waren primäres Beweismittel für die Bug-Identifikation
