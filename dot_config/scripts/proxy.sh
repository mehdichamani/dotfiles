#!/usr/bin/env bash
# ==============================================================================
# Unified CLI, GUI & System Proxy Manager
# Supports execution directly (bash/zsh) or evaluation/sourcing in Bash & Fish
# ==============================================================================

_proxy_default_presets=(
    "http://localhost:10808"
    "http://localhost:3067"
    "socks5h://127.0.0.1:10808"
    "socks5h://127.0.0.1:3067"
    "http://192.168.0.101:10808"
)
_proxy_default_no_proxy="localhost,127.0.0.1,::1,localaddress,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
_proxy_state_file="$HOME/.config/proxy_state"
_proxy_last_used_file="$HOME/.config/proxy_last_used"
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
    printf "  proxy [URL|PORT]            Set proxy for CLI (Shell, NPM, Git) [Default]\n"
    printf "  proxy --gui [URL|PORT]      Set proxy for GUI (GSettings / Desktop apps)\n"
    printf "  proxy --systemd [URL|PORT]  Set proxy for systemd (Docker daemon & system services)\n"
    printf "  proxy --all [URL|PORT]      Set proxy for All (CLI + GUI + systemd + APT)\n"
    printf "  proxy off                   Clear proxy from CLI (Shell, NPM, Git)\n"
    printf "  proxy off --gui             Clear proxy from GUI (GSettings)\n"
    printf "  proxy off --systemd         Clear proxy from systemd (Docker daemon)\n"
    printf "  proxy off --all             Clear proxy from CLI, GUI, systemd, and APT\n"
    printf "  proxy status                Show current proxy status across all targets\n"
    printf "  withproxy <command>         Run a command temporarily with proxy (falls back to default preset)\n"
    printf "  noproxy <command>           Run a single command temporarily without proxy\n"
    printf "  proxy --help, -h            Show this help message\n"
    printf "  proxy                       Interactive menu\n\n"
    printf "${_proxy_c_cyan}Flags:${_proxy_c_reset}\n"
    printf "  -g, --gui                   Target GUI (GSettings / Chromium / Electron)\n"
    printf "  -s, --systemd, --system     Target systemd (Docker daemon & system services)\n"
    printf "  -a, --all                   Target All (CLI + GUI + systemd + APT)\n\n"
    printf "${_proxy_c_cyan}Examples:${_proxy_c_reset}\n"
    printf "  proxy 3067                  -> CLI (Shell, NPM, Git): http://localhost:3067\n"
    printf "  proxy --gui 3067            -> GUI (GSettings): 127.0.0.1:3067\n"
    printf "  proxy --all 3067            -> All: http://localhost:3067\n"
    printf "  proxy socks5://127.0.0.1:1080\n"
    printf "  proxy off\n"
    printf "  proxy off --all\n"
    printf "  withproxy curl ifconfig.me\n"
    printf "  noproxy curl ifconfig.me\n"
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

_proxy_parse_url() {
    local url="$1"
    python3 -c "
import urllib.parse, sys
u = urllib.parse.urlparse('$url')
scheme = u.scheme or 'http'
host = u.hostname or '127.0.0.1'
port = u.port or (1080 if 'socks' in scheme else 8080)
print(f'{scheme} {host} {port}')
" 2>/dev/null
}

# --- CLI Layer ---
_proxy_npm_set() {
    local target="$1"
    if command -v npm >/dev/null 2>&1; then
        npm config set proxy "$target" >/dev/null 2>&1
        npm config set https-proxy "$target" >/dev/null 2>&1
        printf "  ${_proxy_c_green}✓ NPM Proxy set -> %s${_proxy_c_reset}\n" "$target"
    fi
}

_proxy_npm_off() {
    if command -v npm >/dev/null 2>&1; then
        npm config delete proxy >/dev/null 2>&1
        npm config delete https-proxy >/dev/null 2>&1
        npm config delete http-proxy >/dev/null 2>&1
        printf "  ${_proxy_c_yellow}✓ NPM Proxy cleared${_proxy_c_reset}\n"
    fi
}

# --- Git & SSH Layer (Socat Proxy) ---
_proxy_git_ssh_set() {
    local target="$1"
    read -r scheme host port < <(_proxy_parse_url "$target")
    if [ -z "$host" ] || [ -z "$port" ]; then
        return 0
    fi

    # Clean up legacy git config if present to keep chezmoi clean
    if command -v git >/dev/null 2>&1; then
        git config --global --unset http.https://github.com.proxy 2>/dev/null || true
        git config --global --unset core.sshCommand 2>/dev/null || true
    fi

    # Configure SSH proxy via socat if available
    if command -v socat >/dev/null 2>&1; then
        local socks_type="SOCKS5"
        if echo "$scheme" | grep -q "socks5h"; then
            socks_type="SOCKS5"
        fi
        export GIT_SSH_COMMAND="ssh -o ProxyCommand='socat - ${socks_type}:${host}:%h:%p,socksport=${port}'"
        printf "  ${_proxy_c_green}✓ GIT_SSH_COMMAND set via socat -> %s:%s${_proxy_c_reset}\n" "$host" "$port"
    fi
}

_proxy_git_ssh_off() {
    unset GIT_SSH_COMMAND
    if command -v git >/dev/null 2>&1; then
        git config --global --unset http.https://github.com.proxy 2>/dev/null || true
        git config --global --unset core.sshCommand 2>/dev/null || true
    fi
    printf "  ${_proxy_c_yellow}✓ GIT_SSH_COMMAND cleared${_proxy_c_reset}\n"
}

_proxy_cli_set() {
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
    echo "$target" > "$_proxy_last_used_file"
    printf "  ${_proxy_c_green}✓ CLI (Shell & Git) set -> %s${_proxy_c_reset}\n" "$target"
    _proxy_npm_set "$target"
    _proxy_git_ssh_set "$target"
}

_proxy_cli_off() {
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    rm -f "$_proxy_state_file"
    printf "  ${_proxy_c_yellow}✓ CLI (Shell & Git) cleared${_proxy_c_reset}\n"
    _proxy_npm_off
    _proxy_git_ssh_off
}

# --- GUI Layer (GSettings) ---
_proxy_gui_set() {
    local target="$1"
    if ! command -v gsettings >/dev/null 2>&1; then
        printf "  - gsettings not available, skipping GUI proxy.\n"
        return 0
    fi

    read -r scheme host port < <(_proxy_parse_url "$target")
    if [ -z "$host" ] || [ -z "$port" ]; then
        printf "  ${_proxy_c_red}✗ Failed to parse proxy address for GUI${_proxy_c_reset}\n"
        return 1
    fi

    gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null
    if echo "$scheme" | grep -q "socks"; then
        gsettings set org.gnome.system.proxy.socks host "$host" 2>/dev/null
        gsettings set org.gnome.system.proxy.socks port "$port" 2>/dev/null
        printf "  ${_proxy_c_green}✓ GUI Proxy (GSettings SOCKS) set -> %s:%s${_proxy_c_reset}\n" "$host" "$port"
    else
        gsettings set org.gnome.system.proxy.http host "$host" 2>/dev/null
        gsettings set org.gnome.system.proxy.http port "$port" 2>/dev/null
        gsettings set org.gnome.system.proxy.https host "$host" 2>/dev/null
        gsettings set org.gnome.system.proxy.https port "$port" 2>/dev/null
        printf "  ${_proxy_c_green}✓ GUI Proxy (GSettings HTTP/HTTPS) set -> %s:%s${_proxy_c_reset}\n" "$host" "$port"
    fi
}

_proxy_gui_off() {
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null
        printf "  ${_proxy_c_yellow}✓ GUI Proxy (GSettings) cleared (mode: none)${_proxy_c_reset}\n"
    fi
}

# --- APT Layer ---
_proxy_apt_set() {
    if ! command -v apt-get >/dev/null 2>&1 && ! command -v apt >/dev/null 2>&1; then
        return 0
    fi
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
    if ! command -v apt-get >/dev/null 2>&1 && ! command -v apt >/dev/null 2>&1; then
        return 0
    fi
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

# --- systemd & Docker Layer ---
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

_proxy_docker_restart_prompt() {
    if systemctl is-active --quiet docker 2>/dev/null; then
        local ans
        read -r -p "Docker daemon is active. Restart docker now to apply changes? [y/N]: " ans
        case "$ans" in
            [yY]|[yY][eE][sS])
                printf "Restarting Docker daemon (requires sudo)...\n"
                sudo systemctl restart docker
                printf "  ${_proxy_c_green}✓ Docker Daemon restarted${_proxy_c_reset}\n"
                ;;
            *)
                printf "  ${_proxy_c_yellow}↷ Skipped Docker restart (apply manually later with: sudo systemctl restart docker)${_proxy_c_reset}\n"
                ;;
        esac
    fi
}

_proxy_systemd_services_set() {
    local target="$1"
    # 1. systemd user manager import
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user import-environment http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY 2>/dev/null
    fi

    # 2. Docker daemon systemd drop-in
    if command -v docker >/dev/null 2>&1 || [ -d "/lib/systemd/system/docker.service" ] || [ -d "/etc/systemd/system" ]; then
        printf "Configuring Docker daemon proxy (requires sudo)...\n"
        sudo mkdir -p "$_proxy_docker_systemd_dir"
        local daemon_conf="[Service]\nEnvironment=\"HTTP_PROXY=$target\"\nEnvironment=\"HTTPS_PROXY=$target\"\nEnvironment=\"NO_PROXY=$_proxy_default_no_proxy\"\n"
        if printf "%b" "$daemon_conf" | sudo tee "$_proxy_docker_systemd_file" > /dev/null; then
            sudo systemctl daemon-reload
            printf "  ${_proxy_c_green}✓ Docker Daemon proxy configured & daemon-reload completed${_proxy_c_reset}\n"
            _proxy_docker_restart_prompt
        else
            printf "  ${_proxy_c_red}✗ Failed to configure Docker Daemon proxy${_proxy_c_reset}\n"
        fi
    else
        printf "  - Docker daemon service not found, skipping daemon configuration.\n"
    fi

    _proxy_docker_client_set "$target"
}

_proxy_systemd_services_off() {
    # 1. Docker Daemon drop-in remove
    if [ -f "$_proxy_docker_systemd_file" ]; then
        printf "Removing Docker daemon proxy (requires sudo)...\n"
        if sudo rm -f "$_proxy_docker_systemd_file"; then
            sudo systemctl daemon-reload
            printf "  ${_proxy_c_yellow}✓ Docker Daemon proxy removed & daemon-reload completed${_proxy_c_reset}\n"
            _proxy_docker_restart_prompt
        else
            printf "  ${_proxy_c_red}✗ Failed to remove Docker Daemon proxy${_proxy_c_reset}\n"
        fi
    else
        printf "  - Docker Daemon proxy already clear\n"
    fi

    # 2. Docker Client config remove
    _proxy_docker_client_off

    # 3. systemd user manager unset
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user unset-environment http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY 2>/dev/null
    fi
}

# --- Status Dashboard ---
_proxy_status() {
    printf "${_proxy_c_cyan}=== Proxy Status Dashboard ===${_proxy_c_reset}\n\n"
    
    # 1. CLI (Shell & Git)
    printf "${_proxy_c_blue}[CLI Environment (Shell, NPM, Git)]${_proxy_c_reset}\n"
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
    if [ -n "$GIT_SSH_COMMAND" ]; then
        printf "    GIT_SSH_CMD : %s\n" "$GIT_SSH_COMMAND"
    elif command -v git >/dev/null 2>&1; then
        local git_ssh_p
        git_ssh_p="$(git config --global core.sshCommand 2>/dev/null)"
        if [ -n "$git_ssh_p" ]; then
            printf "    Git SSH Cmd : %s\n" "$git_ssh_p"
        fi
    fi

    # 2. NPM
    if command -v npm >/dev/null 2>&1; then
        local npm_p
        npm_p="$(npm config get proxy 2>/dev/null)"
        if [ "$npm_p" = "null" ] || [ "$npm_p" = "undefined" ]; then
            npm_p=""
        fi
        if [ -n "$npm_p" ]; then
            printf "    NPM Proxy   : %s\n" "$npm_p"
        fi
    fi

    # 3. GUI (GSettings)
    if command -v gsettings >/dev/null 2>&1; then
        printf "\n${_proxy_c_blue}[GUI Desktop (GSettings)]${_proxy_c_reset}\n"
        local g_mode
        g_mode="$(gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d \"\'\")"
        if [ "$g_mode" = "manual" ]; then
            local g_http_h g_http_p g_socks_h g_socks_p
            g_http_h="$(gsettings get org.gnome.system.proxy.http host 2>/dev/null | tr -d \"\'\")"
            g_http_p="$(gsettings get org.gnome.system.proxy.http port 2>/dev/null)"
            g_socks_h="$(gsettings get org.gnome.system.proxy.socks host 2>/dev/null | tr -d \"\'\")"
            g_socks_p="$(gsettings get org.gnome.system.proxy.socks port 2>/dev/null)"
            printf "  ${_proxy_c_green}● Status      : ON (mode: manual)${_proxy_c_reset}\n"
            if [ -n "$g_http_h" ] && [ "$g_http_p" != "0" ]; then
                printf "    HTTP/HTTPS  : %s:%s\n" "$g_http_h" "$g_http_p"
            fi
            if [ -n "$g_socks_h" ] && [ "$g_socks_p" != "0" ]; then
                printf "    SOCKS       : %s:%s\n" "$g_socks_h" "$g_socks_p"
            fi
        else
            printf "  ${_proxy_c_yellow}○ Status      : OFF (mode: %s)${_proxy_c_reset}\n" "${g_mode:-none}"
        fi
    fi

    # 4. systemd & Docker Daemon
    printf "\n${_proxy_c_blue}[systemd (Docker Daemon & Services)]${_proxy_c_reset}\n"
    if [ -f "$_proxy_docker_systemd_file" ]; then
        printf "  ${_proxy_c_green}● Status      : Configured (%s)${_proxy_c_reset}\n" "$_proxy_docker_systemd_file"
        sed 's/^/    /' "$_proxy_docker_systemd_file"
    else
        printf "  ${_proxy_c_yellow}○ Status      : Not Configured${_proxy_c_reset}\n"
    fi
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
            printf "    Docker Client: ON (%s)\n" "$docker_p"
        fi
    fi

    # 5. APT (if available)
    if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
        printf "\n${_proxy_c_blue}[APT Package Manager]${_proxy_c_reset}\n"
        if [ -f "$_proxy_apt_file" ]; then
            printf "  ${_proxy_c_green}● Status      : Configured (%s)${_proxy_c_reset}\n" "$_proxy_apt_file"
            sed 's/^/    /' "$_proxy_apt_file"
        else
            printf "  ${_proxy_c_yellow}○ Status      : Not Configured${_proxy_c_reset}\n"
        fi
    fi
    printf "\n"
}

proxy() {
    local target_cli=0
    local target_gui=0
    local target_systemd=0
    local is_off=0
    local is_status=0
    local target_arg=""

    for arg in "$@"; do
        case "$arg" in
            -h|--help|help)
                _proxy_help
                return 0
                ;;
            -g|--gui)
                target_gui=1
                ;;
            -s|--systemd|--system)
                target_systemd=1
                ;;
            -a|--all)
                target_cli=1
                target_gui=1
                target_systemd=1
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

    # Default to CLI if no specific target flag was passed in non-interactive invocation
    if [ "$target_cli" -eq 0 ] && [ "$target_gui" -eq 0 ] && [ "$target_systemd" -eq 0 ]; then
        target_cli=1
    fi

    if [ "$is_status" -eq 1 ]; then
        _proxy_status
        return 0
    fi

    if [ "$is_off" -eq 1 ]; then
        printf "${_proxy_c_cyan}Turning Proxy OFF...${_proxy_c_reset}\n"
        if [ "$target_cli" -eq 1 ]; then
            _proxy_cli_off
        fi
        if [ "$target_gui" -eq 1 ]; then
            _proxy_gui_off
        fi
        if [ "$target_systemd" -eq 1 ]; then
            _proxy_apt_off
            _proxy_systemd_services_off
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

        printf "${_proxy_c_cyan}● Applying Proxy -> %s${_proxy_c_reset}\n" "$normalized"
        if [ "$target_cli" -eq 1 ]; then
            _proxy_cli_set "$normalized"
        fi
        if [ "$target_gui" -eq 1 ]; then
            _proxy_gui_set "$normalized"
        fi
        if [ "$target_systemd" -eq 1 ]; then
            _proxy_systemd_services_set "$normalized"
            _proxy_apt_set "$normalized"
        fi
        return 0
    fi

    # Interactive Mode
    printf "${_proxy_c_cyan}Current Status:${_proxy_c_reset}\n"
    _proxy_status

    printf "${_proxy_c_cyan}Select Target Mode:${_proxy_c_reset}\n"
    printf "  [1] CLI      (Shell, NPM, Git) [Default]\n"
    printf "  [2] GUI      (GSettings, Chromium, Electron)\n"
    printf "  [3] systemd  (Docker Daemon & System Services)\n"
    printf "  [4] All      (CLI + GUI + systemd + APT)\n"
    
    local mode_choice
    read -r -p "Mode [default: 1]: " mode_choice
    target_cli=0
    target_gui=0
    target_systemd=0

    case "$mode_choice" in
        2)
            target_gui=1
            ;;
        3)
            target_systemd=1
            ;;
        4)
            target_cli=1
            target_gui=1
            target_systemd=1
            ;;
        *)
            target_cli=1
            ;;
    esac

    printf "\n${_proxy_c_cyan}Select Proxy Preset or Action:${_proxy_c_reset}\n"
    printf "  [0] Turn proxy OFF\n"
    local idx=1
    for preset in "${_proxy_default_presets[@]}"; do
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
            if [ "$target_cli" -eq 1 ]; then
                _proxy_cli_off
            fi
            if [ "$target_gui" -eq 1 ]; then
                _proxy_gui_off
            fi
            if [ "$target_systemd" -eq 1 ]; then
                _proxy_apt_off
                _proxy_systemd_services_off
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
            selected_target="${_proxy_default_presets[$arr_idx]}"
            ;;
        *)
            selected_target=$(_proxy_normalize "$choice")
            ;;
    esac

    if [ -n "$selected_target" ]; then
        printf "${_proxy_c_cyan}● Applying Proxy -> %s${_proxy_c_reset}\n" "$selected_target"
        if [ "$target_cli" -eq 1 ]; then
            _proxy_cli_set "$selected_target"
        fi
        if [ "$target_gui" -eq 1 ]; then
            _proxy_gui_set "$selected_target"
        fi
        if [ "$target_systemd" -eq 1 ]; then
            _proxy_systemd_services_set "$selected_target"
            _proxy_apt_set "$selected_target"
        fi
    fi
}

# Run a command with proxy (current proxy if set, or fallback to first preset)
withproxy() {
    if [ $# -eq 0 ]; then
        printf "Usage: withproxy <command> [args...]\n" >&2
        return 1
    fi

    local target_p=""
    if [ -n "$http_proxy" ]; then
        target_p="$http_proxy"
    elif [ -n "$HTTP_PROXY" ]; then
        target_p="$HTTP_PROXY"
    elif [ -n "$all_proxy" ]; then
        target_p="$all_proxy"
    elif [ -n "$ALL_PROXY" ]; then
        target_p="$ALL_PROXY"
    elif [ -s "$_proxy_state_file" ]; then
        target_p="$(cat "$_proxy_state_file" 2>/dev/null)"
    elif [ -s "$_proxy_last_used_file" ]; then
        target_p="$(cat "$_proxy_last_used_file" 2>/dev/null)"
    fi

    if [ -z "$target_p" ]; then
        target_p="${_proxy_default_presets[0]}"
    fi

    local git_ssh_cmd=""
    read -r w_scheme w_host w_port < <(_proxy_parse_url "$target_p")
    if [ -n "$w_host" ] && [ -n "$w_port" ] && command -v socat >/dev/null 2>&1; then
        local w_socks="SOCKS5"
        if echo "$w_scheme" | grep -q "socks5h"; then
            w_socks="SOCKS5"
        fi
        git_ssh_cmd="ssh -o ProxyCommand='socat - ${w_socks}:${w_host}:%h:%p,socksport=${w_port}'"
    fi

    if [ -n "$git_ssh_cmd" ]; then
        env http_proxy="$target_p" https_proxy="$target_p" \
            HTTP_PROXY="$target_p" HTTPS_PROXY="$target_p" \
            all_proxy="$target_p" ALL_PROXY="$target_p" \
            no_proxy="${no_proxy:-$_proxy_default_no_proxy}" \
            NO_PROXY="${NO_PROXY:-$_proxy_default_no_proxy}" \
            GIT_SSH_COMMAND="$git_ssh_cmd" "$@"
    else
        env http_proxy="$target_p" https_proxy="$target_p" \
            HTTP_PROXY="$target_p" HTTPS_PROXY="$target_p" \
            all_proxy="$target_p" ALL_PROXY="$target_p" \
            no_proxy="${no_proxy:-$_proxy_default_no_proxy}" \
            NO_PROXY="${NO_PROXY:-$_proxy_default_no_proxy}" "$@"
    fi
}

# Run any command without proxy environment variables
noproxy() {
    if [ $# -eq 0 ]; then
        printf "Usage: noproxy <command> [args...]\n" >&2
        return 1
    fi
    env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
        -u all_proxy -u ALL_PROXY -u ftp_proxy -u FTP_PROXY \
        -u rsync_proxy -u RSYNC_PROXY -u no_proxy -u NO_PROXY \
        -u GIT_SSH_COMMAND "$@"
}

# Auto-load saved persistent proxy if state file exists
if [ -s "$_proxy_state_file" ]; then
    _proxy_saved_val="$(cat "$_proxy_state_file" 2>/dev/null)"
    if [ -n "$_proxy_saved_val" ]; then
        export http_proxy="$_proxy_saved_val"
        export https_proxy="$_proxy_saved_val"
        export HTTP_PROXY="$_proxy_saved_val"
        export HTTPS_PROXY="$_proxy_saved_val"
        export all_proxy="$_proxy_saved_val"
        export ALL_PROXY="$_proxy_saved_val"
        export no_proxy="${no_proxy:-$_proxy_default_no_proxy}"
        export NO_PROXY="${NO_PROXY:-$_proxy_default_no_proxy}"
        _proxy_git_ssh_set "$_proxy_saved_val" >/dev/null 2>&1
    fi
fi
