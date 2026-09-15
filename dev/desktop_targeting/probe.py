#!/usr/bin/env python3

# INFRASTRUCTURE
import argparse
import sys
from typing import Dict, Optional

import objc_bridge
from objc_bridge import _CG, _SL
from spaces import choose_target_space
from window_probe import close_all_textedit, open_test_window
from move_test import move_cgs, move_sls, run_test

_HELP_TEXT = """Space-move probe — empirisch testen welche API auf macOS 15.7 Fenster auf einen
anderen Space verschiebt.

Für jeden Move-Test wird ein eigenes neues TextEdit-Dokument via AppleScript erstellt
→ keine Fenster-Kontamination zwischen Tests. Vor und nach dem Move wird der Space des
Fensters via CGSGetWindowWorkspace zurückgelesen → explizites PASS/FAIL.

Fehler aus Move-Calls werden NICHT gecatcht — Permission-Fehler (TCC) sollen
sichtbar sein.

Usage:
  python3 probe.py [--space <target_space_id>] [--debug]
"""


# ORCHESTRATOR

def main() -> int:
    args = _parse_args()
    objc_bridge._DEBUG = args.debug

    cid = _CG.CGSMainConnectionID()
    sls_cid = _SL.SLSMainConnectionID()
    _print_header(cid, sls_cid)

    active, target = choose_target_space(cid, args.space)
    _print_target_space(active, target)

    results = _run_both_tests(cid, target)
    any_pass = _print_summary(active, target, results)

    close_all_textedit()
    return 0 if any_pass else 1


# FUNCTIONS

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=_HELP_TEXT,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--space', type=int, default=None,
                        help='Ziel-Space-ID (überschreibt Auto-Auswahl)')
    parser.add_argument('--debug', action='store_true', help='Rohe API-Werte ausgeben')
    return parser.parse_args()


def _print_header(cid: int, sls_cid: int) -> None:
    print("── Space-Move Probe — macOS 15.7 ────────────────────────────")
    print(f"CGS connection ID:  {cid}")
    print(f"SLS connection ID:  {sls_cid}")


def _print_target_space(active: int, target: int) -> None:
    print(f"\nAktiver Space:  {active}")
    print(f"Ziel-Space:     {target}")


def _run_both_tests(cid: int, target: int) -> Dict[str, Optional[bool]]:
    results: Dict[str, Optional[bool]] = {}

    wid_a = open_test_window("A")
    results['A: CGSMoveWindowsToManagedSpace (CoreGraphics, legacy)'] = run_test(
        "A: CGSMoveWindowsToManagedSpace (CoreGraphics, legacy)",
        move_cgs, cid, wid_a, target,
    )

    wid_b = open_test_window("B")
    results['B: SLSMoveWindowsToManagedSpace (SkyLight, Stufe 2)'] = run_test(
        "B: SLSMoveWindowsToManagedSpace (SkyLight, Stufe 2)",
        move_sls, cid, wid_b, target,
    )

    return results


def _print_summary(active: int, target: int, results: Dict[str, Optional[bool]]) -> bool:
    print("\n" + "=" * 60)
    print("ERGEBNIS-ZUSAMMENFASSUNG")
    print(f"  Aktiver Space:  {active}")
    print(f"  Ziel-Space:     {target}")
    print()
    any_pass = False
    for name, passed in results.items():
        if passed is True:
            mark, any_pass = "PASS", True
        elif passed is False:
            mark = "FAIL"
        else:
            mark = "UNCLEAR"
        print(f"  [{mark}]  {name}")
    print("=" * 60)
    return any_pass


if __name__ == '__main__':
    sys.exit(main())
