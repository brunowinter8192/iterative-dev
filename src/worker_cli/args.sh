#!/usr/bin/env bash

# FUNCTIONS

require_arity() {
    local cmd="$1" form="$2" min="$3" max="$4" note="${5:-}"
    shift 5
    if [ $# -lt "$min" ]; then
        echo "worker-cli $cmd: missing argument. Correct form: worker-cli $form" >&2
        exit 2
    fi
    if [ $# -gt "$max" ]; then
        arg_unexpected "$cmd" "$form" "$note" "${@:$((max + 1)):1}"
    fi
}

arg_unexpected() {
    local cmd="$1" form="$2" note="$3" bad="$4"
    local message="worker-cli $cmd: unexpected argument '$bad'."
    if [ -n "$note" ]; then
        message="$message $note"
    elif _arg_looks_like_path "$bad"; then
        message="$message A project_path argument was removed; worker-cli resolves the project itself."
    fi
    echo "$message Correct form: worker-cli $form" >&2
    exit 2
}

_arg_looks_like_path() {
    case "$1" in
        /*|./*|../*|~*|.|c) return 0 ;;
        *) return 1 ;;
    esac
}
