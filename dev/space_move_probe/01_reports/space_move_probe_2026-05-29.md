# Space-Move Probe — macOS 15.7.7 (Sequoia, Build 24G720)

**Datum:** 2026-05-29  
**Zweck:** Empirisch klären welche private API auf macOS 15.7 ein Fenster (TextEdit) auf
einen nicht-aktiven Space verschieben kann. Grundlage für Migration von `desktop_targeting.py`
weg von `CGSMoveWindowsToManagedSpace`.

## Setup

- System: macOS 15.7.7 Sequoia, ARM64 (Apple Silicon)
- Python: Homebrew Python 3.14.3 (`/opt/homebrew/bin/python3`)
- PyObjC: **nicht installiert** → reines ctypes + raw `objc_msgSend`-Stil (identisch zu `desktop_targeting.py`)
- Berechtigungen: `AXIsProcessTrusted = True` (Accessibility), Screen Recording aktiv
  (CGWindowListCopyWindowInfo liefert 290 Fenster)
- Fenster-Erkennung: before/after-Diff via `CGWindowListCopyWindowInfo`, neues Fenster via
  AppleScript `tell application "TextEdit" to make new document` (robust; `open -a TextEdit`
  ist fragil wenn App schon läuft)
- Verifikation: `SLSCopySpacesForWindows(my_cid, 7, [wid])` gibt vor dem Move korrekt `[active_space]`
  zurück — funktioniert für TextEdit-Fenster-WIDs aus CGWindowList

## Getestete Methoden

### Test A — `CGSMoveWindowsToManagedSpace` (CoreGraphics)

```
Bibliothek: /System/Library/Frameworks/CoreGraphics.framework/CoreGraphics
Signatur:   CGSMoveWindowsToManagedSpace(cid, window_array, space_id)
desktop_targeting.py nutzt genau diese API (_move_windows_to_space)
```

- **before-space:** `[2119]` (aktiver Space, korrekt per SLSCopySpacesForWindows)
- **after-space:** `[2119]` (unverändert)
- **Return-Code:** `0x16000000` — kein gültiger OSStatus → Funktion wohl void; restype=None
  in desktop_targeting.py bestätigt das
- **Ergebnis: FAIL** — No-Op auf macOS 15.7. Bestätigt die kasper/phoenix-Recherche:
  "only works prior to macOS 14.5"

### Test B — `SLSMoveWindowsToManagedSpace` (SkyLight, eigene Connection)

```
Bibliothek: /System/Library/PrivateFrameworks/SkyLight.framework/SkyLight
Signatur:   SLSMoveWindowsToManagedSpace(cid, window_array, space_id)
cid = SLSMainConnectionID() — die Connection des probe.py-Prozesses
```

- **before-space:** `[2119]` (korrekt)
- **after-space:** `[2119]` (unverändert)
- **Return-Code:** `0x57A00000` — kein gültiger OSStatus → Funktion wohl void
- **Ergebnis: FAIL** — Fenster bleibt auf aktivem Space. Lautlos ignoriert.

### Test C — `SLSMoveWindowsToManagedSpace` (SkyLight, TextEdit-Owner-Connection)

```
TextEdit PID → PSN via Carbon GetProcessForPID → SLSGetConnectionIDForPSN
SLSConnectionGetPID(te_cid) == TextEdit-PID: Roundtrip verifiziert ✓
te_cid = 428707
```

- **before-space:** `[2119]`
- **after-space:** `[2119]`
- **Ergebnis: FAIL** — Auch mit der Owner-Connection (TextEdit's eigene SLS-Verbindung)
  kein Move. Die Connection-ID ist also nicht das fehlende Puzzle-Stück.

### Test Stufe 1b — `SLSBridgedMoveWindowsToManagedSpaceOperation` direkt

```
Klasse vorhanden: SLSBridgedMoveWindowsToManagedSpaceOperation ← objc_getClass gibt non-nil
Dispatcher fehlt: SLSPerformAsynchronousBridgedWindowManagementOperation ← MISSING in SkyLight
Versuch: [[SLSBridgedMoveWindowsToManagedSpaceOperation alloc] initWithWindows:wids spaceID:target]
         dann .start aufrufen (NSOperation-Weg ohne Queue)
```

- **Ergebnis: CRASH (SIGSEGV, Exit 139)** — Die Operation-Klasse ist vorhanden, aber das
  direkte `start` ohne den Async-Operation-Dispatcher führt zu einem Segfault. Die Klasse
  braucht zwingend `SLSPerformAsynchronousBridgedWindowManagementOperation` als Dispatch-Kontext,
  der auf macOS 15.7 **fehlt** (Symbol nicht in SkyLight exportiert).

## Verfügbare Symbole (macOS 15.7 SkyLight)

| Symbol | Status | Bemerkung |
|--------|--------|-----------|
| `SLSMoveWindowsToManagedSpace` | FOUND | Stufe 2 — lautlos no-op |
| `SLSPerformAsynchronousBridgedWindowManagementOperation` | **MISSING** | Stufe 1 Dispatcher |
| `SLSBridgedMoveWindowsToManagedSpaceOperation` (Klasse) | FOUND | crash ohne Dispatcher |
| `SLSCopySpacesForWindows` | FOUND | Verifikation funktioniert |
| `SLSGetActiveSpace` | FOUND | |
| `SLSMainConnectionID` | FOUND | |
| `SLSGetConnectionIDForPSN` | FOUND | |
| `SLSConnectionGetPID` | FOUND | |
| `CGSMoveWindowsToManagedSpace` | FOUND | no-op ab macOS 14.5 |
| `CGSCopySpacesForWindows` | FOUND | |
| `CGSGetWindowWorkspace` | FOUND | gibt rc=0, out=0 für fremde Fenster |

## Fenster-Erkennung (Robustheit)

**before/after-Diff via `CGWindowListCopyWindowInfo`:** robust. Der Diff erkennt neue Fenster
zuverlässig solange die App nicht mehrere Fenster gleichzeitig öffnet.

**Kritischer Bug dokumentiert:** `open -a TextEdit` ohne `-n`-Flag öffnet kein neues Fenster wenn
TextEdit bereits läuft — aktiviert nur die App. Der Diff findet dann kein Delta und läuft in Timeout.
Fix: AppleScript `make new document` erzeugt immer genau ein neues Fenster.

**Frontmost-Fenster-Variante:** nicht robust — wenn App bereits Fenster hat, ist das "frontmost"
Fenster nicht zwingend das neu geöffnete. Before/after-Diff bleibt der korrekte Weg.

## Verifikations-Methode

`SLSCopySpacesForWindows(my_cid, 7, [wid])` funktioniert für TextEdit-Fenster-WIDs
(aus `CGWindowListCopyWindowInfo`) aus einem Process mit Screen Recording + Accessibility.
Gibt `[space_id]` korrekt zurück. Primär genutzt.

`CGSGetWindowWorkspace(my_cid, wid, &outSpace)` gibt `rc=0, out=0` für Fenster fremder
Prozesse — nicht nutzbar.

## Diagnose: Warum schlägt SLSMoveWindowsToManagedSpace fehl?

Alle vier Ansätze (A/B/C/Stufe-1b) scheitern trotz Accessibility + Screen Recording.
Die wahrscheinlichste Ursache: `SLSMoveWindowsToManagedSpace` benötigt auf macOS 15 ein
**privates System-Entitlement** oder die **Dock-Scripting-Addition** (yabai Stufe 3), um
Fenster fremder Prozesse zwischen Spaces zu verschieben.

yabai auf macOS 13+ dokumentiert, dass Space-Moves ohne Scripting-Addition nicht funktionieren.
Die Scripting-Addition injiziert Code in Dock.app, das die nötige `com.apple.private.skylight.*`-
Berechtigung hat. Eine unprivilegierte Python-Anwendung kann diese Entitlements nicht nachahmen.

## Ergebnis-Matrix

| Methode | PASS/FAIL | Kommentar |
|---------|-----------|-----------|
| A: `CGSMoveWindowsToManagedSpace` | **FAIL** | No-Op ab macOS 14.5, bestätigt |
| B: `SLSMoveWindowsToManagedSpace` (eigene cid) | **FAIL** | Lautlos kein Move |
| C: `SLSMoveWindowsToManagedSpace` (Owner-cid) | **FAIL** | Connection-ID irrelevant |
| Stufe 1b: `SLSBridgedMoveWindowsToManagedSpaceOperation.start` | **CRASH** | Dispatcher MISSING |

**Keine der getesteten Methoden verschiebt ein Fenster auf macOS 15.7.**

## Implikation für desktop_targeting.py

Move-after-create ist mit purer ctypes-API aus einem unprivilegierten Prozess auf macOS 15.7
nicht machbar. Alternative Strategie für `show`/`tmux_spawn.sh`:

**Switch-open-switch:** aktiven Space temporär auf Ziel-Space wechseln (via
`CGSSetWorkspace` o.ä.), App öffnen, zurückwechseln. Nachteil: sichtbare Space-Animation.
Diese API-Strategie wurde im Probe nicht getestet, wäre aber der nächste empirische Schritt.
