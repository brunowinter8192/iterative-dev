# desktop_targeting: consume menubar cwd_desktop sidecar

**Date:** 2026-05-29  
**Branch:** blank-desktop-targeting  
**Commit:** feat(desktop): consume menubar cwd_desktop sidecar + blank logging

## Problem

`find_caller_main_space()` used a fragile four-step chain to resolve the caller's Mission Control Desktop:

1. `_read_cwd_uuid_map()` — cwd→UUID from `ghostty_cwd_uuid.json`
2. `_ghostty_uuid_to_window_name()` — AppleScript UUID→window-name lookup
3. `_ghostty_pid()` + `_windows_by_name_for_pid()` — CGWindowList name-match against Ghostty PID
4. `_spaces_for_wid()` — CGSCopySpacesForWindows on the matched wid

Failure modes:
- `kCGWindowName` not populated without spinner-normalize → `n_cand=0`
- No SkyLight TCC bypass → AppleScript UUID lookup fails in some sandbox contexts
- Name-match requires `len(wids)==1` — any window-title ambiguity → hard fail

Both call paths (`bin/show`, `tmux_spawn.sh:open_tmux_viewer`) suppressed all output with `>/dev/null 2>&1`, making failures undiagnosable.

## Solution

### Sidecar schema contract

Monitor_CC menubar publishes its verified detection result:

```
Path:  ~/Library/Application Support/com.brunowinter.monitor_cc_menubar/cwd_desktop.json
Shape: {"<cwd>": {"space_id": <int>, "desktop_no": <int>}}
```

Semantics: last-known-good per cwd. Entries are stable — the menubar only writes valid `space_id`s.

### New `find_caller_main_space()` flow

Kept:
- `_find_claude_ancestor(caller_pid)` → `claude_pid`  (parent-PID walk)
- `_cwd_of_pid(claude_pid)` → `cwd`  (lsof cwd fd)

Replaced (entire name-match chain → single JSON lookup):
```python
entry = _read_cwd_desktop_map().get(cwd)
space_id, desktop_no = entry["space_id"], entry["desktop_no"]
```

Fallback (sidecar miss): `CGSGetActiveSpace` as best-effort space_id. Logged with `sidecar=miss:<reason>`.

### Dead code removed

| Symbol | Reason |
|--------|--------|
| `_read_cwd_uuid_map()` | read old UUID map |
| `_ghostty_uuid_to_window_name()` | AppleScript name query |
| `_ghostty_pid()` | Ghostty process search |
| `_windows_by_name_for_pid()` | CGWindowList name-match |
| `_spaces_for_wid()` | CGSCopySpacesForWindows per-wid |
| `_CWD_UUID_FILE` | old constant |
| `_CGS_SPACE_MASK` | only used by `_spaces_for_wid` |
| `_CG.CGSCopySpacesForWindows` binding | same |

### Detect-before-disturb reorder

Previously: open triggered → `wait-and-move` called → `find_caller_main_space` inside.  
Now: `find-caller-desktop` resolves `space_id` **before** the open, then `wait-and-move-space` takes the pre-resolved `space_id`.

New CLI subcommand: `wait-and-move-space <space_id> <owner_name> [timeout] [op]`

**`bin/show`:**
```bash
_space_id=$(python3 "$_DESKTOP_HELPER" find-caller-desktop "$PPID" show 2>/dev/null | cut -d' ' -f1)
open -a "CotEditor" "$f"
python3 "$_DESKTOP_HELPER" wait-and-move-space "$_space_id" "$app_name" 4 show &
```

**`tmux_spawn.sh`** (both spawn + revive call sites):
```bash
_dt_space_id=$(python3 "$_dt_helper" find-caller-desktop "$PPID" spawn 2>/dev/null | cut -d' ' -f1)
open_tmux_viewer "$session" "$_dt_space_id" &
```
`open_tmux_viewer` accepts `$2=space_id`, passes to `wait-and-move-space` internally.

### Blank log sink

Path: `~/Library/Logs/blank/desktop_targeting.log`  
Format: `<ISO-timestamp> op=<op> caller_pid=<n> claude_pid=<n> cwd=<path> sidecar=<hit|miss:reason> space_id=<n>`  
Both call paths log resolution + move outcomes. Silent failures are now diagnosable.

## Open issues (not implemented)

1. **Worker-calling-`show` routing**: When a worker calls `show`, `_find_claude_ancestor` returns the worker's own claude PID. The sidecar entry for the worker's cwd resolves the worker's Desktop, not the parent Main's Desktop. Routing decision (follow worker cwd vs. parent-main cwd) is deferred.

2. **Multi-new-window disambiguation**: `wait_for_new_windows_and_move` moves all new layer-0 windows in the poll window. Concurrent app opens from other sources may be incorrectly moved. Left for a future targeted fix.

## Live-Verify 2026-05-29 — Routing greift nicht (zwei Bugs)

End-to-End-Test (Opus ruft `show <md>` auf, User auf Desktop 1, Caller-Main-Session auf Desktop 2): md öffnete auf Desktop 1 (aktiver Desktop) statt auf 2 (Caller). Routing funktioniert nicht. Zwei getrennte Ursachen.

### Bug 1 — `show` findet seinen Helper nicht (Symlink-Pfad)

`show` ist symlinkt: `~/.local/bin/show → Meta/blank/bin/show`. Das Script leitet `_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` ab — folgt dem Symlink NICHT. Bei Aufruf via PATH ist `$0=~/.local/bin/show`, also `_DESKTOP_HELPER=~/.local/bin/../src/desktop/desktop_targeting.py = ~/.local/src/desktop/desktop_targeting.py` → **existiert nicht** → `[ -f "$_DESKTOP_HELPER" ]` false → `_space_id` bleibt leer → `find-caller-desktop` wird nie aufgerufen (daher kein `op=show`-Logeintrag) → `wait-and-move-space` wird nie aufgerufen → CotEditor bleibt auf dem aktiven Desktop.

Verifiziert: direkter Helper-Aufruf `find-caller-desktop $$` liefert korrekt `780 2` (`sidecar=hit`) — die Auflösung ist intakt, NUR der Pfad in `show` ist falsch.

**Fix:** Symlink in `show` auflösen, bevor `dirname` läuft (while-`readlink`-Schleife oder `python3 -c "os.path.realpath"`). Betrifft NUR `show`; `tmux_spawn.sh` findet den Helper auf anderem Weg (Spawn-Logs zeigen `sidecar=hit space_id=780`).

**Fix applied 2026-05-29** (`bin/show` Z.20-22): `$0` wird vor `dirname` via `python3 -c 'os.path.realpath'` aufgelöst. `python3` ist ohnehin harte Dependency des Scripts, daher konsistent gegenüber der `readlink`-Schleife. Verifiziert (ohne CotEditor-Open): Aufruf-Simulation mit `$0=~/.local/bin/show` → `_DESKTOP_HELPER` resolved auf `Meta/blank/bin/../src/desktop/desktop_targeting.py`, `[ -f ]` true. Helper wird jetzt erreicht.

End-to-End-Live-Verify 2026-05-29T16:42 (User auf aktivem Desktop, `~/.local/bin/show <md>` aus Monitor_CC-Session): erstmals zwei `op=show`-Logzeilen — `op=show caller_pid=80872 claude_pid=80872 cwd=Monitor_CC sidecar=hit space_id=780` (Helper läuft, Caller-Desktop korrekt aufgelöst) + `op=show wait-and-move-space space_id=780 owner='CotEditor' move=no-new-window`. **Bug 1 damit vollständig bestätigt** (vorher NIE ein `op=show`-Eintrag). Datei landete trotzdem auf aktivem Desktop — Symptom jetzt rein durch Bug 2 verursacht.

### Bug 2 — `move=no-new-window` (separat, pending)

Bei Worker-Spawns (Helper gefunden, `space_id 780` korrekt aufgelöst) meldet `wait_for_new_windows_and_move` trotzdem `move=no-new-window` (Logs 02:01 + 02:59). Das neue Fenster wird im Poll-Fenster nicht als `after - before`-Delta erkannt → kein Move. Verdacht: CGWindowList-Sichtbarkeit (TCC für blanks `python3`), oder das Ziel-Fenster existierte bereits (kein Delta), oder Timing. Ursache pending.

**Bestätigt für `show` 2026-05-29T16:42** (nach Bug-1-Fix): `op=show wait-and-move-space space_id=780 owner='CotEditor' move=no-new-window`. Damit reproduziert über drei Pfade — spawn (Ghostty), show (CotEditor), alter dryrun (CotEditor) — alle `move=no-new-window`. Systematisches Problem in `wait_for_new_windows_and_move` (`after - before`-Delta erkennt das neue Fenster nicht), nicht app- oder pfadspezifisch.

### GitHub-Recherche 2026-05-29 — Move-API ist auf macOS 15 tot

Verifikation, ob es überhaupt eine API gibt, ein Fenster direkt auf einem nicht-aktiven Space zu öffnen, und ob unsere Move-API noch lebt. System: **macOS 15.7.7 (Sequoia, Build 24G720)**.

**Befund 1 — kein direktes Open-on-Space.** Es gibt keine öffentliche API, um ein Fenster direkt auf einem bestimmten, nicht-aktiven Space zu öffnen. Alle untersuchten Window-Manager (yabai 28.9k★, kasper/phoenix, lwouis/alt-tab-macos, bryancostanich/lattice, linearmouse) erzeugen das Fenster und **verschieben es danach** per privater SkyLight/CoreGraphics-API. Bestätigt damit: `open` landet immer auf dem aktiven Space, Move-after-create ist der einzige Weg.

**Befund 2 — `CGSMoveWindowsToManagedSpace` ist tot ab macOS 13.6/14.5/15.0.** Genau diese API nutzt unser Helper (`_move_windows_to_space` → `_CG.CGSMoveWindowsToManagedSpace`). `kasper/phoenix` `Phoenix/PHSpace.m:218-228` gibt für `moveWindows` explizit auf: `if isOperatingSystemAtLeastVentura136 || isOperatingSystemAtLeastSonoma145 || isOperatingSystemAtLeastSequoia: NSLog("deprecated"); return;` — Kommentar Z.64-65: *"only works prior to macOS 14.5"*. Auf macOS 15.7 ist der Move-Aufruf also vermutlich No-Op, selbst wenn die Fenster-Detection greift. (Bug-2-Symptom `move=no-new-window` kommt aktuell aber schon VOR dem Move-Call zustande — Detection scheitert zuerst; der tote Move ist eine zweite, noch nicht erreichte Schicht.)

**Befund 3 — moderner Weg (yabai, funktioniert auf macOS 15).** `asmvik/yabai` `src/space_manager.c:665-688` (`space_manager_move_window_to_space`), dreistufiger Fallback:
1. **`SLSPerformAsynchronousBridgedWindowManagementOperation`** + `objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation")` / `initWithWindows:spaceID:` — der moderne SkyLight-„bridged"-Operations-Pfad, OHNE Scripting-Addition/SIP. Bevorzugt auf aktuellem macOS.
2. **`SLSMoveWindowsToManagedSpace`** (SkyLight-`SLS`-Variante, NICHT die CoreGraphics-`CGS`-Variante die wir nutzen).
3. Scripting-Addition (`scripting_addition_move_window_to_space`, braucht partielles SIP-disable + Dock-Injection) bzw. `SLSSpaceSetCompatID`+`SLSSetWindowListWorkspace` mit Magic-CompatID als letzter Fallback.

**Konsequenz für Bug 2.** Zwei Schichten: (a) Fenster-Detection (`after - before`) scheitert, (b) selbst der Move (`CGSMoveWindowsToManagedSpace`) ist auf macOS 15 tot. Beide müssen adressiert werden. Migration der Move-API von CoreGraphics-`CGS` → SkyLight-`SLSPerformAsynchronousBridgedWindowManagementOperation` ist eine Architektur-Alternative → gehört in einen `dev/`-Probe (Worker-Rules §5), NICHT direkt in `src/`. Probe muss auf macOS 15.7 real ein Fenster auf einen Ziel-Space schieben, bevor `desktop_targeting.py` angefasst wird.

**Quellen (GitHub):** `kasper/phoenix` Phoenix/PHSpace.m; `asmvik/yabai` src/space_manager.c; `beeper/BetterSwiftAX`, `bryancostanich/lattice`, `linearmouse/linearmouse` (CGSSpace.h-Header-Deklarationen).

### Probe-Ergebnis 2026-05-29 — alle Move-APIs scheitern aus unprivilegiertem Prozess

**Probe:** `dev/space_move_probe/probe.py` + `dev/space_move_probe/01_reports/space_move_probe_2026-05-29.md`. Vollständiges Protokoll dort.

**Umgebung:** macOS 15.7.7, Homebrew Python 3.14.3, PyObjC NICHT verfügbar → reines ctypes + raw objc_msgSend. Accessibility (`AXIsProcessTrusted=True`) + Screen Recording (290 Fenster via CGWindowList) beide aktiv — kein Permission-Problem.

**Symbol-Inventar auf macOS 15.7:**
- `SLSMoveWindowsToManagedSpace` — FOUND (Stufe 2)
- `SLSPerformAsynchronousBridgedWindowManagementOperation` — **MISSING** (Stufe 1 Dispatcher)
- `SLSBridgedMoveWindowsToManagedSpaceOperation` (ObjC-Klasse) — FOUND, aber CRASH ohne Dispatcher
- `SLSCopySpacesForWindows`, `SLSGetActiveSpace`, `SLSMainConnectionID`, `SLSGetConnectionIDForPSN` — alle FOUND

**Test-Matrix:**

| Methode | Ergebnis | Detail |
|---------|----------|--------|
| A: `CGSMoveWindowsToManagedSpace` | **FAIL** | No-Op, bestätigt; rc=0x16000000 (void-Funktion) |
| B: `SLSMoveWindowsToManagedSpace` (eigene cid) | **FAIL** | Lautlos, Fenster bleibt auf aktivem Space |
| C: `SLSMoveWindowsToManagedSpace` (TextEdit-Owner-cid via `SLSGetConnectionIDForPSN`) | **FAIL** | Connection-ID ist nicht das fehlende Element |
| Stufe 1b: `SLSBridgedMoveWindowsToManagedSpaceOperation.start` direkt | **CRASH** | SIGSEGV; Klasse braucht `SLSPerformAsynchronousBridgedWindowManagementOperation` als Dispatch-Kontext |

**Diagnose:** `SLSMoveWindowsToManagedSpace` läuft ohne Fehler durch, bewegt aber nichts — silenter No-Op für unprivilegierte Prozesse. Vermutliche Ursache: benötigt privates System-Entitlement (`com.apple.private.skylight.*`) oder die yabai Dock-Scripting-Addition (Stufe 3, braucht SIP-Modifikation). Aus unprivilegiertem Python-Prozess nicht erreichbar.

**Fenster-Erkennung:** before/after-Diff via `CGWindowListCopyWindowInfo` ist robust. `open -a TextEdit` ohne `-n` öffnet kein neues Fenster wenn App bereits läuft → Fix: AppleScript `make new document`.

**Konsequenz:** Move-after-create ist auf macOS 15.7 aus Python/ctypes ohne SIP-Modifikation nicht machbar.

### Re-Verifikation 2026-05-29 (Opus + Screenshots) — Worker-Messmethode war unzuverlässig, Ergebnis trotzdem bestätigt

Anlass: User-Beobachtung beim Live-Test — TextEdit startete (Dock-Icon), aber kein Fenster auf seinem Desktop sichtbar; Verdacht, der Sonnet-Worker habe sich vertan. Opus hat unabhängig nachgeprüft.

**Befund 1 — Worker-Verifikation war kaputt.** Der Probe bestimmte PASS/FAIL allein über `SLSCopySpacesForWindows`. Diese API meldet für frisch erzeugte Fenster stur den *aktiven* Space, unabhängig davon wo das Fenster real liegt. Screenshot-Beleg: aktiver Desktop = 2 (space 780), API meldet Fenster auf [780], aber Vollbild-Screenshot des aktiven Desktops zeigt **kein** TextEdit-Fenster. Die `after==before==target?`-Logik des Workers mass also Rauschen.

**Befund 2 — unabhängige Methode bestätigt: Move ist tot.** Verlässliches Signal statt Readback-API: `CGWindowListCopyWindowInfo` mit `kCGWindowListOptionOnScreenOnly` (=1) listet nur Fenster des *aktiven* Desktops. Entscheidender Test: Fenster öffnen (landet NICHT auf aktivem Desktop) → per `SLSMoveWindowsToManagedSpace` auf den aktiven Desktop holen → on-screen-Liste UND Vollbild-Screenshot prüfen. Ergebnis: Fenster blieb unsichtbar (nicht in on-screen-Liste, nicht im Screenshot). Move bewegt nichts. Per-Window-Direktaufnahme `screencapture -l<wid>` zeigt das Fenster zwar sauber (existiert), aber es ist eben nicht auf dem aktiven Desktop platzierbar. **Worker-Schlussfolgerung war über einen falschen Weg richtig.**

**Befund 3 — verlässliche Methoden für künftige Tests:** (a) Fenster-Existenz/Inhalt: `screencapture -x -l<wid>` (space-übergreifend). (b) „Liegt Fenster auf aktivem Desktop?": Mitgliedschaft in `CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, …)`. (c) Desktop↔space_id-Karte: `CGSCopyManagedDisplaySpaces` (Reihenfolge = Desktop-Nummer), aktiver via `CGSGetActiveSpace`. NICHT verlassen auf `SLSCopySpacesForWindows`/`CGSGetWindowWorkspace` für die Live-Position fremder Fenster.

**Befund 4 (Nebenfund, offen):** Ein neues App-Fenster (`make new document`) öffnet NICHT auf dem aktiven Desktop, sondern dort wo die App „zuhause" ist. Reproduziert über mehrere Läufe (aktiv 2 bzw. 5, Fenster nie dort). Eigene Baustelle, separat von der Move-Frage — relevant falls künftig „open landet richtig" angenommen wird.

### Status: SACKGASSE — zurückgestellt (Entscheidung User 2026-05-29)

Optionsraum erschöpft: (1) Move-after-open = tot ohne SIP (verifiziert). (2) Direkt auf Ziel-Space öffnen = keine API (GitHub-Recherche). (3) Switch-open-switch = **abgelehnt** (User will nicht auf anderen Desktop gezogen werden). (4) Dock-Scripting-Addition + SIP-Teilabschaltung (yabai Stufe 3) = **abgelehnt** (kein Sicherheits-Trade-off). (5) Auto-Platzierung aufgeben = **abgelehnt** (Übersichtsverlust).

Kein nicht-SIP-Werkzeug auf macOS 15.7 erfüllt „lautlos platzieren ohne den User zu stören". Thema zurückgestellt. **Wiederaufnahme:** wenn die Reddit-/gh-cli-Recherchewerkzeuge ausgereifter sind → umfangreiche Neu-Recherche zu macOS-15-Space-Placement (neue private APIs, ggf. ScreenCaptureKit-/Accessibility-Wege, Entitlement-Optionen). Bis dahin bleibt der Symlink-Fix in `bin/show` (Bug 1) das einzige produktiv gelandete Ergebnis; Desktop-Routing (Bug 2) ist bekannt nicht funktionsfähig auf macOS 15.7.
