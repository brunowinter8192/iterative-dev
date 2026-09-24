#!/usr/bin/env bash
# worker_proxy.sh — worker-specific mitmproxy setup shared by spawn and revive. Sourced by tmux_spawn.sh.

# _worker_proxy_setup NAME PROJECT_PATH
#   Sets up a worker-specific mitmproxy if the Monitor_CC proxy marker is present.
#   The proxy is needed so the worker's claude --resume hits the same per-project
#   marker prefix as the main session — without it the prompt-cache prefix changes
#   and Anthropic sees a full cache miss, forcing a complete re-upload of context.
#
#   Reads /tmp/.monitor_cc_proxy_<session_id> (line 1 = main_port, line 3 = MONITOR_CC_ROOT).
#   Starts mitmdump in background on (main_port + N) with a per-worker live-copy of
#   the addon (live-copy prevents hot-reload bashing the main proxy).
#
#   Writes results to global vars (consumed by both spawn and revive):
#     WORKER_PROXY_PID            — pid of mitmdump or empty if no proxy
#     WORKER_PROXY_ENV_PREFIX     — env-var string to prefix the claude command, or empty
#     WORKER_PROXY_LIVE_ADDON     — path to live-copy addon file (for cleanup) or empty
#     WORKER_PROXY_LIVE_DIR       — path to live-copy proxy dir (for cleanup) or empty
#
#   The live-copy paths carry a per-call unique suffix (name + epoch + pid), so a previous
#   worker's asynchronous runner-trap cleanup can only delete its own copies (2026-09-23:
#   kill + immediate respawn under one name lost the new worker's addon).
#   After starting mitmdump it waits until the port listens; if the proxy does not come up
#   it cleans up and returns 1.
#   Returns 0 when no proxy is active or the proxy is ready; 1 when the proxy failed to start
#   (caller must refuse to spawn).
_worker_proxy_setup() {
    local name="$1"
    local project_path="$2"

    WORKER_PROXY_PID=""
    WORKER_PROXY_ENV_PREFIX=""
    WORKER_PROXY_LIVE_ADDON=""
    WORKER_PROXY_LIVE_DIR=""

    local proxy_project_path proxy_session_id proxy_marker
    proxy_project_path=$(_proxy_project_root "$project_path")
    proxy_session_id=$(_proxy_session_id "$proxy_project_path")
    proxy_marker="/tmp/.monitor_cc_proxy_${proxy_session_id}"
    [ ! -f "$proxy_marker" ] && return 0

    local main_port monitor_cc_root
    main_port=$(sed -n '1p' "$proxy_marker")
    monitor_cc_root=$(sed -n '3p' "$proxy_marker")
    if [ -z "$monitor_cc_root" ] || [ ! -d "$monitor_cc_root" ]; then
        return 0
    fi

    local worker_port worker_log_id log_dir
    worker_port=$(_proxy_free_port "$main_port")
    worker_log_id="worker_${proxy_session_id}_${name}_$(date +%s)"
    log_dir="${monitor_cc_root}/src/logs"
    mkdir -p "$log_dir"

    _proxy_launch "$name" "$monitor_cc_root" "$worker_port" "$worker_log_id" "$proxy_project_path"
    if ! _worker_proxy_wait_ready "$WORKER_PROXY_PID" "$worker_port"; then
        _proxy_fail_cleanup "$name" "$worker_port" "$log_dir" "$worker_log_id"
        return 1
    fi
    WORKER_PROXY_ENV_PREFIX="HTTPS_PROXY=http://localhost:${worker_port} NODE_EXTRA_CA_CERTS=~/.mitmproxy/mitmproxy-ca-cert.pem SSL_CERT_FILE=~/.mitmproxy/combined-ca.pem REQUESTS_CA_BUNDLE=~/.mitmproxy/combined-ca.pem "
    return 0
}

# _proxy_project_root PROJECT_PATH
#   Strips the worktree suffix to get the original project path used for the marker hash.
_proxy_project_root() {
    local project_path="$1"
    if [[ "$project_path" == */.claude/worktrees/* ]]; then
        echo "${project_path%%/.claude/worktrees/*}"
    else
        echo "$project_path"
    fi
}

# _proxy_session_id PROJECT_ROOT
#   First 8 hex chars of the md5 of the project root (md5 on macOS, md5sum elsewhere).
_proxy_session_id() {
    local root="$1"
    if command -v md5 >/dev/null 2>&1; then
        echo -n "$root" | md5 | head -c 8
    else
        echo -n "$root" | md5sum | head -c 8
    fi
}

# _proxy_free_port MAIN_PORT
#   Echoes the first port above MAIN_PORT with no TCP listener.
_proxy_free_port() {
    local port=$(( $1 + 1 ))
    while lsof -iTCP:${port} -sTCP:LISTEN >/dev/null 2>&1; do
        port=$((port + 1))
    done
    echo "$port"
}

# _proxy_launch NAME MONITOR_CC_ROOT PORT LOG_ID PROJECT_ROOT
#   Live-copies the addon (prevents hot-reload bashing the main proxy) and starts mitmdump in
#   background. Sets WORKER_PROXY_PID / WORKER_PROXY_LIVE_ADDON / WORKER_PROXY_LIVE_DIR.
_proxy_launch() {
    local name="$1" monitor_cc_root="$2" worker_port="$3" worker_log_id="$4" proxy_project_path="$5"
    local log_dir="${monitor_cc_root}/src/logs"
    local worker_live_id="worker_${name}_$(date +%s)_$$"
    local worker_live_addon_path="${log_dir}/.proxy_addon_live_${worker_live_id}.py"
    local worker_live_dir_path="${log_dir}/.proxy_live_${worker_live_id}"
    cp "${monitor_cc_root}/src/proxy_addon.py" "$worker_live_addon_path"
    mkdir -p "$worker_live_dir_path"
    cp -r "${monitor_cc_root}/src/proxy" "$worker_live_dir_path/"
    MONITOR_CC_ROOT="$monitor_cc_root" PROXY_LOG_ID="$worker_log_id" \
        PROXY_PROJECT_PATH="$proxy_project_path" \
        mitmdump -p "$worker_port" -s "$worker_live_addon_path" \
        --set flow_detail=0 -q \
        >/dev/null 2>"${log_dir}/proxy_errors_${worker_log_id}.log" &
    WORKER_PROXY_PID=$!
    WORKER_PROXY_LIVE_ADDON="$worker_live_addon_path"
    WORKER_PROXY_LIVE_DIR="$worker_live_dir_path"
}

# _proxy_fail_cleanup NAME PORT LOG_DIR LOG_ID
#   Reports the failed proxy start, kills mitmdump, removes the live copies, resets the globals.
_proxy_fail_cleanup() {
    local name="$1" worker_port="$2" log_dir="$3" worker_log_id="$4"
    echo "ERROR: Worker proxy for '$name' did not come up on port ${worker_port}; refusing to start a worker without proxy." >&2
    echo "  mitmdump log: ${log_dir}/proxy_errors_${worker_log_id}.log" >&2
    kill "$WORKER_PROXY_PID" 2>/dev/null || true
    rm -f "$WORKER_PROXY_LIVE_ADDON"
    rm -rf "$WORKER_PROXY_LIVE_DIR"
    WORKER_PROXY_PID=""
    WORKER_PROXY_ENV_PREFIX=""
    WORKER_PROXY_LIVE_ADDON=""
    WORKER_PROXY_LIVE_DIR=""
}

# _worker_proxy_wait_ready PID PORT
#   Polls up to 15s until PID is alive and PORT is listening. Returns 0 when ready, 1 otherwise.
_worker_proxy_wait_ready() {
    local pid="$1"
    local port="$2"
    local deadline=$(( $(date +%s) + 15 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        kill -0 "$pid" 2>/dev/null || return 1
        lsof -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1 && return 0
        sleep 0.3
    done
    return 1
}
