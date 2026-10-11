# Worker viewer windows that never take focus: shim-injected Ghostty copy (2026-10-11)

Continues the dead-end analysis of the earlier viewer-background entry in this area. Read that one for the measured failures of `activate`-less AppleScript and `open -g <file>`.

## Requirement and result

Each worker gets one visible Ghostty window; Ghostty must not become frontmost and the focused window of the user must stay where it is, also while the user types in a Ghostty window. No focus restore afterwards (rejected: keystrokes go astray for about 200 ms). `WORKER_NO_VIEWER=1` is not a default.

Shipped on branch `viewerbg2` (not published): viewer windows are created in a separate Ghostty process, a patched copy of `Ghostty.app` with its own bundle id `com.brunowinter.ghostty-viewer`, in which the app's own `NSApp.activate` calls are swallowed.

## Upstream facts (checked by the orchestrator on 2026-10-11)

- Upstream Ghostty has an open issue since 2026-03-13 titled "macOS: AppleScript new window/new tab implicitly activates Ghostty". The maintainer moved the window fix to 1.3.2, which is unreleased (latest tag 1.3.1; installed here: 1.3.1, commit `332b2aefc`).
- `main` at commit `24da727` (2026-10-10) still calls `NSApp.activate(ignoringOtherApps: true)` in `TerminalController.newWindow`. A contributor fix (commit `d4b31fd`, a gate flag for AppleScript callers) is not merged.
- A discussion asking for "open a window without pulling focus" has no answer. Another confirms that `open -g` only avoids the initial window (it is created in `applicationDidBecomeActive`).
- Consequence: this whole mechanism is a stopgap. See "Removal" below.

## Why a copy with a shim (decision path)

Ghostty source (`/tmp/ghostty-src`, HEAD `24da727`) calls activate in `newWindow` (TerminalController.swift:310), `newTab` (:515), AppleScript `activate window` (ScriptWindow.swift:189), `focusSurface` (BaseTerminalController.swift:328) and several AppDelegate paths. A window created inside the main Ghostty process therefore always activates it.

- `LSUIElement` alone was rejected: `AppDelegate.swift:841` calls `setActivationPolicy(.regular)` on every config load (`macos-hidden` defaults to `never`), and an accessory app can still be activated explicitly. Never measured; rejected by source reading, so the shim path was measured instead.
- Chosen: copy `Ghostty.app`, new bundle id and display name, ad-hoc re-sign, and inject `viewer_shim.dylib` via `LSEnvironment` `DYLD_INSERT_LIBRARIES`. The re-sign drops the hardened-runtime flag (`flags=0x10000(runtime)` on the original), which is what makes the DYLD variable honoured. The dylib replaces `-[NSApplication activateIgnoringOtherApps:]` and `-[NSApplication activate]` with a logging no-op. `/Applications/Ghostty.app` is never touched.
- One shared instance of the copy serves all workers; windows are created by AppleScript `new window` addressed by `application id`. `open -n` per worker was rejected: several processes with one bundle id make `tell application id` ambiguous, the same trap as the old `open -na Ghostty.app`.
- The original plist already has an `LSEnvironment` dict (`GHOSTTY_MAC_LAUNCH_SOURCE=app`). `PlistBuddy Add :LSEnvironment dict` fails with "Entry Already Exists"; only the keys are added.

## Files (iterative-dev)

- `src/spawn/viewer_app.sh`: orchestrator `prepare_viewer_app` = lock, build if stale, launch if stopped. Copy path `~/Library/Application Support/iterative-dev/GhosttyViewer.app`. Staleness is the stamp `<CFBundleShortVersionString>-<GhosttyCommit>` of the installed Ghostty, stored as `ViewerSourceStamp` in the copy's `Info.plist`. A `mkdir` lock serialises build and launch so 20 parallel spawns build once and launch once; the build happens in a staging directory and is moved into place. A running old copy keeps running until its last window closes.
- `src/spawn/viewer_shim.m`: the shim. Writes one line per event (`installed ...`, `swallowed ...`) to `viewer-shim.log` next to the copy.
- `src/spawn/worker_io.sh` `open_tmux_viewer`: `prepare_viewer_app`, then one `osascript` on `application id "com.brunowinter.ghostty-viewer"` with `new window`, `input text "tmux attach -t <session>; exit"`, `send key "enter"`. No `activate`. The `ghostty +version` branch and the `open -na` branch are gone. `tmux_spawn.sh` and `worker_revive.sh` are unchanged (`open_tmux_viewer "$session" &`).
- Launch arguments: `open -g -a <copy> --args --initial-window=false --quit-after-last-window-closed=true --window-save-state=never --auto-update=off`. `open` is only issued when no process of the copy runs (a second `open` on a running app sends a reopen event, which would open a window).
- Tripwires (abort with an error, no fallback): unreadable Ghostty version/commit, failed ditto/clang/codesign, lock held longer than 90 s, copy not scriptable within 20 s.

## Live runs (3 allowed, 3 used; each window set removed afterwards)

Desktop at the time: CotEditor frontmost with maximised window; main Ghostty not frontmost.

- Unusable first run (3 windows): my script used a bare `wait`, which also waited for the background sampler, so the open phase lasted 102 s and the user's own app switching leaked into the result. Raw samples were not kept. Do not use its verdict.
- Run 1 of 3, rerun with the fixed script, `dev/worker_spawn/measure_viewer_focus.sh 3`: frontmost app CotEditor before and after, main Ghostty front window `tab-group-aaa55b020` and focused terminal unchanged, 0 of 87 samples (20 ms interval, timestamped) differed from the start, 3 windows attached, all 3 found by the OSC2 marker lookup against the copy, 3 swallowed activates in the shim log. Open phase 1 s including the cold start of the copy.
- Run 2 of 3, menubar row click, `monitor-cc dev/menubar/live_viewer_row_click.py`: viewer tty mapped to the viewer app, terminal id mapped, `_focus_worker` brought `com.brunowinter.ghostty-viewer` to the front (before: CotEditor) and the viewer's focused terminal equalled the mapped id. This one takes focus on purpose.
- Run 3 of 3, burst `measure_viewer_focus.sh 20`: 20 windows opened in parallel in 4 s, frontmost app and main Ghostty state unchanged, 0 of 199 samples differed, 20 of 20 attached and found by the marker, 22 swallowed activates in the log (20 plus the two `installed` lines counted by the line-count delta).
- Raw samples of the last run: `dev/worker_spawn/md/measure_viewer_focus_samples.txt`, report `dev/worker_spawn/md/measure_viewer_focus.md`.

## Known limits (state on 2026-10-11)

- The strict case (main Ghostty frontmost while windows open) was not measured: during all runs CotEditor was frontmost. The script waits up to 30 s for Ghostty to be frontmost and then proceeds regardless. Hypothesis: the same, since the shim blocks the activate regardless of which app is front.
- Visibility: the new windows are on screen but ordered behind the windows of the frontmost app (an inactive app's windows land behind the active app's). With a maximised CotEditor, the viewer windows were visible only below it. The report line "0 viewer windows above every other app window" counts the frontmost app's window as "other"; read the window list instead.
- The cascade placed the 20 windows partly overlapping; no special positioning was done.
- A first-time macOS Automation consent prompt for the new bundle id (once for osascript's parent, once for the menubar) is expected for a fresh machine; none was observed here (hypothesis: prior grants were inherited via the responsible process).
- The row click activates the viewer through LaunchServices (`open -b`) in the menubar, because the shim also swallows AppleScript's own `activate`.

## Tests

- `dev/worker_spawn/verify_viewer_app.sh`: 7 strands (build, current skips rebuild, stale rebuild, 8 parallel prepares build and launch once, window script shape without `activate` or the main Ghostty, suppression, missing Ghostty). The dylib compile is real; Ghostty, open, osascript, pgrep and codesign are fixtures/stubs from `dev/worker_spawn/viewer_fixture.sh`.
- `dev/worker_spawn/verify_no_viewer.sh` and `test_spawn_flow.sh` adapted to the new call shape (spawn path polls for the call, because the build now takes about 1 s before the first osascript). In `test_spawn_flow.sh` the blocking stub now blocks the first osascript (the readiness probe), so "attach logged" is asserted after the release.
- monitor-cc: `dev/menubar/test_ghostty_viewer_app.py` (13 checks), `p5_run_all.py` green.

## Pitfalls hit

- Bare `wait` in a script with a background sampler waits for the sampler forever; wait on explicit pids.
- `lsappinfo info -all <asn>` dumps the full plist (tens of KB); use `-only bundleid`.
- `codesign` prints "replacing existing signature" on stderr during the build; harmless.
- The viewer needs no `ghostty +version` check any more; the version gate on the AppleScript API (>= 1.3) is implied by the installed app.

## Removal once upstream ships the fix (small revert)

Trigger: a Ghostty release in which AppleScript `new window` does not activate (the fix the maintainer moved to 1.3.2). Verify first on the plain path: run a variant of `measure_viewer_focus.sh` against the main Ghostty with the script below and check the frontmost app.

iterative-dev:
1. Delete `src/spawn/viewer_app.sh` and `src/spawn/viewer_shim.m`; remove the `source ".../viewer_app.sh"` line at the top of `worker_io.sh`.
2. In `open_tmux_viewer` drop `prepare_viewer_app || return 1` and replace the osascript target with the main app:
   ```
   tell application "Ghostty"
       set win to new window
       set t to terminal 1 of selected tab of win
       input text "tmux attach -t $session; exit" to t
       send key "enter" to t
   end tell
   ```
3. Delete `dev/worker_spawn/viewer_fixture.sh`, `verify_viewer_app.sh`, `measure_viewer_focus.sh`, `measure_viewer_focus_windows.js` and their `md/` outputs; remove the `install_fake_ghostty_app` lines from `verify_no_viewer.sh` and `test_spawn_flow.sh` (their osascript stubs then see the call at once).
4. Remove the copy: `rm -rf "$HOME/Library/Application Support/iterative-dev/GhosttyViewer.app" "$HOME/Library/Application Support/iterative-dev/viewer-shim.log"` and quit a running `GhosttyViewer` process.
5. Update `src/spawn/DOCS.md` and `dev/worker_spawn/DOCS.md` (module entries and LOC).
monitor-cc: the removal steps are in its process-docs, area `menubar`, entry of 2026-10-11 about the viewer app.
