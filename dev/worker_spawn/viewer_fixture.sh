# INFRASTRUCTURE

FAKE_GHOSTTY_VERSION="1.3.1"
FAKE_GHOSTTY_COMMIT="fixture01"

# FUNCTIONS

install_fake_ghostty_app() {
    VIEWER_SOURCE_APP="$STRAND_DIR/Ghostty.app"
    VIEWER_SIGN_LOG="$STRAND_DIR/codesign.log"
    : > "$VIEWER_SIGN_LOG"
    write_fake_ghostty_app "$FAKE_GHOSTTY_COMMIT"
    cat > "$STRAND_DIR/bin/codesign" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$VIEWER_SIGN_LOG"
STUB
    chmod +x "$STRAND_DIR/bin/codesign"
    export VIEWER_SOURCE_APP
}

write_fake_ghostty_app() {
    local commit="$1"
    mkdir -p "$VIEWER_SOURCE_APP/Contents/MacOS"
    printf '#!/bin/sh\nexit 0\n' > "$VIEWER_SOURCE_APP/Contents/MacOS/ghostty"
    chmod +x "$VIEWER_SOURCE_APP/Contents/MacOS/ghostty"
    cat > "$VIEWER_SOURCE_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.mitchellh.ghostty</string>
    <key>CFBundleName</key><string>Ghostty</string>
    <key>CFBundleDisplayName</key><string>Ghostty</string>
    <key>CFBundleShortVersionString</key><string>$FAKE_GHOSTTY_VERSION</string>
    <key>GhosttyCommit</key><string>$commit</string>
    <key>LSEnvironment</key><dict><key>GHOSTTY_MAC_LAUNCH_SOURCE</key><string>app</string></dict>
</dict>
</plist>
PLIST
}
