# dev/desktop_targeting/

## Role

Probe for macOS Space-move APIs, backing the desktop-targeting investigation (see `process-docs/desktop_targeting/`).

## Public Interface

Invoked directly: `python3 dev/desktop_targeting/probe.py [--space <id>] [--debug]`. No `__init__.py` — `objc_bridge`, `spaces`, `window_probe`, `move_test` import each other by bare module name (the script's own directory is on `sys.path[0]` for direct execution).

## Flow

CLI args in → space discovery (`spaces`) and TextEdit test-window lifecycle (`window_probe`) → CGS/SLS move + verify (`move_test`) → PASS/FAIL summary out (stdout).

## Modules

### probe.py (111 LOC)

**Purpose:** Orchestrates the space-move API probe (macOS 15.7) — tests CGS/SLS move APIs from an unprivileged process.
**Reads:** CLI args (`--space`, `--debug`).
**Writes:** stdout.
**Called by:** run manually.
**Calls out:** `objc_bridge`, `spaces`, `window_probe`, `move_test`.

---

### objc_bridge.py (121 LOC)

**Purpose:** Low-level ctypes/ObjC bridge — CoreGraphics/SkyLight library handles, `objc_msgSend` helpers, CF container accessors.
**Reads:** nothing.
**Writes:** nothing (debug lines to stdout when the debug flag is set).
**Called by:** `spaces.py`, `window_probe.py`, `move_test.py`, `probe.py`.
**Calls out:** CoreGraphics.framework, SkyLight.framework (private), libobjc (via ctypes).

---

### spaces.py (70 LOC)

**Purpose:** Enumerates Mission Control Spaces per display and selects the move target (explicit `--space` override or first non-active Space on the active display).
**Reads:** live space state via `objc_bridge`.
**Writes:** stdout (Space overview).
**Called by:** `probe.py`.
**Calls out:** `objc_bridge`.

---

### window_probe.py (76 LOC)

**Purpose:** Creates, detects (before/after window-list diff), and closes the TextEdit window used as each test's move target.
**Reads:** live window list via `objc_bridge`.
**Writes:** stdout; opens/closes a real TextEdit window as a side effect.
**Called by:** `probe.py`.
**Calls out:** `objc_bridge`, `osascript`/TextEdit (via subprocess).

---

### move_test.py (85 LOC)

**Purpose:** Performs one move (CGS or SLS API) and verifies the window's resulting Space via two independent readback APIs.
**Reads:** live window/space state via `objc_bridge`.
**Writes:** stdout.
**Called by:** `probe.py`.
**Calls out:** `objc_bridge`.

## State

The debug flag in `objc_bridge.py` is the one piece of cross-module mutable state. `probe.py` sets it directly after parsing the debug option, as a plain module-attribute assignment rather than through a setter. The bridge's debug print reads it; `window_probe.py` and `move_test.py` call that print but never touch the flag.
