#!/usr/bin/env bash

# INFRASTRUCTURE

_VIEWER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_VIEWER_APP_ID="com.brunowinter.ghostty-viewer"
_VIEWER_HOME_DIR="$HOME/Library/Application Support/iterative-dev"
_VIEWER_APP_PATH="$_VIEWER_HOME_DIR/GhosttyViewer.app"
_VIEWER_LOCK_DIR="$_VIEWER_HOME_DIR/viewer.lock"
_VIEWER_SHIM_LOG="$_VIEWER_HOME_DIR/viewer-shim.log"
_VIEWER_SHIM_SOURCE="$_VIEWER_LIB_DIR/viewer_shim.m"
_VIEWER_SOURCE_APP="${VIEWER_SOURCE_APP:-/Applications/Ghostty.app}"
_VIEWER_PLIST_BUDDY="/usr/libexec/PlistBuddy"
_VIEWER_LOCK_TIMEOUT_S=90
_VIEWER_READY_TIMEOUT_S=20

# ORCHESTRATOR

prepare_viewer_app() {
    _viewer_lock_acquire || return 1
    local rc=0
    _viewer_build_if_stale && _viewer_launch_if_stopped || rc=$?
    _viewer_lock_release
    return $rc
}

# FUNCTIONS

_viewer_lock_acquire() {
    mkdir -p "$_VIEWER_HOME_DIR"
    local deadline=$((SECONDS + _VIEWER_LOCK_TIMEOUT_S))
    while ! mkdir "$_VIEWER_LOCK_DIR" 2>/dev/null; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "ERROR: viewer lock $_VIEWER_LOCK_DIR still held after ${_VIEWER_LOCK_TIMEOUT_S}s" >&2
            return 1
        fi
        sleep 0.2
    done
}

_viewer_lock_release() {
    rmdir "$_VIEWER_LOCK_DIR"
}

_viewer_build_if_stale() {
    local stamp
    stamp=$(_viewer_source_stamp) || return 1
    if [ "$(_viewer_built_stamp)" = "$stamp" ]; then
        return 0
    fi
    _viewer_build "$stamp"
}

_viewer_source_stamp() {
    local plist="$_VIEWER_SOURCE_APP/Contents/Info.plist"
    local version commit
    version=$("$_VIEWER_PLIST_BUDDY" -c "Print :CFBundleShortVersionString" "$plist") || {
        echo "ERROR: cannot read the Ghostty version from $plist" >&2
        return 1
    }
    commit=$("$_VIEWER_PLIST_BUDDY" -c "Print :GhosttyCommit" "$plist") || {
        echo "ERROR: cannot read GhosttyCommit from $plist" >&2
        return 1
    }
    echo "${version}-${commit}"
}

_viewer_built_stamp() {
    "$_VIEWER_PLIST_BUDDY" -c "Print :ViewerSourceStamp" "$_VIEWER_APP_PATH/Contents/Info.plist" 2>/dev/null || true
}

_viewer_build() {
    local stamp="$1"
    local staging="$_VIEWER_APP_PATH.build.$$"
    rm -rf "$_VIEWER_APP_PATH".build.*
    ditto --noqtn "$_VIEWER_SOURCE_APP" "$staging" || return 1
    _viewer_rewrite_plist "$staging/Contents/Info.plist" "$stamp" || return 1
    _viewer_compile_shim "$staging/Contents/Frameworks/viewer_shim.dylib" || return 1
    _viewer_sign "$staging" || return 1
    rm -rf "$_VIEWER_APP_PATH"
    mv "$staging" "$_VIEWER_APP_PATH"
}

_viewer_rewrite_plist() {
    local plist="$1" stamp="$2"
    local dylib="$_VIEWER_APP_PATH/Contents/Frameworks/viewer_shim.dylib"
    "$_VIEWER_PLIST_BUDDY" \
        -c "Set :CFBundleIdentifier $_VIEWER_APP_ID" \
        -c "Set :CFBundleName Ghostty Viewer" \
        -c "Set :CFBundleDisplayName Ghostty Viewer" \
        -c "Add :ViewerSourceStamp string $stamp" \
        -c "Add :LSEnvironment:DYLD_INSERT_LIBRARIES string $dylib" \
        -c "Add :LSEnvironment:VIEWER_SHIM_LOG string $_VIEWER_SHIM_LOG" \
        "$plist" > /dev/null
}

_viewer_compile_shim() {
    local dylib="$1"
    mkdir -p "$(dirname "$dylib")"
    clang -dynamiclib -fobjc-arc -arch "$(uname -m)" -framework AppKit \
        -o "$dylib" "$_VIEWER_SHIM_SOURCE"
}

_viewer_sign() {
    local app="$1"
    codesign --force -s - "$app/Contents/Frameworks/viewer_shim.dylib" || return 1
    codesign --force --deep -s - "$app" || return 1
    codesign --verify --deep "$app"
}

_viewer_launch_if_stopped() {
    if _viewer_running; then
        return 0
    fi
    open -g -a "$_VIEWER_APP_PATH" --args \
        --initial-window=false \
        --quit-after-last-window-closed=true \
        --window-save-state=never \
        --auto-update=off || return 1
    _viewer_wait_ready
}

_viewer_running() {
    pgrep -f "$_VIEWER_APP_PATH/Contents/MacOS/" > /dev/null
}

_viewer_wait_ready() {
    local deadline=$((SECONDS + _VIEWER_READY_TIMEOUT_S))
    until osascript -e "tell application id \"$_VIEWER_APP_ID\" to count windows" > /dev/null 2>&1; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "ERROR: viewer app $_VIEWER_APP_ID not scriptable after ${_VIEWER_READY_TIMEOUT_S}s" >&2
            return 1
        fi
        sleep 0.2
    done
}
