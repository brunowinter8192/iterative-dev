# INFRASTRUCTURE
import subprocess
import sys
import time
from typing import Optional, Set

from objc_bridge import _CG, _cf_at, _cf_count, _dbg, _dict_long, _dict_str


# FUNCTIONS

# ── Fenster-Erkennung ──────────────────────────────────────────────────────────

def wids_for_owner(owner_name: str) -> Set[int]:
    arr = _CG.CGWindowListCopyWindowInfo(0, 0)
    out: Set[int] = set()
    for i in range(_cf_count(arr)):
        d = _cf_at(arr, i)
        if _dict_long(d, "kCGWindowLayer") != 0:
            continue
        if _dict_str(d, "kCGWindowOwnerName") != owner_name:
            continue
        wid = _dict_long(d, "kCGWindowNumber")
        if wid is not None:
            out.add(wid)
    return out


def open_new_textedit_window() -> None:
    """Öffnet genau ein neues TextEdit-Dokument via AppleScript — robust auch wenn
    TextEdit bereits läuft (im Gegensatz zu 'open -a TextEdit' das TextEdit nur
    aktiviert wenn es schon läuft)."""
    subprocess.run(
        ['osascript', '-e', 'tell application "TextEdit" to make new document'],
        check=True,
    )


def wait_for_new_window(owner_name: str, timeout: float = 6.0) -> Optional[int]:
    """before/after-Diff nach open_new_textedit_window. Wird vor dem open-Call
    aufgerufen (snapshotted before), DANN open, DANN poll."""
    before = wids_for_owner(owner_name)
    _dbg(f"before-snapshot: {len(before)} Fenster von {owner_name}")
    return before, lambda: _poll_new(owner_name, before, timeout)


def _poll_new(owner_name: str, before: Set[int], timeout: float) -> Optional[int]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        time.sleep(0.15)
        after = wids_for_owner(owner_name)
        new = after - before
        if new:
            wid = next(iter(new))
            print(f"  Fenster erkannt (before/after-Diff): wid={wid}  "
                  f"(before={len(before)}, after={len(after)})")
            return wid
    return None

# ── Test-Kern ──────────────────────────────────────────────────────────────────

def open_test_window(label: str) -> int:
    """Snapshot → open → poll. Gibt wid zurück oder beendet mit Fehler."""
    print(f"\n  Öffne TextEdit-Fenster für Test {label}...")
    _, poll = wait_for_new_window('TextEdit')
    open_new_textedit_window()
    time.sleep(0.3)
    wid = poll()
    if wid is None:
        print(
            "ERROR: Kein neues TextEdit-Fenster nach 6s erkannt.\n"
            "Mögliche Ursache: python3 hat keine Accessibility/Screen-Recording-Berechtigung\n"
            "  → Systemeinstellungen → Datenschutz & Sicherheit → Bildschirmaufnahme\n"
            "     Terminal (oder python3) eintragen, dann neu starten.",
            file=sys.stderr,
        )
        close_all_textedit()
        sys.exit(1)
    return wid


def close_all_textedit():
    subprocess.run(
        ['osascript', '-e', 'tell application "TextEdit" to close every window without saving'],
        capture_output=True,
    )
