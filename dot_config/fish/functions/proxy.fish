function proxy --description "Manage shell and system proxy configurations"
    # Configuration & Defaults
    set -l default_no_proxy "localhost,127.0.0.1,::1,localaddress,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
    set -l proxy_file (test -n "$XDG_RUNTIME_DIR" -a -d "$XDG_RUNTIME_DIR"; and echo "$XDG_RUNTIME_DIR/current_proxy"; or echo "/tmp/current_proxy")
    set -l apt_proxy_file "/etc/apt/apt.conf.d/99proxy"
    set -l docker_systemd_dir "/etc/systemd/system/docker.service.d"
    set -l docker_systemd_file "$docker_systemd_dir/http-proxy.conf"
    set -l docker_config_file "$HOME/.docker/config.json"

    # Helper to print usage instructions
    function _proxy_help
        set_color cyan; echo "Usage:"; set_color normal
        echo "  proxy [URL|PORT]            Set proxy for shell environment (Default mode)"
        echo "  proxy --all [URL|PORT]      Set proxy for shell + APT + Docker (System mode)"
        echo "  proxy off                   Clear proxy from shell environment"
        echo "  proxy off --all             Clear proxy from shell, APT, and Docker"
        echo "  proxy status                Show current proxy status across all targets"
        echo "  proxy --help, -h            Show this help message"
        echo "  proxy                       Interactive menu"
        echo ""
        set_color cyan; echo "Flags:"; set_color normal
        echo "  -a, --all, --system         Apply changes system-wide (Shell + APT + Docker)"
        echo ""
        set_color cyan; echo "Examples:"; set_color normal
        echo "  proxy 3067                  -> Shell env: http://localhost:3067"
        echo "  proxy --all 3067            -> Shell + APT + Docker: http://localhost:3067"
        echo "  proxy socks5://127.0.0.1:1080"
        echo "  proxy off"
        echo "  proxy off --all"
    end

    # Normalize input into full URL format
    function _proxy_normalize --argument-names input
        set -l val (string trim "$input")
        if test -z "$val"
            return 1
        end

        # Upgrade socks:// or socks5:// to socks5h:// (remote DNS resolution)
        if string match -qr '^socks(5)?://' -- "$val"
            set val (string replace -r '^socks(5)?://' 'socks5h://' -- "$val")
            echo "$val"
            return 0
        end

        # If already has scheme
        if string match -qr '^[a-zA-Z0-9+-]+://' -- "$val"
            echo "$val"
            return 0
        end

        # Strip leading colon if provided (e.g. :3068)
        set val (string replace -r '^:' '' -- "$val")

        # Port only
        if string match -qr '^\d+$' -- "$val"
            echo "http://localhost:$val"
            return 0
        end

        # host:port
        if string match -qr '^.+:\d+$' -- "$val"
            echo "http://$val"
            return 0
        end

        echo "http://$val"
    end

    # --- Target: Shell Environment & Temp File ---
    function _proxy_env_set --argument-names target --inherit-variable proxy_file --inherit-variable default_no_proxy
        set -e -g http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
        if string match -qr '^socks5h?://' -- "$target"
            set -Ux all_proxy "$target"
            set -Ux ALL_PROXY "$target"
            set -Ux http_proxy "$target"
            set -Ux https_proxy "$target"
            set -Ux HTTP_PROXY "$target"
            set -Ux HTTPS_PROXY "$target"
        else
            set -Ux http_proxy "$target"
            set -Ux https_proxy "$target"
            set -Ux HTTP_PROXY "$target"
            set -Ux HTTPS_PROXY "$target"
            set -Ux all_proxy "$target"
            set -Ux ALL_PROXY "$target"
        end
        set -Ux no_proxy "$default_no_proxy"
        set -Ux NO_PROXY "$default_no_proxy"
        echo "$target" > "$proxy_file"
        set_color green; echo "  ✓ Shell Environment set -> $target"; set_color normal
    end

    function _proxy_env_off --inherit-variable proxy_file
        set -e -g http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
        set -e -U http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
        rm -f "$proxy_file"
        set_color yellow; echo "  ✓ Shell Environment cleared"; set_color normal
    end

    # --- Target: APT Configuration (/etc/apt/apt.conf.d/99proxy) ---
    function _proxy_apt_set --argument-names target --inherit-variable apt_proxy_file
        echo "Configuring APT proxy (requires sudo)..."
        set -l apt_content "# Managed by fish proxy\nAcquire::http::Proxy \"$target\";\nAcquire::https::Proxy \"$target\";\n"
        if echo -e "$apt_content" | sudo tee "$apt_proxy_file" > /dev/null
            set_color green; echo "  ✓ APT Proxy configured ($apt_proxy_file)"; set_color normal
        else
            set_color red; echo "  ✗ Failed to configure APT proxy"; set_color normal
        end
    end

    function _proxy_apt_off --inherit-variable apt_proxy_file
        if test -f "$apt_proxy_file"
            echo "Removing APT proxy (requires sudo)..."
            if sudo rm -f "$apt_proxy_file"
                set_color yellow; echo "  ✓ APT Proxy removed ($apt_proxy_file)"; set_color normal
            else
                set_color red; echo "  ✗ Failed to remove APT proxy"; set_color normal
            end
        else
            echo "  - APT Proxy already clear"
        end
    end

    # --- Target: Docker CLI (~/.docker/config.json) ---
    function _proxy_docker_client_set --argument-names target --inherit-variable docker_config_file --inherit-variable default_no_proxy
        mkdir -p (dirname "$docker_config_file")
        python3 -c "
import json, os, sys

path = os.path.expanduser('$docker_config_file')
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
    'noProxy': '$default_no_proxy'
}

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"
        if test $status -eq 0
            set_color green; echo "  ✓ Docker Client config updated ($docker_config_file)"; set_color normal
        else
            set_color red; echo "  ✗ Failed to update Docker Client config"; set_color normal
        end
    end

    function _proxy_docker_client_off --inherit-variable docker_config_file
        if test -f "$docker_config_file"
            python3 -c "
import json, os

path = os.path.expanduser('$docker_config_file')
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
            set_color yellow; echo "  ✓ Docker Client proxy config removed"; set_color normal
        else
            echo "  - Docker Client config not present"
        end
    end

    # --- Target: Docker Daemon Systemd ---
    function _proxy_docker_daemon_set --argument-names target --inherit-variable docker_systemd_dir --inherit-variable docker_systemd_file --inherit-variable default_no_proxy
        if command -q docker; or test -d "/lib/systemd/system/docker.service" -o -d "/etc/systemd/system"
            echo "Configuring Docker daemon proxy (requires sudo)..."
            sudo mkdir -p "$docker_systemd_dir"
            set -l daemon_conf "[Service]\nEnvironment=\"HTTP_PROXY=$target\"\nEnvironment=\"HTTPS_PROXY=$target\"\nEnvironment=\"NO_PROXY=$default_no_proxy\"\n"
            if echo -e "$daemon_conf" | sudo tee "$docker_systemd_file" > /dev/null
                sudo systemctl daemon-reload
                if systemctl is-active --quiet docker
                    sudo systemctl restart docker
                end
                set_color green; echo "  ✓ Docker Daemon proxy configured & reloaded"; set_color normal
            else
                set_color red; echo "  ✗ Failed to configure Docker Daemon proxy"; set_color normal
            end
        else
            echo "  - Docker daemon service not found, skipping daemon configuration."
        end
    end

    function _proxy_docker_daemon_off --inherit-variable docker_systemd_file
        if test -f "$docker_systemd_file"
            echo "Removing Docker daemon proxy (requires sudo)..."
            if sudo rm -f "$docker_systemd_file"
                sudo systemctl daemon-reload
                if systemctl is-active --quiet docker
                    sudo systemctl restart docker
                end
                set_color yellow; echo "  ✓ Docker Daemon proxy removed & reloaded"; set_color normal
            else
                set_color red; echo "  ✗ Failed to remove Docker Daemon proxy"; set_color normal
            end
        else
            echo "  - Docker Daemon proxy already clear"
        end
    end

    # Helper to show proxy status across all modules
    function _proxy_status --inherit-variable proxy_file --inherit-variable apt_proxy_file --inherit-variable docker_config_file --inherit-variable docker_systemd_file
        set_color cyan; echo "=== Proxy Status Dashboard ==="; set_color normal
        
        # 1. Shell Env
        echo ""
        set_color blue; echo "[Shell Environment]"; set_color normal
        if set -q http_proxy; or set -q HTTP_PROXY; or set -q all_proxy; or set -q ALL_PROXY
            set_color green; echo "  ● Status      : ON"; set_color normal
            echo "    http_proxy  : "(set -q http_proxy; and echo "$http_proxy"; or echo "not set")
            echo "    https_proxy : "(set -q https_proxy; and echo "$https_proxy"; or echo "not set")
            echo "    all_proxy   : "(set -q all_proxy; and echo "$all_proxy"; or echo "not set")
            echo "    no_proxy    : "(set -q no_proxy; and echo "$no_proxy"; or echo "not set")
        else
            set_color yellow; echo "  ○ Status      : OFF"; set_color normal
        end
        if test -f "$proxy_file"
            echo "    State File  : "(cat "$proxy_file")
        end

        # 2. APT
        echo ""
        set_color blue; echo "[APT Package Manager]"; set_color normal
        if test -f "$apt_proxy_file"
            set_color green; echo "  ● Status      : Configured ($apt_proxy_file)"; set_color normal
            cat "$apt_proxy_file" | string replace -r '^' '    '
        else
            set_color yellow; echo "  ○ Status      : Not Configured"; set_color normal
        end

        # 3. Docker CLI
        echo ""
        set_color blue; echo "[Docker Client (~/.docker/config.json)]"; set_color normal
        if test -f "$docker_config_file"
            set -l has_docker_proxy (python3 -c "
import json, os
try:
    with open(os.path.expanduser('$docker_config_file')) as f:
        d = json.load(f)
        p = d.get('proxies', {}).get('default', {})
        if p:
            print(p.get('httpProxy', 'configured'))
except:
    pass
")
            if test -n "$has_docker_proxy"
                set_color green; echo "  ● Status      : ON ($has_docker_proxy)"; set_color normal
            else
                set_color yellow; echo "  ○ Status      : OFF"; set_color normal
            end
        else
            set_color yellow; echo "  ○ Status      : OFF"; set_color normal
        end

        # 4. Docker Daemon
        echo ""
        set_color blue; echo "[Docker Daemon (Systemd)]"; set_color normal
        if test -f "$docker_systemd_file"
            set_color green; echo "  ● Status      : Configured ($docker_systemd_file)"; set_color normal
            cat "$docker_systemd_file" | string replace -r '^' '    '
        else
            set_color yellow; echo "  ○ Status      : Not Configured"; set_color normal
        end
        echo ""
    end

    # --- Argument Parsing & Dispatching ---
    set -l is_system_mode 0
    set -l is_off 0
    set -l is_status 0
    set -l target_arg ""

    for arg in $argv
        switch "$arg"
            case "-h" "--help" "help"
                _proxy_help
                return 0
            case "-a" "--all" "--system"
                set is_system_mode 1
            case "off" "clear" "disable"
                set is_off 1
            case "status" "show"
                set is_status 1
            case '*'
                set target_arg "$arg"
        end
    end

    if test $is_status -eq 1
        _proxy_status
        return 0
    end

    if test $is_off -eq 1
        set_color cyan; echo "Turning Proxy OFF..."; set_color normal
        _proxy_env_off
        if test $is_system_mode -eq 1
            _proxy_apt_off
            _proxy_docker_client_off
            _proxy_docker_daemon_off
        end
        return 0
    end

    if test -n "$target_arg"
        set -l normalized (_proxy_normalize "$target_arg")
        if test -z "$normalized"
            echo "Invalid proxy argument."
            return 1
        end

        if test $is_system_mode -eq 1
            set_color cyan; echo "● Setting System-Wide Proxy (Shell + APT + Docker) -> $normalized"; set_color normal
            _proxy_env_set "$normalized"
            _proxy_apt_set "$normalized"
            _proxy_docker_client_set "$normalized"
            _proxy_docker_daemon_set "$normalized"
        else
            set_color cyan; echo "● Setting Shell Proxy -> $normalized"; set_color normal
            _proxy_env_set "$normalized"
            echo "  (Tip: use 'proxy --all <url>' to also configure APT & Docker)"
        end
        return 0
    end

    # Interactive Mode (no target or flags provided)
    set -l default_presets \
        "http://localhost:3067" \
        "http://localhost:10808" \
        "socks5h://127.0.0.1:1080" \
        "socks5h://127.0.0.1:2080"

    set_color cyan; echo "Current Status:"; set_color normal
    _proxy_status

    set_color cyan; echo "Select Target Mode:"; set_color normal
    echo "  [1] Shell Environment Only (Default)"
    echo "  [2] System-Wide (Shell + APT + Docker)"
    read -P "Mode [default: 1]: " -l mode_choice
    if test "$mode_choice" = "2"
        set is_system_mode 1
    else
        set is_system_mode 0
    end

    echo ""
    set_color cyan; echo "Select Proxy Preset or Action:"; set_color normal
    echo "  [0] Turn proxy OFF"
    for i in (seq (count $default_presets))
        echo "  [$i] $default_presets[$i]"
    end
    echo "  [c] Enter custom address / port"
    echo "  [q] Cancel / Quit"
    echo ""

    read -P "Choice [default: 1]: " -l choice
    if test -z "$choice"
        set choice 1
    end

    set -l selected_target ""
    switch "$choice"
        case 0 "off"
            _proxy_env_off
            if test $is_system_mode -eq 1
                _proxy_apt_off
                _proxy_docker_client_off
                _proxy_docker_daemon_off
            end
            return 0
        case q "quit" "exit"
            return 0
        case c "custom"
            read -P "Enter proxy address or port (e.g. 3068, 127.0.0.1:3068, http://...): " -l custom_input
            if test -n "$custom_input"
                set selected_target (_proxy_normalize "$custom_input")
            else
                echo "No input provided."
                return 1
            end
        case (seq (count $default_presets))
            set selected_target $default_presets[$choice]
        case '*'
            set selected_target (_proxy_normalize "$choice")
    end

    if test -n "$selected_target"
        if test $is_system_mode -eq 1
            set_color cyan; echo "● Setting System-Wide Proxy -> $selected_target"; set_color normal
            _proxy_env_set "$selected_target"
            _proxy_apt_set "$selected_target"
            _proxy_docker_client_set "$selected_target"
            _proxy_docker_daemon_set "$selected_target"
        else
            set_color cyan; echo "● Setting Shell Proxy -> $selected_target"; set_color normal
            _proxy_env_set "$selected_target"
        end
    end
end
