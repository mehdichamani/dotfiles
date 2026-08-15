#!/usr/bin/env bash
# ==============================================================================
# Unified CLI & Shell Proxy Manager
# Supports execution directly (bash/zsh) or evaluation/sourcing in Bash & Fish
# ==============================================================================

_proxy_default_no_proxy="localhost,127.0.0.1,::1,localaddress,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
if [ -n "$XDG_RUNTIME_DIR" ] && [ -d "$XDG_RUNTIME_DIR" ]; then
    _proxy_state_file="$XDG_RUNTIME_DIR/current_proxy"
else
    _proxy_state_file="/tmp/current_proxy"
fi
_proxy_apt_file="/etc/apt/apt.conf.d/99proxy"
_proxy_docker_systemd_dir="/etc/systemd/system/docker.service.d"
_proxy_docker_systemd_file="$_proxy_docker_systemd_dir/http-proxy.conf"
_proxy_docker_config_file="$HOME/.docker/config.json"

# ANSI Colors
_proxy_c_cyan="\033[36m"
_proxy_c_green="\033[32m"
_proxy_c_yellow="\033[33m"
_proxy_c_red="\033[31m"
_proxy_c_blue="\033[34m"
_proxy_c_reset="\033[0m"

_proxy_help() {
    printf "${_proxy_c_cyan}Usage:${_proxy_c_reset}\n"
    printf "  proxy [URL|PORT]            Set proxy for shell environment (Default mode)\n"
    printf "  proxy --all [URL|PORT]      Set proxy for shell + APT + Docker (System mode)\n"
    printf "  proxy off                   Clear proxy from shell environment\n"
    printf "  proxy off --all             Clear proxy from shell, APT, and Docker\n"
    printf "  proxy status                Show current proxy status across all targets\n"
    printf "  proxy --help, -h            Show this help message\n"
    printf "  proxy                       Interactive menu\n\n"
    printf "${_proxy_c_cyan}Flags:${_proxy_c_reset}\n"
    printf "  -a, --all, --system         Apply changes system-wide (Shell + APT + Docker)\n\n"
    printf "${_proxy_c_cyan}Examples:${_proxy_c_reset}\n"
    printf "  proxy 3067                  -> Shell env: http://localhost:3067\n"
    printf "  proxy --all 3067            -> Shell + APT + Docker: http://localhost:3067\n"
    printf "  proxy socks5://127.0.0.1:1080\n"
    printf "  proxy off\n"
    printf "  proxy off --all\n"
}

_proxy_normalize() {
    local val="$1"
    # Trim whitespace
    val="$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ -z "$val" ]; then
        return 1
    fi

    # Upgrade socks:// or socks5:// to socks5h://
    if echo "$val" | grep -qE '^socks(5)?://'; then
        echo "$val" | sed -E 's/^socks(5)?:\/\//socks5h:\/\//'
        return 0
    fi

    # If scheme exists
    if echo "$val" | grep -qE '^[a-zA-Z0-9+-]+://'; then
        echo "$val"
        return 0
    fi

    # Strip leading colon
    val="${val#:}"

    # Port only (digits)
    if echo "$val" | grep -qE '^[0-9]+$'; then
        echo "http://localhost:$val"
        return 0
    fi

    # host:port or general
    echo "http://$val"
    return 0
}

_proxy_env_set() {
    local target="$1"
    export http_proxy="$target"
    export https_proxy="$target"
    export HTTP_PROXY="$target"
    export HTTPS_PROXY="$target"
    export all_proxy="$target"
    export ALL_PROXY="$target"
    export no_proxy="$_proxy_default_no_proxy"
    export NO_PROXY="$_proxy_default_no_proxy"
    echo "$target" > "$_proxy_state_file"
    printf "  ${_proxy_c_green}✓ Shell Environment set -> %s${_proxy_c_reset}\n" "$target"
}

_proxy_env_off() {
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    rm -f "$_proxy_state_file"
    printf "  ${_proxy_c_yellow}✓ Shell Environment cleared${_proxy_c_reset}\n"
}

_proxy_apt_set() {
    local target="$1"
    printf "Configuring APT proxy (requires sudo)...\n"
    local apt_content="# Managed by proxy script\nAcquire::http::Proxy \"$target\";\nAcquire::https::Proxy \"$target\";\n"
    if printf "%b" "$apt_content" | sudo tee "$_proxy_apt_file" > /dev/null; then
        printf "  ${_proxy_c_green}✓ APT Proxy configured (%s)${_proxy_c_reset}\n" "$_proxy_apt_file"
    else
        printf "  ${_proxy_c_red}✗ Failed to configure APT proxy${_proxy_c_reset}\n"
    fi
}

_proxy_apt_off() {
    if [ -f "$_proxy_apt_file" ]; then
        printf "Removing APT proxy (requires sudo)...\n"
        if sudo rm -f "$_proxy_apt_file"; then
            printf "  ${_proxy_c_yellow}✓ APT Proxy removed (%s)${_proxy_c_reset}\n" "$_proxy_apt_file"
        else
            printf "  ${_proxy_c_red}✗ Failed to remove APT proxy${_proxy_c_reset}\n"
        fi
    else
        printf "  - APT Proxy already clear\n"
    fi
}

_proxy_docker_client_set() {
    local target="$1"
    mkdir -p "$(dirname "$_proxy_docker_config_file")"
    python3 -c "
import json, os
path = os.path.expanduser('$_proxy_docker_config_file')
data = {}
if os.path.isfile(path):
    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except Exception:
        data = {}

if 'proxies' not in data:
    data['proxies'] = {}

data['proxies']['default'] = {
    'httpProxy': '$target',
    'httpsProxy': '$target',
    'noProxy': '$_proxy_default_no_proxy'
}

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"
    if [ $? -eq 0 ]; then
        printf "  ${_proxy_c_green}✓ Docker Client config updated (%s)${_proxy_c_reset}\n" "$_proxy_docker_config_file"
    else
        printf "  ${_proxy_c_red}✗ Failed to update Docker Client config${_proxy_c_reset}\n"
    fi
}

_proxy_docker_client_off() {
    if [ -f "$_proxy_docker_config_file" ]; then
        python3 -c "
import json, os
path = os.path.expanduser('$_proxy_docker_config_file')
if os.path.isfile(path):
    try:
        with open(path, 'r') as f:
            data = json.load(f)
        if 'proxies' in data and 'default' in data['proxies']:
            del data['proxies']['default']
            if not data['proxies']:
                del data['proxies']
            with open(path, 'w') as f:
                json.dump(data, f, indent=2)
    except Exception:
        pass
"
        printf "  ${_proxy_c_yellow}✓ Docker Client proxy config removed${_proxy_c_reset}\n"
    else
        printf "  - Docker Client config not present\n"
    fi
}

_proxy_docker_daemon_set() {
    local target="$1"
    if command -v docker >/dev/null 2>&1 || [ -d "/lib/systemd/system/docker.service" ] || [ -d "/etc/systemd/system" ]; then
        printf "Configuring Docker daemon proxy (requires sudo)...\n"
        sudo mkdir -p "$_proxy_docker_systemd_dir"
        local daemon_conf="[Service]\nEnvironment=\"HTTP_PROXY=$target\"\nEnvironment=\"HTTPS_PROXY=$target\"\nEnvironment=\"NO_PROXY=$_proxy_default_no_proxy\"\n"
        if printf "%b" "$daemon_conf" | sudo tee "$_proxy_docker_systemd_file" > /dev/null; then
            sudo systemctl daemon-reload
            if systemctl is-active --quiet docker 2>/dev/null; then
                sudo systemctl restart docker
            fi
            printf "  ${_proxy_c_green}✓ Docker Daemon proxy configured & reloaded${_proxy_c_reset}\n"
        else
            printf "  ${_proxy_c_red}✗ Failed to configure Docker Daemon proxy${_proxy_c_reset}\n"
        fi
    else
        printf "  - Docker daemon service not found, skipping daemon configuration.\n"
    fi
}

_proxy_docker_daemon_off() {
    if [ -f "$_proxy_docker_systemd_file" ]; then
        printf "Removing Docker daemon proxy (requires sudo)...\n"
        if sudo rm -f "$_proxy_docker_systemd_file"; then
            sudo systemctl daemon-reload
            if systemctl is-active --quiet docker 2>/dev/null; then
                sudo systemctl restart docker
            fi
            printf "  ${_proxy_c_yellow}✓ Docker Daemon proxy removed & reloaded${_proxy_c_reset}\n"
        else
            printf "  ${_proxy_c_red}✗ Failed to remove Docker Daemon proxy${_proxy_c_reset}\n"
        fi
    else
        printf "  - Docker Daemon proxy already clear\n"
    fi
}

_proxy_status() {
    printf "${_proxy_c_cyan}=== Proxy Status Dashboard ===${_proxy_c_reset}\n\n"
    
    # 1. Shell Env
    printf "${_proxy_c_blue}[Shell Environment]${_proxy_c_reset}\n"
    if [ -n "$http_proxy" ] || [ -n "$HTTP_PROXY" ] || [ -n "$all_proxy" ] || [ -n "$ALL_PROXY" ]; then
        printf "  ${_proxy_c_green}● Status      : ON${_proxy_c_reset}\n"
        printf "    http_proxy  : %s\n" "${http_proxy:-not set}"
        printf "    https_proxy : %s\n" "${https_proxy:-not set}"
        printf "    all_proxy   : %s\n" "${all_proxy:-not set}"
        printf "    no_proxy    : %s\n" "${no_proxy:-not set}"
    else
        printf "  ${_proxy_c_yellow}○ Status      : OFF${_proxy_c_reset}\n"
    fi
    if [ -f "$_proxy_state_file" ]; then
        printf "    State File  : %s\n" "$(cat "$_proxy_state_file" 2>/dev/null)"
    fi

    # 2. APT
    printf "\n${_proxy_c_blue}[APT Package Manager]${_proxy_c_reset}\n"
    if [ -f "$_proxy_apt_file" ]; then
        printf "  ${_proxy_c_green}● Status      : Configured (%s)${_proxy_c_reset}\n" "$_proxy_apt_file"
        sed 's/^/    /' "$_proxy_apt_file"
    else
        printf "  ${_proxy_c_yellow}○ Status      : Not Configured${_proxy_c_reset}\n"
    fi

    # 3. Docker CLI
    printf "\n${_proxy_c_blue}[Docker Client (~/.docker/config.json)]${_proxy_c_reset}\n"
    if [ -f "$_proxy_docker_config_file" ]; then
        local docker_p
        docker_p=$(python3 -c "
import json, os
try:
    with open(os.path.expanduser('$_proxy_docker_config_file')) as f:
        d = json.load(f)
        p = d.get('proxies', {}).get('default', {})
        if p:
            print(p.get('httpProxy', 'configured'))
except Exception:
    pass
" 2>/dev/null)
        if [ -n "$docker_p" ]; then
            printf "  ${_proxy_c_green}● Status      : ON (%s)${_proxy_c_reset}\n" "$docker_p"
        else
            printf "  ${_proxy_c_yellow}○ Status      : OFF${_proxy_c_reset}\n"
        fi
    else
        printf "  ${_proxy_c_yellow}○ Status      : OFF${_proxy_c_reset}\n"
    fi

    # 4. Docker Daemon
    printf "\n${_proxy_c_blue}[Docker Daemon (Systemd)]${_proxy_c_reset}\n"
    if [ -f "$_proxy_docker_systemd_file" ]; then
        printf "  ${_proxy_c_green}● Status      : Configured (%s)${_proxy_c_reset}\n" "$_proxy_docker_systemd_file"
        sed 's/^/    /' "$_proxy_docker_systemd_file"
    else
        printf "  ${_proxy_c_yellow}○ Status      : Not Configured${_proxy_c_reset}\n"
    fi
    printf "\n"
}

proxy() {
    local is_system_mode=0
    local is_off=0
    local is_status=0
    local target_arg=""

    for arg in "$@"; do
        case "$arg" in
            -h|--help|help)
                _proxy_help
                return 0
                ;;
            -a|--all|--system)
                is_system_mode=1
                ;;
            off|clear|disable)
                is_off=1
                ;;
            status|show)
                is_status=1
                ;;
            *)
                target_arg="$arg"
                ;;
        esac
    done

    if [ "$is_status" -eq 1 ]; then
        _proxy_status
        return 0
    fi

    if [ "$is_off" -eq 1 ]; then
        printf "${_proxy_c_cyan}Turning Proxy OFF...${_proxy_c_reset}\n"
        _proxy_env_off
        if [ "$is_system_mode" -eq 1 ]; then
            _proxy_apt_off
            _proxy_docker_client_off
            _proxy_docker_daemon_off
        fi
        return 0
    fi

    if [ -n "$target_arg" ]; then
        local normalized
        normalized=$(_proxy_normalize "$target_arg")
        if [ -z "$normalized" ]; then
            printf "Invalid proxy argument.\n"
            return 1
        fi

        if [ "$is_system_mode" -eq 1 ]; then
            printf "${_proxy_c_cyan}● Setting System-Wide Proxy (Shell + APT + Docker) -> %s${_proxy_c_reset}\n" "$normalized"
            _proxy_env_set "$normalized"
            _proxy_apt_set "$normalized"
            _proxy_docker_client_set "$normalized"
            _proxy_docker_daemon_set "$normalized"
        else
            printf "${_proxy_c_cyan}● Setting Shell Proxy -> %s${_proxy_c_reset}\n" "$normalized"
            _proxy_env_set "$normalized"
            printf "  (Tip: use 'proxy --all <url>' to also configure APT & Docker)\n"
        fi
        return 0
    fi

    # Interactive Mode
    local default_presets=(
        "http://localhost:3067"
        "http://localhost:10808"
        "socks5h://127.0.0.1:1080"
        "socks5h://127.0.0.1:2080"
    )

    printf "${_proxy_c_cyan}Current Status:${_proxy_c_reset}\n"
    _proxy_status

    printf "${_proxy_c_cyan}Select Target Mode:${_proxy_c_reset}\n"
    printf "  [1] Shell Environment Only (Default)\n"
    printf "  [2] APT & Docker Only (System Services)\n"
    printf "  [3] All / System-Wide (Shell + APT + Docker)\n"
    
    local mode_choice
    read -r -p "Mode [default: 1]: " mode_choice
    local target_shell=0
    local target_system=0

    case "$mode_choice" in
        2)
            target_shell=0
            target_system=1
            ;;
        3)
            target_shell=1
            target_system=1
            ;;
        *)
            target_shell=1
            target_system=0
            ;;
    esac

    printf "\n${_proxy_c_cyan}Select Proxy Preset or Action:${_proxy_c_reset}\n"
    printf "  [0] Turn proxy OFF\n"
    local idx=1
    for preset in "${default_presets[@]}"; do
        printf "  [%d] %s\n" "$idx" "$preset"
        idx=$((idx + 1))
    done
    printf "  [c] Enter custom address / port\n"
    printf "  [q] Cancel / Quit\n\n"

    local choice
    read -r -p "Choice [default: 1]: " choice
    if [ -z "$choice" ]; then
        choice=1
    fi

    local selected_target=""
    case "$choice" in
        0|off)
            if [ "$target_shell" -eq 1 ]; then
                _proxy_env_off
            fi
            if [ "$target_system" -eq 1 ]; then
                _proxy_apt_off
                _proxy_docker_client_off
                _proxy_docker_daemon_off
            fi
            return 0
            ;;
        q|quit|exit)
            return 0
            ;;
        c|custom)
            local custom_input
            read -r -p "Enter proxy address or port (e.g. 3068, 127.0.0.1:3068, http://...): " custom_input
            if [ -n "$custom_input" ]; then
                selected_target=$(_proxy_normalize "$custom_input")
            else
                printf "No input provided.\n"
                return 1
            fi
            ;;
        1|2|3|4)
            local arr_idx=$((choice - 1))
            selected_target="${default_presets[$arr_idx]}"
            ;;
        *)
            selected_target=$(_proxy_normalize "$choice")
            ;;
    esac

    if [ -n "$selected_target" ]; then
        if [ "$target_shell" -eq 1 ] && [ "$target_system" -eq 1 ]; then
            printf "${_proxy_c_cyan}● Setting System-Wide Proxy (Shell + APT + Docker) -> %s${_proxy_c_reset}\n" "$selected_target"
            _proxy_env_set "$selected_target"
            _proxy_apt_set "$selected_target"
            _proxy_docker_client_set "$selected_target"
            _proxy_docker_daemon_set "$selected_target"
        elif [ "$target_system" -eq 1 ]; then
            printf "${_proxy_c_cyan}● Setting System Proxy (APT + Docker) -> %s${_proxy_c_reset}\n" "$selected_target"
            _proxy_apt_set "$selected_target"
            _proxy_docker_client_set "$selected_target"
            _proxy_docker_daemon_set "$selected_target"
        else
            printf "${_proxy_c_cyan}● Setting Shell Proxy -> %s${_proxy_c_reset}\n" "$selected_target"
            _proxy_env_set "$selected_target"
        fi
    fi
}
