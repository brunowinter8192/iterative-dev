#!/usr/bin/env python3
"""Desktop targeting helper — find caller's Mission-Control Desktop, move new app windows there.

Used by iterative-dev plugin to:
  1. tmux_spawn.sh: move newly-spawned Ghostty worker windows to the spawning Main's Desktop
  2. bin/show: open files on the calling Main's Desktop instead of whichever Desktop is active

Caller identification: walk up parent-PID chain from $$ to find the nearest `claude` process,
use its cwd via lsof, then look up cwd→space_id in Monitor_CC's cwd_desktop.json sidecar.

Space sidecar schema (written by Monitor_CC menubar):
  Path: ~/Library/Application Support/com.brunowinter.monitor_cc_menubar/cwd_desktop.json
  Shape: {"<cwd>": {"space_id": <int>, "desktop_no": <int>}}
  Semantics: last-known-good per cwd; may be absent or lack a given cwd → graceful fallback.

Window-move via private `CGSMoveWindowsToManagedSpace`.

Logging: ~/Library/Logs/blank/desktop_targeting.log (one line per invocation).

CLI usage from bash:
  desktop_targeting.py find-caller-desktop <caller_pid> [op]
    → prints "<space_id> <desktop_no>" for the caller's Main session. Exit 0 on success, 1 on fail.

  desktop_targeting.py wait-and-move-space <space_id> <owner_name> [timeout_secs=4] [op]
    → snapshots existing app windows, polls for new window, moves to space_id.
      Exit 0 on success, 1 on no-match. Use after pre-resolving space via find-caller-desktop.

  desktop_targeting.py wait-and-move <caller_pid> <app_name> [timeout_secs=4] [op]
    → combined: resolves caller space then moves new window. Legacy fallback.
"""

# INFRASTRUCTURE
import ctypes
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

_APP_SUPPORT      = Path("~/Library/Application Support/com.brunowinter.monitor_cc_menubar").expanduser()
_CWD_DESKTOP_FILE = _APP_SUPPORT / "cwd_desktop.json"
_BLANK_LOG        = Path("~/Library/Logs/blank/desktop_targeting.log").expanduser()

_CGW_LIST_ALL    = 0
_CGW_NULL_WID    = 0
_PARENT_WALK_MAX = 12

_CG  = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
_OBJ = ctypes.CDLL('/usr/lib/libobjc.A.dylib')

_OBJ.sel_registerName.restype  = ctypes.c_void_p
_OBJ.sel_registerName.argtypes = [ctypes.c_char_p]
_OBJ.objc_getClass.restype     = ctypes.c_void_p
_OBJ.objc_getClass.argtypes    = [ctypes.c_char_p]

# Module-level CFUNCTYPE refs — GC of these corrupts the IMP pointer table
_FT_vv   = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
_FT_vvv  = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
_FT_vvcp = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p)
_FT_vvl  = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_long)
_FT_lvv  = ctypes.CFUNCTYPE(ctypes.c_long,   ctypes.c_void_p, ctypes.c_void_p)
_FT_pvv  = ctypes.CFUNCTYPE(ctypes.c_char_p, ctypes.c_void_p, ctypes.c_void_p)
_FT_nvv  = ctypes.CFUNCTYPE(None,            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
_FT_nvvv = ctypes.CFUNCTYPE(None,            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)

_IMP = ctypes.cast(_OBJ.objc_msgSend, ctypes.c_void_p).value

_CG.CGSMainConnectionID.argtypes          = []
_CG.CGSMainConnectionID.restype           = ctypes.c_int32
_CG.CGSGetActiveSpace.argtypes            = [ctypes.c_int32]
_CG.CGSGetActiveSpace.restype             = ctypes.c_uint64
_CG.CGSCopyManagedDisplaySpaces.argtypes  = [ctypes.c_int32]
_CG.CGSCopyManagedDisplaySpaces.restype   = ctypes.c_void_p
_CG.CGSMoveWindowsToManagedSpace.argtypes = [ctypes.c_int32, ctypes.c_void_p, ctypes.c_uint64]
_CG.CGSMoveWindowsToManagedSpace.restype  = None
_CG.CGWindowListCopyWindowInfo.argtypes   = [ctypes.c_uint32, ctypes.c_uint32]
_CG.CGWindowListCopyWindowInfo.restype    = ctypes.c_void_p

# FUNCTIONS

# --- objc bridge ---

def _sel(s: str):                    return _OBJ.sel_registerName(s.encode())
def _msg1v(obj, s: str, a):          return ctypes.cast(_IMP, _FT_vvv)(obj, _sel(s), a)
def _msg1cp(obj, s: str, a: bytes):  return ctypes.cast(_IMP, _FT_vvcp)(obj, _sel(s), a)
def _msg1l(obj, s: str, a: int):     return ctypes.cast(_IMP, _FT_vvl)(obj, _sel(s), ctypes.c_long(a))
def _msgl(obj, s: str) -> int:       return ctypes.cast(_IMP, _FT_lvv)(obj, _sel(s))
def _msgp(obj, s: str):              return ctypes.cast(_IMP, _FT_pvv)(obj, _sel(s))

def _nsstr(s: str):
    return _msg1cp(_OBJ.objc_getClass(b"NSString"), "stringWithUTF8String:", s.encode())

def _cf_count(arr) -> int:    return _msgl(arr, "count")
def _cf_at(arr, i: int):      return _msg1l(arr, "objectAtIndex:", i)
def _dict_val(d, key: str):   return _msg1v(d, "objectForKey:", _nsstr(key))

def _dict_str(d, key: str) -> Optional[str]:
    v = _dict_val(d, key)
    if not v: return None
    r = _msgp(v, "UTF8String")
    return r.decode() if r else None

def _dict_long(d, key: str) -> Optional[int]:
    v = _dict_val(d, key)
    return _msgl(v, "intValue") if v else None

def _make_uint_array(values: List[int]):
    NSMutableArray = _OBJ.objc_getClass(b"NSMutableArray")
    NSNumber = _OBJ.objc_getClass(b"NSNumber")
    arr = ctypes.cast(_IMP, _FT_vv)(NSMutableArray, _sel("array"))
    for v in values:
        n = ctypes.cast(_IMP, _FT_vvl)(NSNumber, _sel("numberWithUnsignedInt:"), ctypes.c_long(v))
        ctypes.cast(_IMP, _FT_nvv)(arr, _sel("addObject:"), n)
    return arr

# --- logging ---

def _log(msg: str) -> None:
    try:
        _BLANK_LOG.parent.mkdir(parents=True, exist_ok=True)
        ts = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime())
        with _BLANK_LOG.open("a") as f:
            f.write(f"{ts} {msg}\n")
    except Exception:  # best-effort logger — swallow all I/O errors silently
        return

# --- caller identification ---

# Walk up parent-PID chain from caller_pid up to _PARENT_WALK_MAX hops, return the first
# PID whose command contains 'claude' (case-insensitive). None if no claude ancestor found.
def _find_claude_ancestor(caller_pid: int) -> Optional[int]:
    pid = caller_pid
    for _ in range(_PARENT_WALK_MAX):
        if pid <= 1: return None
        r = subprocess.run(['ps', '-o', 'ppid=,command=', '-p', str(pid)],
                            capture_output=True, text=True, timeout=2)
        if r.returncode != 0: return None
        parts = r.stdout.strip().split(None, 1)
        if len(parts) != 2: return None
        ppid_str, cmd = parts
        if 'claude' in cmd.lower() and 'claude_proxy_start' not in cmd:
            return pid
        try:
            pid = int(ppid_str)
        except ValueError:
            return None
    return None

# Return cwd of a PID via lsof (cwd file descriptor). None on failure.
def _cwd_of_pid(pid: int) -> Optional[str]:
    r = subprocess.run(['lsof', '-a', '-d', 'cwd', '-p', str(pid)],
                        capture_output=True, text=True, timeout=2)
    for line in r.stdout.strip().split('\n'):
        if line.startswith('COMMAND') or not line: continue
        fields = line.split(None, 8)
        if len(fields) == 9:
            return fields[8]
    return None

# --- CGS / Mission Control ---

# Returns ({space_id: (display_id, desktop_no_1based)}, active_space_id)
def _build_space_map(cid: int) -> Tuple[Dict[int, Tuple[str, int]], int]:
    active = _CG.CGSGetActiveSpace(cid)
    dsp_arr = _CG.CGSCopyManagedDisplaySpaces(cid)
    n_displays = _cf_count(dsp_arr)
    out: Dict[int, Tuple[str, int]] = {}
    for di in range(n_displays):
        d = _cf_at(dsp_arr, di)
        disp_id = (_dict_str(d, 'Display Identifier') or
                   _dict_str(d, 'DisplayIdentifier') or 'unknown')[:8]
        spaces_val = _dict_val(d, 'Spaces') or _dict_val(d, 'spaces')
        if not spaces_val: continue
        for si in range(_cf_count(spaces_val)):
            sp = _cf_at(spaces_val, si)
            sid = (_dict_long(sp, 'ManagedSpaceID') or
                   _dict_long(sp, 'id') or _dict_long(sp, 'ID'))
            if sid is not None:
                out[sid] = (disp_id, si + 1)
    return out, active

# Move one or more windows to the target space (private API; non-fullscreen windows only)
def _move_windows_to_space(cid: int, wids: List[int], space_id: int) -> None:
    _CG.CGSMoveWindowsToManagedSpace(cid, _make_uint_array(wids), ctypes.c_uint64(space_id))

# --- window polling ---

# Returns {wid} for layer-0 windows. If owner_name is non-empty, filters by kCGWindowOwnerName;
# else returns all layer-0 windows except system-app noise (Dock, WindowServer, Finder, etc.).
_SYSTEM_APP_EXCLUDE = {"Dock", "WindowServer", "SystemUIServer", "Window Server",
                       "Spotlight", "NotificationCenter", "Control Center"}

def _wids_for_owner_name(owner_name: str) -> Set[int]:
    arr = _CG.CGWindowListCopyWindowInfo(_CGW_LIST_ALL, _CGW_NULL_WID)
    out: Set[int] = set()
    for i in range(_cf_count(arr)):
        d = _cf_at(arr, i)
        if _dict_long(d, "kCGWindowLayer") != 0: continue
        own = _dict_str(d, "kCGWindowOwnerName")
        if owner_name:
            if own != owner_name: continue
        else:
            if own in _SYSTEM_APP_EXCLUDE: continue
        wid = _dict_long(d, "kCGWindowNumber")
        if wid is not None: out.add(wid)
    return out

# --- sidecar lookup ---

def _read_cwd_desktop_map() -> Dict:
    try:
        return json.loads(_CWD_DESKTOP_FILE.read_text())
    except Exception as e:
        _log(f"sidecar read error: {e}")
        return {}

# --- public ops ---

# Returns (space_id, desktop_no) for the caller's Main session.
# On sidecar miss falls back to CGSGetActiveSpace (best-effort). Logs all outcomes.
# Strategy: parent-walk → claude pid → claude's cwd via lsof → cwd_desktop.json sidecar lookup.
def find_caller_main_space(caller_pid: int, op: str = "unknown") -> Tuple[Optional[int], Optional[int]]:
    claude_pid = _find_claude_ancestor(caller_pid)
    if not claude_pid:
        _log(f"op={op} caller_pid={caller_pid} claude_pid=none sidecar=skip space_id=none")
        return None, None
    cwd = _cwd_of_pid(claude_pid)
    if not cwd:
        _log(f"op={op} caller_pid={caller_pid} claude_pid={claude_pid} cwd=none sidecar=skip space_id=none")
        return None, None

    cid = _CG.CGSMainConnectionID()

    if not _CWD_DESKTOP_FILE.exists():
        active = _CG.CGSGetActiveSpace(cid)
        space_map, _ = _build_space_map(cid)
        dno = space_map.get(active, (None, None))[1]
        _log(f"op={op} caller_pid={caller_pid} claude_pid={claude_pid} cwd={cwd} sidecar=miss:file_absent space_id=active:{active}")
        return active, dno

    sidecar = _read_cwd_desktop_map()
    if not sidecar:
        active = _CG.CGSGetActiveSpace(cid)
        space_map, _ = _build_space_map(cid)
        dno = space_map.get(active, (None, None))[1]
        _log(f"op={op} caller_pid={caller_pid} claude_pid={claude_pid} cwd={cwd} sidecar=miss:parse_error space_id=active:{active}")
        return active, dno

    entry = sidecar.get(cwd)
    if not entry:
        active = _CG.CGSGetActiveSpace(cid)
        space_map, _ = _build_space_map(cid)
        dno = space_map.get(active, (None, None))[1]
        _log(f"op={op} caller_pid={caller_pid} claude_pid={claude_pid} cwd={cwd} sidecar=miss:no_cwd space_id=active:{active}")
        return active, dno

    space_id   = entry.get("space_id")
    desktop_no = entry.get("desktop_no")
    _log(f"op={op} caller_pid={caller_pid} claude_pid={claude_pid} cwd={cwd} sidecar=hit space_id={space_id}")
    return space_id, desktop_no

# Snapshot windows of owner_name, poll up to timeout_secs for NEW windows,
# move all new windows to target space. Returns count of moved windows (0 = none found).
def wait_for_new_windows_and_move(owner_name: str, target_space_id: int,
                                   timeout_secs: float = 4.0,
                                   poll_interval: float = 0.15) -> int:
    before = _wids_for_owner_name(owner_name)
    deadline = time.monotonic() + timeout_secs
    cid = _CG.CGSMainConnectionID()
    new: Set[int] = set()
    while time.monotonic() < deadline:
        time.sleep(poll_interval)
        after = _wids_for_owner_name(owner_name)
        new = after - before
        if new: break
    if not new: return 0
    _move_windows_to_space(cid, list(new), target_space_id)
    return len(new)

# CLI

def _cli_find_caller_desktop(caller_pid: int, op: str = "find") -> int:
    sid, dno = find_caller_main_space(caller_pid, op=op)
    if sid is None:
        return 1
    print(f"{sid} {dno}")
    return 0

# wait-and-move-space: caller already resolved space_id pre-open; just poll + move.
def _cli_wait_and_move_space(space_id: int, owner_name: str, timeout: float, op: str) -> int:
    n = wait_for_new_windows_and_move(owner_name, space_id, timeout_secs=timeout)
    if n == 0:
        _log(f"op={op} wait-and-move-space space_id={space_id} owner={owner_name!r} move=no-new-window")
        print("no-new-window", file=sys.stderr)
        return 1
    _log(f"op={op} wait-and-move-space space_id={space_id} owner={owner_name!r} move={n}_windows")
    print(f"moved {n} window(s) to space {space_id}")
    return 0

# wait-and-move: legacy combined command (resolve + move in one call).
def _cli_wait_and_move(caller_pid: int, owner_name: str, timeout: float, op: str) -> int:
    sid, _dno = find_caller_main_space(caller_pid, op=op)
    if sid is None:
        _log(f"op={op} wait-and-move caller_pid={caller_pid} owner={owner_name!r} move=caller-not-found")
        print("caller-main-not-found", file=sys.stderr)
        return 1
    return _cli_wait_and_move_space(sid, owner_name, timeout, op)

def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    cmd = sys.argv[1]

    if cmd == 'find-caller-desktop':
        if len(sys.argv) < 3: return 2
        caller_pid = int(sys.argv[2])
        op = sys.argv[3] if len(sys.argv) > 3 else "find"
        return _cli_find_caller_desktop(caller_pid, op)

    if cmd == 'wait-and-move-space':
        if len(sys.argv) < 4: return 2
        space_id   = int(sys.argv[2])
        owner_name = sys.argv[3]
        timeout    = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0
        op         = sys.argv[5] if len(sys.argv) > 5 else "move"
        return _cli_wait_and_move_space(space_id, owner_name, timeout, op)

    if cmd == 'wait-and-move':
        if len(sys.argv) < 4: return 2
        caller_pid = int(sys.argv[2])
        owner_name = sys.argv[3]
        timeout    = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0
        op         = sys.argv[5] if len(sys.argv) > 5 else "move"
        return _cli_wait_and_move(caller_pid, owner_name, timeout, op)

    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2

if __name__ == '__main__':
    sys.exit(main())
