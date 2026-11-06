#!/usr/bin/env bash

# FUNCTIONS

install_mitmdump_stub() {
    cat > "$STRAND_DIR/bin/mitmdump" <<'STUB'
#!/usr/bin/env bash
port=""
while [ $# -gt 0 ]; do
    [ "$1" = "-p" ] && port="$2"
    shift
done
[ -n "${STUB_ENV_LOG:-}" ] && echo "PROXY_PROJECT_PATH=${PROXY_PROJECT_PATH:-} MONITOR_CC_ROOT=${MONITOR_CC_ROOT:-}" >> "$STUB_ENV_LOG"
exec python3 -c "
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', int(sys.argv[1])))
s.listen(1)
time.sleep(600)
" "$port"
STUB
    chmod +x "$STRAND_DIR/bin/mitmdump"
}

install_monitor_root() {
    MONITOR_ROOT="$STRAND_DIR/monitor_root"
    mkdir -p "$MONITOR_ROOT/src/proxy"
    echo "# addon stub" > "$MONITOR_ROOT/src/proxy_addon.py"
    printf '#!/bin/bash\ncp "$(dirname "$0")/proxy_addon.py" "$1"\nmkdir -p "$2"\n' > "$MONITOR_ROOT/src/copy_proxy_live.sh"
    chmod +x "$MONITOR_ROOT/src/copy_proxy_live.sh"
}

write_proxy_marker() {
    local session_id="$1" port="$2"
    printf '%s\n%s\n%s\n' "$port" "fixture" "$MONITOR_ROOT" > "/tmp/.monitor_cc_proxy_${session_id}"
}
