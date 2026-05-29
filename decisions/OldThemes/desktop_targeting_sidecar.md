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
