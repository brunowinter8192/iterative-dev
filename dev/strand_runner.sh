# INFRASTRUCTURE

STRAND_REAL_TMUX="$(command -v tmux)"

pass() { echo "  PASS: $1"; }

fail() { echo "  FAIL: $1"; exit 1; }

check() {
    if [ "$2" = "ok" ]; then
        pass "$1"
    else
        fail "$1 — $2"
    fi
}

# ORCHESTRATOR

strand_main() {
    local names root
    names=$(_strand_select "$@")
    root=$(mktemp -d /tmp/strands-XXXXXX)
    local started
    started=$(date +%s)
    _strand_launch_all "$root" $names
    _strand_report "$root" "$started" $names
    local rc=$?
    rm -rf "$root"
    return $rc
}

# FUNCTIONS

_strand_select() {
    if [ "$#" -gt 0 ]; then
        echo "$@"
    else
        echo "${STRANDS[@]}"
    fi
}

_strand_launch_all() {
    local root="$1"; shift
    local name
    for name in "$@"; do
        ( _strand_child "$root" "$name" ) > "$root/$name.out" 2>&1 &
        echo $! > "$root/$name.pid"
    done
}

_strand_child() {
    local root="$1" name="$2"
    SECONDS=0
    STRAND_NAME="$name"
    STRAND_DIR=$(mktemp -d /tmp/strand-"$name"-XXXXXX)
    trap '_strand_teardown "$root" "$name"' EXIT
    _strand_isolate "$name"
    if declare -F strand_init >/dev/null; then
        strand_init
    fi
    "strand_$name"
}

_strand_isolate() {
    local name="$1"
    export HOME="$STRAND_DIR/home"
    export WORKER_LOGGER_DIR="$STRAND_DIR/logs"
    export WORKER_REGISTRY_DIR="$STRAND_DIR/registry"
    mkdir -p "$HOME" "$WORKER_LOGGER_DIR" "$WORKER_REGISTRY_DIR" "$STRAND_DIR/bin"
    export GIT_AUTHOR_NAME="strand" GIT_AUTHOR_EMAIL="strand@example.invalid"
    export GIT_COMMITTER_NAME="strand" GIT_COMMITTER_EMAIL="strand@example.invalid"
    export GIT_CONFIG_NOSYSTEM=1
    STRAND_TMUX_SOCKET="strand_$$_${name}"
    cat > "$STRAND_DIR/bin/tmux" <<WRAP
#!/usr/bin/env bash
unset TMUX
exec "$STRAND_REAL_TMUX" -L $STRAND_TMUX_SOCKET "\$@"
WRAP
    chmod +x "$STRAND_DIR/bin/tmux"
    export PATH="$STRAND_DIR/bin:$PATH"
}

_strand_teardown() {
    local root="$1" name="$2"
    if declare -F strand_cleanup >/dev/null; then
        strand_cleanup 2>/dev/null || true
    fi
    tmux kill-server 2>/dev/null || true
    echo "$SECONDS" > "$root/$name.time"
    rm -rf "$STRAND_DIR"
}

_strand_report() {
    local root="$1" started="$2"; shift 2
    local name rc passed=0 failed=0
    for name in "$@"; do
        wait "$(cat "$root/$name.pid")"
        rc=$?
        echo "--- strand $name: rc=$rc, $(cat "$root/$name.time" 2>/dev/null || echo '?')s ---"
        cat "$root/$name.out"
        if [ "$rc" -eq 0 ]; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
    done
    echo "=== $(( passed + failed )) strands: $passed passed, $failed failed, $(( $(date +%s) - started ))s wall ==="
    [ "$failed" -eq 0 ]
}
