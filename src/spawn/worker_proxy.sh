#!/usr/bin/env bash

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

_proxy_project_root() {
    local project_path="$1"
    if [[ "$project_path" == */.claude/worktrees/* ]]; then
        echo "${project_path%%/.claude/worktrees/*}"
    else
        echo "$project_path"
    fi
}

_proxy_session_id() {
    local root="$1"
    if command -v md5 >/dev/null 2>&1; then
        echo -n "$root" | md5 | head -c 8
    else
        echo -n "$root" | md5sum | head -c 8
    fi
}

_proxy_free_port() {
    local port=$(( $1 + 1 ))
    while lsof -iTCP:${port} -sTCP:LISTEN >/dev/null 2>&1; do
        port=$((port + 1))
    done
    echo "$port"
}

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
