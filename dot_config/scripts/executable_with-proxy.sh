#!/usr/bin/env bash
# ==============================================================================
# Helper to execute any command with current proxy settings (if active)
# ==============================================================================

if [ -n "$XDG_RUNTIME_DIR" ] && [ -d "$XDG_RUNTIME_DIR" ]; then
    _proxy_state_file="$XDG_RUNTIME_DIR/current_proxy"
else
    _proxy_state_file="/tmp/current_proxy"
fi

_default_no_proxy="localhost,127.0.0.1,::1,localaddress,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"

if [ -s "$_proxy_state_file" ]; then
    _proxy_val="$(cat "$_proxy_state_file" 2>/dev/null)"
    if [ -n "$_proxy_val" ]; then
        export http_proxy="$_proxy_val"
        export https_proxy="$_proxy_val"
        export HTTP_PROXY="$_proxy_val"
        export HTTPS_PROXY="$_proxy_val"
        export all_proxy="$_proxy_val"
        export ALL_PROXY="$_proxy_val"
        export no_proxy="${no_proxy:-$_default_no_proxy}"
        export NO_PROXY="${NO_PROXY:-$_default_no_proxy}"
    fi
fi

if [ $# -eq 0 ]; then
    echo "Usage: with-proxy.sh <command> [args...]" >&2
    exit 1
fi

exec "$@"
