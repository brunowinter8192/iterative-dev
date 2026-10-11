# Viewer window in the background: what was tried and why nothing shipped (2026-10-11)

## Task and requirement

`worker-cli spawn` opens a Ghostty window per worker (`open_tmux_viewer` in `src/spawn/worker_io.sh`, backgrounded from `spawn_claude_worker` and `worker_revive`). Requirement from the user: the window is visible, but Ghostty does not become the frontmost app and the user's focused window stays where it is. Trigger: on 2026-10-11 six workers were spawned in a loop and the windows popped to the front while the user was typing. `WORKER_NO_VIEWER=1` is not an acceptable default.

Pass criterion fixed with the user (stricter than "Ghostty is not frontmost", because the user usually types in a Ghostty window himself): frontmost app, Ghostty front window id and focused terminal id are identical before and after; the new window exists; it is attached to the tmux session; the menubar's OSC2 marker lookup finds it.

Outcome of this session: no implementation shipped. `worker_io.sh` is unchanged (the variant-A edit was reverted). Both levers tested live failed, and the source of Ghostty explains both failures.

## Status quo of the code (unchanged)

`open_tmux_viewer` on Ghostty >= 1.3 runs `osascript` with `tell application "Ghostty"`, `activate`, `set win to new window`, `input text "tmux attach -t <session>; exit"`, `send key "enter"`. Below 1.3 it runs `open -na Ghostty.app --args ... -e tmux attach -t <session>`. The version is read with `ghostty +version`.

## What the menubar needs from a viewer window (constraint on any solution)

Read in monitor-cc `src/menubar/ghostty.py` and `system.py`:
- `_ghostty_pid` takes the first process whose command line contains `Ghostty.app/Contents/MacOS`. `_ghostty_child_ttys` lists processes with `ppid == that pid` and a tty (the `login` process of each terminal).
- Each such tty is mapped to a terminal UUID by writing an OSC2 title marker to the tty and asking `tell application "Ghostty"` for `first terminal whose name is <marker>`.
- A worker row click finds the viewer tty by `ps` (`tmux attach -t <session>`, exact match on the argument after `-t`), maps it to the UUID and sends `focus terminal id` plus app-level `activate` to `Ghostty`.
- Consequence: a viewer window must live in the same Ghostty process and bundle as the main windows, or the menubar must be extended to query a second app. A window in another process is invisible to the current lookup and the row click becomes a no-op (`tty_unmapped`).
- `open -na Ghostty.app` (the old fallback) creates a second process with the same bundle id which then answers every `tell application "Ghostty"` and breaks click-to-focus for all windows. That path was removed from consideration; it is also dead weight now because Ghostty 1.3.1 is installed.

## Measurements (macOS, Ghostty 1.3.1, three runs allowed, two used)

Measurement script lived in `/tmp` (gone). Shape, so it can be rebuilt: create a throwaway tmux session `viewerbg-test-<pid>` running `sleep 600`; record before and after (0.5 s later) the frontmost app (`lsappinfo front` / `info -only name`), Ghostty `id of front window`, `id of focused terminal of selected tab of front window` and the window id list (read-only AppleScript, does not activate); sample `lsappinfo front` plus the Ghostty front/focused ids every 50 ms for 0.7 to 1.5 s around the open; then check `tmux list-clients`, `ps`, write an OSC2 marker to the client tty and look it up; kill the session and close the new window by id.

### Run 1: variant A (the osascript call without the `activate` line)

Frontmost before: CotEditor. Ghostty front window `tab-group-aaa55b2a0`, focused terminal `6F6D332F-...`.
- `osascript` duration 237 ms, rc 0.
- Frontmost after: Ghostty. Ghostty front window after: the new window `tab-group-ab0501400`, focused terminal `696598C6-...`, `AXFocusedWindow` = `tmux attach -t viewerbg-test-<pid>; exit`.
- Sampling every 50 ms over 1.5 s (30 samples): 26 Ghostty frontmost, 4 CotEditor. The first four samples (about 200 ms) still showed CotEditor, then Ghostty took over.
- Window existed and was attached (`/dev/ttys037 viewerbg-test-<pid>`).
- Result: FAIL. Removing `activate` does not help; `new window` itself activates Ghostty and gives the new window focus. After closing the test window, Ghostty's front window returned to the old one, but Ghostty stayed the frontmost app. CotEditor was restored by hand with System Events (`set frontmost of process "CotEditor" to true`).

### Run 2: `open -g -b com.mitchellh.ghostty <script>.command` (self-deleting executable script, `exec tmux attach -t <session>`)

State set by the script: CotEditor frontmost (it was Ghostty before; the script set CotEditor).
- `open` duration 67 ms, rc 0.
- Frontmost app before/after: CotEditor / CotEditor. Ghostty front window `tab-group-aa70495e0` and focused terminal `9103DF2F-...` unchanged in all 14 samples.
- Window ids before and after: 9 and 9, no new id. `tmux list-clients`: 0 clients. `ps` showed no `tmux attach -t <session>`. The `.command` file was still on disk (the script never ran). The OSC2 check could not be done (no client).
- Result: FAIL (no window). Focus was unchanged only because nothing happened.
- `log show` for process `ghostty` around the run showed only TCC, CoreSpotlight and XPC noise, no error.
- Run 3 (same lever with Ghostty frontmost) was not executed; the source below made it pointless.

Count of runs: 2 of the 3 allowed were used. A manual no-op smoke attempt earlier (a `source` of the measurement script that stopped on a quoting error before doing anything) opened no window and is not counted.

## Source evidence (read by the user and re-read by this worker)

Clone at `/tmp/ghostty-src` (HEAD `24da727`, 2026-10-10). The installed Ghostty is 1.3.1, commit `332b2aefc` (from `GhosttyCommit` in its `Info.plist`). The clone is newer than the installed build; the quoted code may differ in detail from 1.3.1, but both runs behave exactly as the code says.

1. `macos/Sources/App/AppDelegate.swift`, `application(_:openFile:)`: for any non-directory file it sets `requiresConfirm = true` ("Unconditionally require confirmation in the file execution case", reason given in the comment: a sandbox escape is possible when a sandboxed app `open`s a non-sandboxed one). It then shows an app-wide `NSAlert` ("Allow Ghostty to execute ...?", buttons Allow and Cancel) via `runModal()` before creating any terminal. Executing a file also sets `initialInput` to `<quoted filename>; exit\n` and `waitAfterCommand = true`. Explains run 2: the script was never run; no window appeared until someone answers the alert.
2. `macos/Sources/Features/Terminal/TerminalController.swift`, static `newWindow(_:withBaseConfig:withParent:)`: the presentation closure ends with `NSApp.activate(ignoringOtherApps: true)`, commented "All new_window actions force our app to be active, so that the new window is focused and visible". Every window created inside the running Ghostty process goes through this: AppleScript `new window`, document open, services, the new-window action. Explains run 1, and means no AppleScript or `open` variant against the running process can avoid activation, with or without `activate` in the script.
3. `application(_:openFile:)` also has a `commandLineOpenFileFilter` and a `macosDockDropBehavior` branch (new tab or new window); not relevant to the failure.

## Pending confirmation alert from run 2 (checked after the runs)

Looked for it without clicking anything:
- System Events lists 3 windows of the process `Ghostty` on the current space, all `AXStandardWindow` (no `AXDialog`, no sheet).
- The CoreGraphics window list (all spaces) has 15 Ghostty-owned windows, none with a name matching "Allow" or "execute". Caveat: an `NSAlert` window normally has no title and `kCGWindowName` may be stripped, so this is weak evidence.
- Ghostty keeps answering AppleScript normally (window count 9 earlier, queries return), which an open modal alert would probably not allow, but that is a hypothesis, not observed.
- No `.worker-viewer-*.command` file and no leftover test tmux session exist.
Reading: no pending alert was found; not proven absent on spaces the Accessibility API cannot see.

## Dead ends, with the reason (do not repeat)

- Variant A (drop `activate`): run 1.
- `open -g -b com.mitchellh.ghostty <file>`: run 2 plus the source (confirmation alert; and even after "Allow" the same `newWindow` activation would run).
- Restoring focus after the fact (activate the previous app again, or `focus terminal id` on the old window): rejected by the user. It leaves a window of about 200 ms in which keystrokes go to the wrong window.
- `open -na Ghostty.app`: second process with the same bundle id, breaks AppleScript and click-to-focus (known from monitor-cc).
- Any call into the running Ghostty (AppleScript, services, `open` with documents): activates, per `newWindow`.

## Facts from the websearch project that were considered

- Chrome is launched with `open -g -n -a <path to .app> --args ...`: `-g` stops activation at the launch moment only. Windows created later by the same instance can still activate it (playwright#42343), so the project also runs a focus-steal watchdog that re-activates the previous app (the approach the user rejected here).
- Camoufox: `LSUIElement=true` in the bundle's `Info.plist` made macOS never activate that app; 46 of 46 poll samples had the terminal frontmost. That works because Firefox itself issued no explicit activate once `-foreground` was dropped.
- `open --hide` exists as a further lever; not used there.
- Direct transfer to Ghostty is not given: Ghostty calls `NSApp.activate(ignoringOtherApps: true)` explicitly. An explicit activate may still activate an accessory app (`LSUIElement`); that was never tested.

## Remaining untested options

1. A separate Ghostty process with its own bundle identity, launched with `open -g` and `LSUIElement=true`. Prototype: copy `/Applications/Ghostty.app` (62 MB), change `CFBundleIdentifier`, `CFBundleName` and display name via PlistBuddy, set `LSUIElement`, `codesign --force --deep -s -`. Launch per worker with `open -g -n -a <copy> --args --quit-after-last-window-closed=true --window-save-state=never -e tmux attach -t <session>` (the window exists at launch time, so no `newWindow` call from AppleScript), or one shared instance. Open questions: (a) does the `NSApp.activate` in `newWindow` still activate an accessory app (the main risk, untested); (b) does the initial window at launch go through `newWindow` and so activate too; (c) the user's `~/.config/ghostty/config` is shared, which is wanted. Cost: the menubar must be extended to see the viewer (its pid does not contain `Ghostty.app/Contents/MacOS` in the path, so `_ghostty_pid` would not confuse it, but the OSC2 lookup and `focus terminal id` go to `Ghostty` only); the copy goes stale after every Ghostty update and has to be re-signed; clicking a window of an accessory app to give it keyboard focus was never tested.
2. A different terminal app for viewers (anything that creates windows without self-activating when launched with `open -g`). Not examined; same menubar cost as option 1 (tty to window lookup would need a different mechanism).
3. Lazy viewer: no window at spawn; the menubar opens the viewer when the user clicks the worker row, which is a user action and so may take focus. Changes the "I want to see the windows" behaviour; needs the user's decision and a menubar change. No code written.

## Pitfalls hit in this session (for a successor)

- Do not `source` a measurement script to "check it": it is a script, not a library, and runs. A stray `source` ran into a quoting error before doing harm; check with `bash -n`.
- zsh treats a leading `=====` argument as a command (`= not found`); use `-----` as echo separators.
- AppleScript `ids as text` joins without a separator unless `AppleScript's text item delimiters` is set first.
- `log` is shadowed in the tool shell; use `/usr/bin/log show`.
- Put AppleScript with apostrophes into a quoted heredoc (`osascript <<'AS'`), not a single-quoted `-e` string.
- A window opened by `open -g` into a Ghostty that is already frontmost would be the harder case (the new window becomes key in the active app); run 3 was meant to measure it and was cancelled.

## State at the end

`git -C <worktree> status` is clean apart from this file; `worker_io.sh` is identical to `integration`. Nothing was published and the plugin cache is untouched.
