function s --description "Smart SSH connection parser with devices.toml inventory, named commands, RDP, VNC, and Port Forwarding support"
    set -l mode "ssh"
    set -l forward_spec ""
    set -l clean_argv
    set -l skip_next 0
    set -l target ""
    set -l explicit_cmd ""
    set -l list_commands 0

    # Parse special flags and subcommands:
    # Flags: -rdp, --rdp, -vnc, --vnc, -jellyfin, --jellyfin, -L, --port, -c, --command, --commands, -l, -h, --help
    # Subcommands: rdp, vnc, jellyfin, cmd/commands/run
    set -l argc (count $argv)
    for i in (seq 1 $argc)
        if test $skip_next -eq 1
            set skip_next 0
            continue
        end

        set -l arg $argv[$i]
        switch $arg
            case -h --help
                set target ""
                break
            case -rdp --rdp rdp
                set mode "rdp"
            case -vnc --vnc vnc
                set mode "vnc"
            case -jellyfin --jellyfin jellyfin
                set mode "jellyfin"
            case -c --command
                set -l next_idx (math $i + 1)
                if test $next_idx -le $argc
                    set explicit_cmd $argv[$next_idx]
                    set skip_next 1
                end
            case -l --commands commands
                set list_commands 1
            case -L --port -p
                set mode "forward"
                set -l next_idx (math $i + 1)
                if test $next_idx -le $argc
                    set forward_spec $argv[$next_idx]
                    set skip_next 1
                end
            case '-L*'
                set mode "forward"
                set forward_spec (string sub -s 3 -- $arg)
            case '*'
                set -a clean_argv $arg
        end
    end

    if test -z "$target"; and test (count $clean_argv) -gt 0
        set target $clean_argv[1]
        set extra_args $clean_argv[2..-1]
    end

    set -l devices_toml "$HOME/.ssh/devices.toml"
    if not test -f "$devices_toml"
        set devices_toml "$HOME/.local/share/chezmoi/dot_ssh/devices.toml"
    end

    # Interactive TUI Mode (Yazi-like Touch & Mobile Friendly)
    if test -z "$target"
        # If -h or --help was explicitly passed, show usage
        if contains -- -h $argv; or contains -- --help $argv
            echo -e "\033[1;33mUsage:\033[0m s [<target>] [rdp | vnc | jellyfin | -L <port>] [<named_command> | extra_args...]"
            echo "       s <target> <named_command>       (e.g. s 2011 wake-workpc, s work reboot)"
            echo "       s <target> --commands            (List all defined commands for target)"
            echo "       s <target> rdp | s rdp <target>  (Launch RDP tunnel/session)"
            echo "       s <target> vnc | s vnc <target>  (Launch VNC tunnel/session)"
            echo "       s -L 8096 <target>               (Port forward)"
            echo ""
            echo "💡 Tip: Run 's' with no arguments for the interactive Yazi-style menu (touch & Termux friendly)."
            return 0
        end

        # Check if fzf is installed for interactive TUI mode
        if not command -q fzf
            echo -e "\033[1;31m❌ Error:\033[0m 'fzf' is required for the interactive menu."
            if test -n "$TERMUX_VERSION"
                echo -e "💡 Install it in Termux via: \033[1;32mpkg install fzf\033[0m"
            else
                echo -e "💡 Please install 'fzf' using your system package manager (e.g. pacman -S fzf / apt install fzf)."
            end
            return 1
        end

        while true
            # --- Step 1: Select Node (Miller-column / Yazi-like Preview) ---
            set -l node_list (python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open('$devices_toml', 'rb') as f:
    data = tomllib.load(f)
for node, info in data.get('ssh', {}).items():
    name = info.get('name', node)
    print(f'{node:<12} │ {name}')
" 2>/dev/null)

            if test -z "$node_list"
                echo "⚠️ No SSH nodes found in $devices_toml"
                return 1
            end

            set -l selected_line (printf "%s\n" $node_list | fzf \
                --height=70% \
                --min-height=15 \
                --layout=reverse \
                --border=rounded \
                --prompt="📱 Select Node > " \
                --header="[Right / Enter: Select] [ESC / Left: Exit]" \
                --bind="right:accept,left:abort" \
                --preview="python3 -c '
import sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
try:
    with open(\"$devices_toml\", \"rb\") as f:
        d = tomllib.load(f)
    node = sys.argv[1] if len(sys.argv) > 1 else \"\"
    i = d.get(\"ssh\", dict()).get(node, dict())
    if not i:
        sys.exit(0)
    name = i.get(\"name\", node)
    sh = i.get(\"shell\", \"-\")
    sy = i.get(\"sync\", False)
    rt = \", \".join(i.get(\"routes\", list())) or \"-\"
    cp = \", \".join(i.get(\"capabilities\", list())) or \"-\"
    print(f\"\033[1;36m=== {name} ({node}) ===\033[0m\n\")
    print(f\"\033[1;33mOS Shell:\033[0m  {sh}\")
    print(f\"\033[1;33mSync Repo:\033[0m {sy}\")
    print(f\"\033[1;33mRoutes:\033[0m    {rt}\")
    print(f\"\033[1;33mCaps:\033[0m      {cp}\")
    cmds = i.get(\"commands\", dict())
    if cmds:
        print(\"\n\033[1;32m📋 Named Commands:\033[0m\")
        for c, v in cmds.items():
            print(f\"  • \033[1;36m{c:<14}\033[0m -> {v}\")
except Exception as e:
    print(e)
' {1}" \
                --preview-window="right:55%:border-left:wrap")

            if test -z "$selected_line"
                return 0
            end

            set target (string split -n ' ' -- $selected_line)[1]
            test -z "$target"; and return 0

            # --- Step 2: Select Action / Commands (flattened list) ---
            set -l action_list (python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open('$devices_toml', 'rb') as f:
    data = tomllib.load(f)
info = data.get('ssh', {}).get('$target', {})
caps = info.get('capabilities', [])
shell = info.get('shell', '')

idx = 1
def item(label):
    global idx
    print(f'{idx:<2} │ {label}')
    idx += 1

item('🐚 SSH Shell')
if 'rdp' in caps or shell == 'pwsh':
    item('🖥️  RDP Remote Desktop')
if 'vnc' in caps:
    item('🖼️  VNC Remote Display')
if 'jellyfin' in caps:
    item('🍿 Jellyfin Tunnel')

cmds = info.get('commands', {})
for k, v in cmds.items():
    item(f'⚡ {k:<16} │ {v}')

item('🔌 Port Forward (-L)')
" 2>/dev/null)

            set -l chosen_action (printf "%s\n" $action_list | fzf \
                --height=60% \
                --min-height=12 \
                --layout=reverse \
                --border=rounded \
                --prompt="⚡ $target Action > " \
                --header="[Right / Enter: Run] [Left / ESC: Back to Nodes]" \
                --bind="right:accept,left:abort")

            if test -z "$chosen_action"
                # Pressed Left or ESC -> Go back to node selection
                set target ""
                continue
            end

            # Parse selection
            set -l act_text (string replace -r '^[0-9]+\s*│\s*' '' -- "$chosen_action")
            if string match -q '🐚*' -- "$act_text"
                set mode "ssh"
                break
            else if string match -q '🖥️*' -- "$act_text"
                set mode "rdp"
                break
            else if string match -q '🖼️*' -- "$act_text"
                set mode "vnc"
                break
            else if string match -q '🍿*' -- "$act_text"
                set mode "jellyfin"
                break
            else if string match -q '🔌*' -- "$act_text"
                # Port forwarding input
                echo -n "Enter Port (e.g. 8080 or 8080:3000): "
                read -l input_port
                if test -n "$input_port"
                    set mode "forward"
                    set forward_spec "$input_port"
                    break
                else
                    continue
                end
            else if string match -q '⚡*' -- "$act_text"
                # Named command directly selected
                set -l raw_cmd (string replace -r '^⚡\s*' '' -- "$act_text")
                set -l cmd_name (string split -n ' ' -- "$raw_cmd")[1]
                set extra_args $cmd_name
                break
            else
                break
            end
        end
    end

    # Handle --commands / -l flag
    if test $list_commands -eq 1
        if test -f "$devices_toml"
            set -l cmd_output (python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open('$devices_toml', 'rb') as f:
    data = tomllib.load(f)
info = data.get('ssh', {}).get('$target', {})
cmds = info.get('commands', {})
if cmds:
    print(f'📋 Commands for {info.get(\"name\", \"$target\")}:')
    for k, v in cmds.items():
        print(f'  - \033[1;32m{k:<16}\033[0m : {v}')
else:
    print(f'ℹ️ No named commands defined for target \'$target\'.')
" 2>/dev/null)
            for line in $cmd_output
                echo -e "$line"
            end
            return 0
        end
    end

    # Check for named command match
    set -l final_command ""
    if test -n "$explicit_cmd"
        set final_command $explicit_cmd
    else if test (count $extra_args) -gt 0
        set -l potential_cmd $extra_args[1]
        set -l lookup_cmd (python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open('$devices_toml', 'rb') as f:
    data = tomllib.load(f)
cmds = data.get('ssh', {}).get('$target', {}).get('commands', {})
if '$potential_cmd' in cmds:
    print(cmds['$potential_cmd'])
" 2>/dev/null)
        if test -n "$lookup_cmd"
            set final_command "$lookup_cmd"
            set extra_args $extra_args[2..-1]
        end
    end

    # Helper function to launch GUI client, tunnel or SSH command
    function _s_connect -V mode -V forward_spec -V extra_args -V final_command
        set -l host $argv[1]

        if test -n "$final_command"
            echo -e "🚀 \033[1;36m[Executing Command]\033[0m on $host: \033[1;33m$final_command\033[0m"
            command ssh "$host" $final_command $extra_args
            return $status
        end

        if test "$mode" = "jellyfin"
            echo -e "🍿 \033[1;35m[Jellyfin Tunnel]\033[0m Forwarding local port 8096 to $host:8096..."
            echo -e "🌐 \033[1;33mWeb UI:\033[0m \033[1;32mhttp://127.0.0.1:8096\033[0m"
            echo "🔒 SSH Tunnel is active in foreground. Press Ctrl+C to close."
            command ssh -N -L 8096:localhost:8096 "$host" $extra_args
            return $status

        else if test "$mode" = "forward"
            set -l l_spec $forward_spec
            if string match -qr '^[0-9]+$' -- "$l_spec"
                set l_spec "$l_spec:localhost:$l_spec"
            else if string match -qr '^[0-9]+:[0-9]+$' -- "$l_spec"
                set -l parts (string split ':' -- "$l_spec")
                set l_spec "$parts[1]:localhost:$parts[2]"
            end

            echo -e "🔌 \033[1;36m[Port Forward]\033[0m Local $l_spec via $host..."
            set -l local_port (string split ':' -- "$l_spec")[1]
            echo -e "🌐 \033[1;33mLocal Address:\033[0m \033[1;32mhttp://127.0.0.1:$local_port\033[0m (if HTTP/Web service)"
            echo "🔒 SSH Tunnel is active in foreground. Press Ctrl+C to close."
            command ssh -N -L "$l_spec" "$host" $extra_args
            return $status

        else if test "$mode" = "rdp"
            echo "🖥️  [RDP Mode] Forwarding local port 3390 to $host:3389..."
            set -l is_android 0
            if test -n "$TERMUX_VERSION"; or string match -qi "*s24*" (cat ~/.config/name 2>/dev/null)
                set is_android 1
            end

            if test $is_android -eq 1
                echo "🚀 Launching Windows App..."
                if command -q am
                    am start -n com.microsoft.rdc.androidx/com.microsoft.windowsapp.ui.HomeActivity >/dev/null 2>&1
                end
                echo ""
                echo -e "💡 \033[1;33mTarget Address:\033[0m \033[1;32m127.0.0.1:3390\033[0m"
                echo "🔒 SSH Tunnel is active in foreground. Press Ctrl+C to close."
                command ssh -N -L 3390:localhost:3389 "$host" $extra_args
                return $status
            else if command -q remmina
                command ssh -N -L 3390:localhost:3389 "$host" $extra_args &
                set -l ssh_pid $last_pid

                for i in (seq 1 30)
                    if not kill -0 $ssh_pid 2>/dev/null
                        break
                    end
                    if ss -tlpn 2>/dev/null | grep -q ':3390 '
                        break
                    end
                    sleep 0.1
                end

                if not kill -0 $ssh_pid 2>/dev/null
                    echo "❌ Failed to establish SSH tunnel."
                    return 1
                end

                echo "🚀 Launching Remmina (rdp://127.0.0.1:3390)..."
                remmina -c "rdp://127.0.0.1:3390" >/dev/null 2>&1 &

                echo ""
                echo -e "💡 \033[1;33mTarget Address:\033[0m \033[1;32m127.0.0.1:3390\033[0m"
                echo "🔒 SSH Tunnel is active in foreground. Press Ctrl+C to close."

                function _s_cleanup_rdp --on-signal SIGINT -V ssh_pid
                    kill $ssh_pid 2>/dev/null
                end

                wait $ssh_pid 2>/dev/null
                functions -e _s_cleanup_rdp
                kill $ssh_pid 2>/dev/null
                return 0
            else if command -q mstsc.exe; or command -q mstsc
                command ssh -f -N -L 3390:localhost:3389 "$host" $extra_args
                mstsc /v:127.0.0.1:3390
                return 0
            else
                echo -e "💡 \033[1;33mTunnel active! Connect RDP client to:\033[0m \033[1;36m127.0.0.1:3390\033[0m"
                echo "Press Ctrl+C to close tunnel."
                command ssh -N -L 3390:localhost:3389 "$host" $extra_args
                return $status
            end

        else if test "$mode" = "vnc"
            echo "🖼️  [VNC Mode] Forwarding local port 5901 to $host:5900..."
            set -l is_android 0
            if test -n "$TERMUX_VERSION"; or string match -qi "*s24*" (cat ~/.config/name 2>/dev/null)
                set is_android 1
            end

            if test $is_android -eq 1
                echo "🚀 Launching RVNC Viewer..."
                if command -q am
                    am start -n com.realvnc.viewer.android/.app.ConnectionChooserActivity >/dev/null 2>&1
                end
                echo ""
                echo -e "💡 \033[1;33mTarget Address:\033[0m \033[1;32m127.0.0.1:5901\033[0m"
                echo "🔒 SSH Tunnel is active in foreground. Press Ctrl+C to close."
                command ssh -N -L 5901:localhost:5900 "$host" $extra_args
                return $status
            else if command -q remmina
                command ssh -N -L 5901:localhost:5900 "$host" $extra_args &
                set -l ssh_pid $last_pid

                for i in (seq 1 30)
                    if not kill -0 $ssh_pid 2>/dev/null
                        break
                    end
                    if ss -tlpn 2>/dev/null | grep -q ':5901 '
                        break
                    end
                    sleep 0.1
                end

                if not kill -0 $ssh_pid 2>/dev/null
                    echo "❌ Failed to establish SSH tunnel."
                    return 1
                end

                echo "🚀 Launching Remmina (vnc://127.0.0.1:5901)..."
                remmina -c "vnc://127.0.0.1:5901" >/dev/null 2>&1 &

                echo ""
                echo -e "💡 \033[1;33mTarget Address:\033[0m \033[1;32m127.0.0.1:5901\033[0m"
                echo "🔒 SSH Tunnel is active in foreground. Press Ctrl+C to close."

                function _s_cleanup_vnc --on-signal SIGINT -V ssh_pid
                    kill $ssh_pid 2>/dev/null
                end

                wait $ssh_pid 2>/dev/null
                functions -e _s_cleanup_vnc
                kill $ssh_pid 2>/dev/null
                return 0
            else
                echo -e "💡 \033[1;33mTunnel active! Connect VNC client to:\033[0m \033[1;36m127.0.0.1:5901\033[0m"
                echo "Press Ctrl+C to close tunnel."
                command ssh -N -L 5901:localhost:5900 "$host" $extra_args
                return $status
            end

        else
            command ssh "$host" $extra_args
            return $status
        end
    end

    # Extract candidate routes for target from devices.toml
    set -l candidate_hosts
    if test -f "$devices_toml"
        set candidate_hosts (python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open('$devices_toml', 'rb') as f:
    data = tomllib.load(f)
routes = data.get('ssh', {}).get('$target', {}).get('routes', [])
for r in routes:
    print(r)
" 2>/dev/null)
    end

    # If target is not a node with multiple routes, try connecting directly
    if test (count $candidate_hosts) -eq 0
        _s_connect "$target"
        return $status
    end

    echo "🔍 Probing target '$target': $candidate_hosts"

    set -l tmp_dir (mktemp -d 2>/dev/null; or mktemp -d -t s_probe)
    set -l idx 1

    for h in $candidate_hosts
        set -l h_info (command ssh -G "$h" 2>/dev/null | awk '/^hostname / {hn=$2} /^port / {pt=$2} END {print hn; print pt}')
        set -l hn $h_info[1]
        set -l pt $h_info[2]
        test -z "$pt"; and set pt 22

        fish -c "
            if test -n '$hn'
                # Fast TCP probe via python (nc is often missing on Termux).
                # 4s timeout is needed for WAN routes; LAN misses fail fast anyway.
                if python3 -c 'import socket,sys; s=socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=4); s.close()' '$hn' '$pt' >/dev/null 2>&1
                    touch '$tmp_dir/succ_$idx'
                else
                    # Fallback: full SSH handshake (covers hosts where TCP probe is filtered).
                    if command ssh -o ConnectTimeout=5 -o BatchMode=yes -o ClearAllForwardings=yes -q '$h' \"exit 0\" >/dev/null 2>&1
                        touch '$tmp_dir/succ_$idx'
                    end
                end
            end
        " &
        set idx (math $idx + 1)
    end

    # Wait up to ~8s for any probe to succeed (WAN needs >1s).
    for t in (seq 1 80)
        set -l found 0
        for i in (seq 1 (count $candidate_hosts))
            if test -f "$tmp_dir/succ_$i"
                set found 1
                break
            end
        end
        if test $found -eq 1
            break
        end
        if test (count (jobs -p)) -eq 0
            break
        end
        sleep 0.1
    end

    set -l selected_host ""
    for i in (seq 1 (count $candidate_hosts))
        if test -f "$tmp_dir/succ_$i"
            set selected_host $candidate_hosts[$i]
            break
        end
    end

    kill (jobs -p) 2>/dev/null
    rm -rf "$tmp_dir"

    if test -n "$selected_host"
        echo "  ✅ Best route: $selected_host"
        _s_connect "$selected_host"
        return $status
    end

    echo "⚠️ All routes for '$target' failed to respond."
    return 1
end

# Dynamic Auto-completion for devices, commands, and options
complete -c s -f -a '(
    set -l dev_file "$HOME/.ssh/devices.toml"
    if not test -f "$dev_file"
        set dev_file "$HOME/.local/share/chezmoi/dot_ssh/devices.toml"
    end
    if test -f "$dev_file"
        python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open(\"$dev_file\", \"rb\") as f:
    data = tomllib.load(f)
for node, info in data.get(\"ssh\", {}).items():
    print(node)
    for r in info.get(\"routes\", []):
        print(r)
" 2>/dev/null
    end
    echo -rdp
    echo -vnc
    echo -jellyfin
    echo --jellyfin
    echo -L
    echo --port
    echo -l
    echo --commands
)'

# Dynamic command auto-completion after target
complete -c s -f -n '__fish_prev_arg_in_command (
    set -l dev_file "$HOME/.ssh/devices.toml"
    if not test -f "$dev_file"; set dev_file "$HOME/.local/share/chezmoi/dot_ssh/devices.toml"; end
    if test -f "$dev_file"
        python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open(\"$dev_file\", \"rb\") as f:
    data = tomllib.load(f)
print(\" \".join(data.get(\"ssh\", {}).keys()))
" 2>/dev/null
    end
)' -a '(
    set -l prev_tokens (commandline -poc)
    set -l target $prev_tokens[2]
    set -l dev_file "$HOME/.ssh/devices.toml"
    if not test -f "$dev_file"; set dev_file "$HOME/.local/share/chezmoi/dot_ssh/devices.toml"; end
    if test -f "$dev_file"
        python3 -c "
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open(\"$dev_file\", \"rb\") as f:
    data = tomllib.load(f)
cmds = data.get(\"ssh\", {}).get(\"$target\", {}).get(\"commands\", {})
for k in cmds.keys():
    print(k)
" 2>/dev/null
    end
)'
