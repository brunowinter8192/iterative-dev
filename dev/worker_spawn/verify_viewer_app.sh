#!/usr/bin/env bash

# INFRASTRUCTURE

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../strand_runner.sh"
source "$SCRIPT_DIR/viewer_fixture.sh"

STRANDS=(build_missing build_current build_stale build_parallel window_script suppressed source_missing)
VIEWER_ID="com.brunowinter.ghostty-viewer"

# ORCHESTRATOR

verify_viewer_app_workflow() {
    strand_main "$@"
}

# FUNCTIONS

_install_stubs() {
    install_fake_ghostty_app
    OSA_LOG="$STRAND_DIR/osascript.log"
    OPEN_LOG="$STRAND_DIR/open.log"
    RUNNING_MARKER="$STRAND_DIR/viewer_running"
    : > "$OSA_LOG"
    : > "$OPEN_LOG"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$OSA_LOG" > "$STRAND_DIR/bin/osascript"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\ntouch "%s"\n' "$OPEN_LOG" "$RUNNING_MARKER" > "$STRAND_DIR/bin/open"
    printf '#!/usr/bin/env bash\n[ -e "%s" ]\n' "$RUNNING_MARKER" > "$STRAND_DIR/bin/pgrep"
    chmod +x "$STRAND_DIR/bin/osascript" "$STRAND_DIR/bin/open" "$STRAND_DIR/bin/pgrep"
    source "$PLUGIN_ROOT/src/spawn/worker_io.sh"
}

_lines() {
    wc -l < "$1" | tr -d ' '
}

_plist_value() {
    /usr/libexec/PlistBuddy -c "Print $1" "$_VIEWER_APP_PATH/Contents/Info.plist" 2>&1
}

strand_build_missing() {
    _install_stubs
    prepare_viewer_app
    check "prepare_viewer_app succeeds" "$([ $? -eq 0 ] && echo ok || echo failed)"
    check "copy has the viewer bundle id" \
        "$([ "$(_plist_value :CFBundleIdentifier)" = "$VIEWER_ID" ] && echo ok || echo "id=$(_plist_value :CFBundleIdentifier)")"
    check "copy injects the shim dylib via LSEnvironment" \
        "$([ "$(_plist_value :LSEnvironment:DYLD_INSERT_LIBRARIES)" = "$_VIEWER_APP_PATH/Contents/Frameworks/viewer_shim.dylib" ] && echo ok || echo "dyld=$(_plist_value :LSEnvironment:DYLD_INSERT_LIBRARIES)")"
    check "copy keeps the original LSEnvironment entry" \
        "$([ "$(_plist_value :LSEnvironment:GHOSTTY_MAC_LAUNCH_SOURCE)" = "app" ] && echo ok || echo lost)"
    check "shim dylib was compiled" "$([ -f "$_VIEWER_APP_PATH/Contents/Frameworks/viewer_shim.dylib" ] && echo ok || echo missing)"
    check "copy is signed (dylib, app, verify)" "$([ "$(_lines "$VIEWER_SIGN_LOG")" = "3" ] && echo ok || echo "sign calls=$(_lines "$VIEWER_SIGN_LOG")")"
    check "viewer launched in the background without activation" \
        "$(grep -q -- "-g -a $_VIEWER_APP_PATH --args --initial-window=false" "$OPEN_LOG" && echo ok || echo "open log: $(cat "$OPEN_LOG")")"
}

strand_build_current() {
    _install_stubs
    prepare_viewer_app
    prepare_viewer_app
    check "second prepare does not rebuild" "$([ "$(_lines "$VIEWER_SIGN_LOG")" = "3" ] && echo ok || echo "sign calls=$(_lines "$VIEWER_SIGN_LOG")")"
    check "second prepare does not relaunch a running viewer" "$([ "$(_lines "$OPEN_LOG")" = "1" ] && echo ok || echo "open calls=$(_lines "$OPEN_LOG")")"
}

strand_build_stale() {
    _install_stubs
    prepare_viewer_app
    write_fake_ghostty_app "fixture02"
    prepare_viewer_app
    check "changed Ghostty commit triggers a rebuild" "$([ "$(_lines "$VIEWER_SIGN_LOG")" = "6" ] && echo ok || echo "sign calls=$(_lines "$VIEWER_SIGN_LOG")")"
    check "rebuilt copy carries the new stamp" \
        "$([ "$(_plist_value :ViewerSourceStamp)" = "$FAKE_GHOSTTY_VERSION-fixture02" ] && echo ok || echo "stamp=$(_plist_value :ViewerSourceStamp)")"
}

strand_build_parallel() {
    _install_stubs
    local i pids=()
    for i in 1 2 3 4 5 6 7 8; do
        prepare_viewer_app &
        pids+=($!)
    done
    wait "${pids[@]}"
    check "8 parallel prepares build once" "$([ "$(_lines "$VIEWER_SIGN_LOG")" = "3" ] && echo ok || echo "sign calls=$(_lines "$VIEWER_SIGN_LOG")")"
    check "8 parallel prepares launch once" "$([ "$(_lines "$OPEN_LOG")" = "1" ] && echo ok || echo "open calls=$(_lines "$OPEN_LOG")")"
    check "no lock directory left behind" "$([ ! -e "$_VIEWER_LOCK_DIR" ] && echo ok || echo "lock stuck")"
}

strand_window_script() {
    _install_stubs
    open_tmux_viewer "worker-demo-session"
    local script
    script=$(cat "$OSA_LOG")
    check "window is created in the viewer app by bundle id" \
        "$(grep -q "tell application id \"$VIEWER_ID\"" <<<"$script" && echo ok || echo "script: $script")"
    check "window attaches to the worker session" \
        "$(grep -q "input text \"tmux attach -t worker-demo-session; exit\"" <<<"$script" && echo ok || echo "no attach line")"
    check "script contains no activate" "$(grep -qw "activate" <<<"$script" && echo "activate present" || echo ok)"
    check "script never addresses the main Ghostty" "$(grep -q 'application "Ghostty"' <<<"$script" && echo "main Ghostty addressed" || echo ok)"
}

strand_suppressed() {
    _install_stubs
    WORKER_NO_VIEWER=1 open_tmux_viewer "worker-demo-session"
    check "WORKER_NO_VIEWER builds nothing" "$([ ! -e "$_VIEWER_APP_PATH" ] && echo ok || echo "copy built")"
    check "WORKER_NO_VIEWER calls neither open nor osascript" \
        "$([ "$(_lines "$OPEN_LOG")" = "0" ] && [ "$(_lines "$OSA_LOG")" = "0" ] && echo ok || echo "calls made")"
}

strand_source_missing() {
    _install_stubs
    rm -rf "$VIEWER_SOURCE_APP"
    open_tmux_viewer "worker-demo-session" 2> "$STRAND_DIR/err.txt"
    local rc=$?
    check "missing Ghostty app makes open_tmux_viewer fail" "$([ "$rc" -ne 0 ] && echo ok || echo "rc=0")"
    check "failure names the unreadable Ghostty plist" \
        "$(grep -q "cannot read the Ghostty version" "$STRAND_DIR/err.txt" && echo ok || echo "stderr: $(cat "$STRAND_DIR/err.txt")")"
    check "no window script was run" "$([ "$(_lines "$OSA_LOG")" = "0" ] && echo ok || echo "osascript called")"
}

verify_viewer_app_workflow "$@"
