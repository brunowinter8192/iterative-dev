# dev/desktop_targeting/

## Role

Probe for macOS Space-move APIs, backing the desktop-targeting investigation (see `process-docs/desktop_targeting/`).

## Modules

### probe.py (113 LOC)

**Purpose:** Orchestrates the space-move API probe (macOS 15.7) — tests CGS/SLS move APIs from an unprivileged process.
**Usage:** `python3 dev/desktop_targeting/probe.py`
**Output:** `dev/desktop_targeting/md/space_move_probe_2026-05-29.md`
**Called by:** run manually.
**Calls out:** `objc_bridge`, `spaces`, `window_probe`, `move_test` (this directory, imported by bare module name — the script's own directory is on `sys.path[0]` for direct `python3 probe.py` execution, no package/`__init__.py` involved).

---

### objc_bridge.py (131 LOC)

**Purpose:** Low-level ctypes/ObjC bridge — CoreGraphics/SkyLight library handles, `objc_msgSend` helpers, CF container accessors.
**Reads:** nothing.
**Writes:** nothing (debug lines to stdout when `_DEBUG` is set).
**Called by:** `spaces.py`, `window_probe.py`, `move_test.py`, `probe.py`.
**Calls out:** CoreGraphics.framework, SkyLight.framework (private), libobjc (via ctypes).

---

### spaces.py (78 LOC)

**Purpose:** Enumerates Mission Control Spaces per display and selects the move target (explicit `--space` override or first non-active Space on the active display).
**Reads:** live space state via `objc_bridge`.
**Writes:** stdout (Space overview).
**Called by:** `probe.py`.
**Calls out:** `objc_bridge`.

---

### window_probe.py (86 LOC)

**Purpose:** Creates, detects (before/after window-list diff), and closes the TextEdit window used as each test's move target.
**Reads:** live window list via `objc_bridge`.
**Writes:** stdout; opens/closes a real TextEdit window as a side effect.
**Called by:** `probe.py`.
**Calls out:** `objc_bridge`, `osascript`/TextEdit (via subprocess).

---

### move_test.py (107 LOC)

**Purpose:** Performs one move (CGS or SLS API) and verifies the window's resulting Space via two independent readback APIs.
**Reads:** live window/space state via `objc_bridge`.
**Writes:** stdout.
**Called by:** `probe.py`.
**Calls out:** `objc_bridge`.

## State

`objc_bridge._DEBUG` is the one piece of cross-module mutable state: `probe.py`'s `main()` sets it directly (`objc_bridge._DEBUG = args.debug`) after parsing `--debug`, rather than through a setter function — a plain module-attribute assignment, not a new public API. `objc_bridge._dbg()` reads it to decide whether to print raw API values; `window_probe.py` and `move_test.py` both call `_dbg()` but never touch the flag itself.
