# INFRASTRUCTURE
import ctypes
import time
from typing import List, Optional

from objc_bridge import _CG, _SL, _cf_count, _cfarray_ints, _dbg, _make_uint_array


# FUNCTIONS

def get_window_space(cid: int, wid: int) -> Optional[int]:
    out = ctypes.c_uint64(0)
    rc = _CG.CGSGetWindowWorkspace(cid, ctypes.c_uint32(wid), ctypes.byref(out))
    _dbg(f"CGSGetWindowWorkspace(cid={cid}, wid={wid}) rc={rc} out={out.value}")
    if rc != 0:
        return None
    return out.value if out.value != 0 else None


def get_window_spaces_copy(cid: int, wid: int) -> List[int]:
    wid_arr = _make_uint_array([wid])

    result = _SL.SLSCopySpacesForWindows(cid, 7, wid_arr)
    _dbg(f"SLSCopySpacesForWindows ptr={result}")
    if result:
        ids = _cfarray_ints(result)
        _dbg(f"SLS count={_cf_count(result)} ids={ids}")
        if ids:
            return ids

    result2 = _CG.CGSCopySpacesForWindows(cid, 7, wid_arr)
    _dbg(f"CGSCopySpacesForWindows ptr={result2}")
    if result2:
        ids2 = _cfarray_ints(result2)
        _dbg(f"CGS count={_cf_count(result2)} ids={ids2}")
        return ids2
    return []

def move_cgs(cid: int, wids: List[int], space_id: int) -> int:
    rc = _CG.CGSMoveWindowsToManagedSpace(cid, _make_uint_array(wids), ctypes.c_uint64(space_id))
    _dbg(f"CGSMoveWindowsToManagedSpace rc={rc}")
    return rc


def move_sls(cid: int, wids: List[int], space_id: int) -> int:
    rc = _SL.SLSMoveWindowsToManagedSpace(cid, _make_uint_array(wids), ctypes.c_uint64(space_id))
    _dbg(f"SLSMoveWindowsToManagedSpace rc={rc}")
    return rc

def run_test(label: str, move_fn, cid: int, wid: int, target_space: int) -> bool:
    print(f"\n── Test {label} ──────────────────────────────────────────────")

    before_ws = get_window_space(cid, wid)
    before_copy = get_window_spaces_copy(cid, wid)
    print(f"  before  CGSGetWindowWorkspace:  space={before_ws}")
    print(f"  before  CGSCopySpacesForWindows: {before_copy}")

    print(f"  → Move-Call (wid={wid}, target={target_space})...")
    rc = move_fn(cid, [wid], target_space)
    print(f"  Return-Code: {rc}")
    time.sleep(0.5)

    after_ws = get_window_space(cid, wid)
    after_copy = get_window_spaces_copy(cid, wid)
    print(f"  after   CGSGetWindowWorkspace:  space={after_ws}")
    print(f"  after   CGSCopySpacesForWindows: {after_copy}")
    print(f"  target-space: {target_space}")

    if after_ws is not None and before_ws is not None:
        passed = after_ws == target_space
        src = "CGSGetWindowWorkspace"
    elif after_copy:
        passed = target_space in after_copy
        src = "CGSCopySpacesForWindows"
    else:
        print("  WARN: Beide Verifikations-APIs geben None/[] zurück.")
        print("        Mögliche Ursache: python3 darf Fenster fremder Prozesse")
        print("        auf macOS 15 nicht per SLS/CGS space-querien (TCC).")
        print("        Visuelle Verifikation nötig — Probe-Ergebnis nicht eindeutig.")
        passed = False
        src = "keine"

    print(f"  Verifikation via:  {src}")
    print(f"  Ergebnis:          {'PASS' if passed else 'FAIL'}")
    return passed
