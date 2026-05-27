#!/usr/bin/env python3
"""Desktop targeting helper — find caller's Mission-Control Desktop, move new app windows there.

Used by iterative-dev plugin to:
  1. tmux_spawn.sh: move newly-spawned Ghostty worker windows to the spawning Main's Desktop
  2. bin/show: open files on the calling Main's Desktop instead of whichever Desktop is active

Caller identification: walk up parent-PID chain from $$ to find the nearest `claude` process,
use its TTY to look up the cwd via lsof, then look up cwd→UUID in Monitor_CC's APP_SUPPORT map.

CGS detection logic extracted from Monitor_CC/dev/desktop_detection/01_probe.py (proven 100%
detection rate). Window-move via private `CGSMoveWindowsToManagedSpace`.

CLI usage from bash:
  desktop_targeting.py wait-and-move <caller_pid> <app_name> [timeout_secs=4]
    → identifies caller's desktop, snapshots existing app windows, polls for new window,
      moves new window(s) to caller's desktop. Exit 0 on success, 1 on no-match.

  desktop_targeting.py find-caller-desktop <caller_pid>
    → prints "<space_id> <desktop_no>" for the caller's Main session.
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

_APP_SUPPORT = Path("~/Library/Application Support/com.brunowinter.monitor_cc_menubar").expanduser()
_CWD_UUID_FILE = _APP_SUPPORT / "ghostty_cwd_uuid.json"

_CGS_SPACE_MASK   = 0x7
_CGW_LIST_ALL     = 0
_CGW_NULL_WID     = 0
_PARENT_WALK_MAX  = 12

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

_CG.CGSMainConnectionID.argtypes           = []
_CG.CGSMainConnectionID.restype            = ctypes.c_int32
_CG.CGSGetActiveSpace.argtypes             = [ctypes.c_int32]
_CG.CGSGetActiveSpace.restype              = ctypes.c_uint64
_CG.CGSCopyManagedDisplaySpaces.argtypes   = [ctypes.c_int32]
_CG.CGSCopyManagedDisplaySpaces.restype    = ctypes.c_void_p
_CG.CGSCopySpacesForWindows.argtypes       = [ctypes.c_int32, ctypes.c_int32, ctypes.c_void_p]
_CG.CGSCopySpacesForWindows.restype        = ctypes.c_void_p
_CG.CGSMoveWindowsToManagedSpace.argtypes  = [ctypes.c_int32, ctypes.c_void_p, ctypes.c_uint64]
_CG.CGSMoveWindowsToManagedSpace.restype   = None
_CG.CGWindowListCopyWindowInfo.argtypes    = [ctypes.c_uint32, ctypes.c_uint32]
_CG.CGWindowListCopyWindowInfo.restype     = ctypes.c_void_p

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

# Returns list of space_ids for one CGWindowID
def _spaces_for_wid(cid: int, wid: int) -> List[int]:
    arr = _CG.CGSCopySpacesForWindows(cid, _CGS_SPACE_MASK, _make_uint_array([wid]))
    if not arr: return []
    return [_msgl(_cf_at(arr, i), "intValue") for i in range(_cf_count(arr))]

# Move one or more windows to the target space (private API; non-fullscreen windows only)
def _move_windows_to_space(cid: int, wids: List[int], space_id: int) -> None:
    _CG.CGSMoveWindowsToManagedSpace(cid, _make_uint_array(wids), ctypes.c_uint64(space_id))

# --- Ghostty / Main lookup ---

def _ghostty_pid() -> Optional[int]:
    r = subprocess.run(['ps', '-A', '-o', 'pid=,command='], capture_output=True, text=True, timeout=2)
    for line in r.stdout.splitlines():
        if 'Ghostty.app/Contents/MacOS' in line:
            pid_str = line.split(None, 1)[0].strip()
            if pid_str.isdigit():
                return int(pid_str)
    return None

# Returns {window_name: [wid, ...]} for layer-0 windows owned by the given PID across all spaces
def _windows_by_name_for_pid(owner_pid: int) -> Dict[str, List[int]]:
    arr = _CG.CGWindowListCopyWindowInfo(_CGW_LIST_ALL, _CGW_NULL_WID)
    out: Dict[str, List[int]] = {}
    for i in range(_cf_count(arr)):
        d = _cf_at(arr, i)
        if _dict_long(d, "kCGWindowOwnerPID") != owner_pid: continue
        if _dict_long(d, "kCGWindowLayer") != 0: continue
        wid  = _dict_long(d, "kCGWindowNumber")
        name = _dict_str(d, "kCGWindowName")
        if wid is None or name is None: continue
        out.setdefault(name, []).append(wid)
    return out

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

def _read_cwd_uuid_map() -> Dict[str, str]:
    if not _CWD_UUID_FILE.exists():
        return {}
    try:
        return json.loads(_CWD_UUID_FILE.read_text())
    except Exception:
        return {}

# AppleScript one-call → {uuid: window_name}
def _ghostty_uuid_to_window_name() -> Dict[str, str]:
    osa = (
        'tell application "Ghostty"\n'
        '  set out to ""\n'
        '  repeat with w in every window\n'
        '    set wname to (name of w) as text\n'
        '    repeat with t in every tab of w\n'
        '      try\n'
        '        set out to out & wname & "|||" & (id of terminal of t) & ASCII character 10\n'
        '      end try\n'
        '    end repeat\n'
        '  end repeat\n'
        '  return out\n'
        'end tell'
    )
    r = subprocess.run(['osascript', '-e', osa], capture_output=True, text=True, timeout=6)
    if r.returncode != 0:
        return {}
    out: Dict[str, str] = {}
    for line in r.stdout.strip().split('\n'):
        p = line.strip().split('|||')
        if len(p) == 2:
            out[p[1]] = p[0]
    return out

# --- public ops ---

# Returns (space_id, desktop_no) for the caller's Main session, or (None, None) on failure.
# Strategy: parent-walk → claude pid → claude's cwd via lsof → cwd-uuid map → AppleScript window name
# → CGWindowList lookup by ghostty pid → CGSCopySpacesForWindows.
def find_caller_main_space(caller_pid: int) -> Tuple[Optional[int], Optional[int]]:
    claude_pid = _find_claude_ancestor(caller_pid)
    if not claude_pid: return None, None
    cwd = _cwd_of_pid(claude_pid)
    if not cwd: return None, None
    uuid = _read_cwd_uuid_map().get(cwd)
    if not uuid: return None, None
    win_name = _ghostty_uuid_to_window_name().get(uuid)
    if not win_name: return None, None
    g_pid = _ghostty_pid()
    if not g_pid: return None, None
    wids = _windows_by_name_for_pid(g_pid).get(win_name, [])
    if len(wids) != 1: return None, None   # ambiguity → fail safely
    cid = _CG.CGSMainConnectionID()
    spaces = _spaces_for_wid(cid, wids[0])
    if not spaces: return None, None
    space_id = spaces[0]
    space_map, _ = _build_space_map(cid)
    desktop_no = space_map.get(space_id, (None, None))[1]
    return space_id, desktop_no

# Snapshot windows of owner_name, run callback, poll up to timeout_secs for NEW windows,
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

def _cli_find_caller_desktop(caller_pid: int) -> int:
    sid, dno = find_caller_main_space(caller_pid)
    if sid is None:
        print("none", file=sys.stderr)
        return 1
    print(f"{sid} {dno}")
    return 0

# Marker file is written BEFORE the open; bash invokes `wait-and-move` AFTER the open with
# the same marker so we can read the snapshot. Avoids race where snapshot happens between
# open-launch and window-appear.
def _cli_wait_and_move(caller_pid: int, owner_name: str, timeout: float) -> int:
    sid, _dno = find_caller_main_space(caller_pid)
    if sid is None:
        print("caller-main-not-found", file=sys.stderr)
        return 1
    n = wait_for_new_windows_and_move(owner_name, sid, timeout_secs=timeout)
    if n == 0:
        print("no-new-window", file=sys.stderr)
        return 1
    print(f"moved {n} window(s) to space {sid}")
    return 0

def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    cmd = sys.argv[1]
    if cmd == 'find-caller-desktop':
        if len(sys.argv) != 3: return 2
        return _cli_find_caller_desktop(int(sys.argv[2]))
    if cmd == 'wait-and-move':
        if len(sys.argv) < 4: return 2
        caller_pid = int(sys.argv[2])
        owner_name = sys.argv[3]
        timeout = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0
        return _cli_wait_and_move(caller_pid, owner_name, timeout)
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2

if __name__ == '__main__':
    sys.exit(main())
