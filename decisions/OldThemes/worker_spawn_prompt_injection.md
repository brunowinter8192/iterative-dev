# worker_spawn_prompt_injection — Prompt via Paste statt Cmdline-Arg

**Date**: 2026-05-30
**Branch**: infra
**Commit**: 2a024e0
**Files changed**: `src/spawn/tmux_spawn.sh`

---

## Problem

`spawn_claude_worker` übergab den Prompt als Positional-Argument an claude
(Runner-Zeile in Heredoc):

```bash
${worker_claude_bin} --model '${model}' ${extra_flags} "$(cat '${prompt_file}')"
```

Der vollständige Prompt-Text stand damit in der Kommandozeile des
claude-Prozesses — sichtbar via `ps aux`, `pgrep -fa`, und jedem Tool das
Prozess-Cmdlines nach Substring durchsucht. Real-World-Konsequenz: 2x Worker
wurden beim Start gekillt, weil ihr Prompt-Text zufällig einen
Cleanup-Match-String enthielt.

---

## Verworfener Ansatz: JSONL-Poll als Readiness-Gate

**Idee**: Warte nach dem Spawn bis eine neue JSONL-Datei in
`~/.claude/projects/<encoded-worktree>/` erscheint — CC schreibt beim
Session-Start einen `system`-Record, bevor der Prompt erscheint.

**Warum dead-end**: Die Annahme war falsch. CC schreibt **kein JSONL vor
dem ersten User-Prompt**. Eine Session beginnt offiziell erst mit dem ersten
Prompt — davor passiert intern nichts. JSONL-Poll-Gate würde deadlocken:

```
Gate wartet auf JSONL
→ JSONL braucht den Prompt
→ Prompt wartet auf Gate
→ 30s Timeout → KEIN Worker bekommt je seinen Prompt
```

Empirisch bestätigt (Probes 1–3): kein JSONL nach 8s in frischen und
established Projekt-Dirs, solange keine User-Eingabe erfolgte.
User-autoritativ bestätigt.

---

## Empirische Befunde der Probes

### Readiness-Marker

`tmux capture-pane -p` im Input-Ready-State zeigt:
```
❯ 
```
Bytes: `e2 9d af` (U+276F, HEAVY RIGHT-POINTING ANGLE QUOTATION MARK) +
`c2 a0` (U+00A0, NO-BREAK SPACE) + `0a` (newline).

Die Zeile beginnt bei Spalte 0 mit `❯`. `grep -q '^❯'` matcht zuverlässig.

**Unterscheidung Trust-Dialog**: Der Workspace-Trust-Dialog zeigt
` ❯ 1. Yes, I trust this folder` mit führendem Space — kein Match auf `^❯`.

### Trust-Dialog-Verhalten

- **Frische/unbekannte Dirs** (z.B. `/tmp/...`): Trust-Dialog erscheint,
  **auch** mit `--dangerously-skip-permissions` (das Flag suppresst
  Tool-Permission-Prompts, nicht den Workspace-Trust-Dialog).
- **Established Projekt-Dirs** (bekannte Git-Repos): kein Dialog — direkt
  `❯`-Prompt nach ~3-4s Boot-Zeit.
- **Worker-Spawns** (`$project_path` = existierender Repo-Root):
  established, kein Dialog erwartet. Bestätigt durch eigenen sauberen Spawn.

### Early-Paste-Queueing

Bytes die VOR dem `❯`-State in die Pane gepastet werden, werden vom
Terminal-Buffer gehalten und bei CC-Bereitschaft zugestellt. Gemessen:
paste bei T=0.1s, Text erscheint in CC-Inputbox bei T~4s als
`❯ echo QUEUE_TEST`. Die Pane-Gate ist damit kein harter Delivery-Blocker
für den Happy-Path — sie stellt aber sicher, dass Enter erst gesendet wird
wenn CC den Text als Prompt interpretiert.

---

## Fix

### 1. Runner — Prompt-Arg entfernen

```bash
# Vorher (Zeile 545):
${worker_claude_bin} --model '${model}' ${extra_flags} "$(cat '${prompt_file}')"

# Nachher:
${worker_claude_bin} --model '${model}' ${extra_flags}
```

### 2. Readiness-Gate (`^❯`-Poll)

```bash
_pane_id=$(tmux list-panes -t "$session" -F "#{pane_id}" | head -1)
_deadline=$(( $(date +%s) + 30 ))
while [ "$(date +%s)" -lt "$_deadline" ]; do
    tmux capture-pane -p -t "$_pane_id" 2>/dev/null | grep -q '^❯' && break
    sleep 0.3
done
if ! tmux capture-pane -p -t "$_pane_id" 2>/dev/null | grep -q '^❯'; then
    echo "spawn_claude_worker: CC did not reach input-ready state within 30s" >&2
    rm -f "$prompt_file"
    return 1
fi
```

Trust-Dialog trifft `^❯` nicht → Gate läuft in Timeout → expliziter
`return 1` statt stiller Injection in den Dialog.

### 3. Prompt-Inject (identisch worker_send)

```bash
printf '%s' "$task_prompt" | tmux load-buffer -
tmux paste-buffer -d -t "$_pane_id"
sleep 0.2
tmux send-keys -t "$_pane_id" Enter
rm -f "$prompt_file"
```

`prompt_file` wird sowohl bei Erfolg (nach Inject) als auch bei
Gate-Timeout (`return 1`) bereinigt.

### Position im Spawn-Flow

Gate + Inject nach `open_tmux_viewer "$session" ... &` (Ghostty-Launch
läuft im Hintergrund parallel zum Gate-Polling), vor `echo "$session"`.
`_orchestrator_signal_update` bleibt an Zeile 558 — deckt die
Menubar-Grace-Phase während Boot + Gate-Warten.

`spawn_claude_worker_from_file` ist nicht direkt geändert — es liest die
Datei in `$task_prompt` und ruft `spawn_claude_worker` auf; Fix greift
automatisch.

---

## Bekannte Fragilität

**`^❯`-Marker ist CC-versionsabhängig.** Das Glyph U+276F wird in der
CC-TUI als Input-Prompt verwendet — nicht durch eine stabile API garantiert.
Ändert eine CC-Version diesen Glyph:
- Gate-Timeout nach 30s
- `return 1` → expliziter Spawn-Fail (nie stilles Versagen)
- Maßnahme: `grep -q '^❯'` in `tmux_spawn.sh` anpassen auf den neuen Marker
