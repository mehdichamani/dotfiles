function s --description "Fast, ergonomic SSH, tunnels and command runner powered by devices.toml & OpenSSH"
    set -l target ""
    set -l action ""
    set -l extra_args

    # Parse arguments
    if test (count $argv) -gt 0
        switch $argv[1]
            case -h --help help
                echo -e "\033[1;33mUsage:\033[0m s [<target>] [<tunnel | command | -L port>] [extra_args...]"
                echo "       s                          (Interactive device & action picker)"
                echo "       s <target>                 (Connect to fastest route of target)"
                echo "       s <target> rdp | vnc       (Launch tunnel/remote desktop)"
                echo "       s <target> reboot | lock   (Execute remote command directly)"
                echo "       s <target> 8080            (Forward local 8080:localhost:8080)"
                echo ""
                echo "💡 Tip: All tunnel arguments and commands are defined transparently in ~/.ssh/devices.toml"
                return 0
            case '*'
                set target $argv[1]
                if test (count $argv) -gt 1
                    set action $argv[2]
                end
                if test (count $argv) -gt 2
                    set extra_args $argv[3..-1]
                end
        end
    end

    # Interactive picker with fzf (Step 1: Select Node, Step 2: Select Action)
    if test -z "$target"
        if not command -q fzf
            echo -e "\033[1;31m❌ Error:\033[0m 'fzf' is required for the interactive picker."
            python3 ~/.config/scripts/mesh_core.py list-nodes
            return 1
        end

        while true
            # --- Step 1: Select Node with Live Preview ---
            set -l selected_node (python3 ~/.config/scripts/mesh_core.py list-nodes | fzf \
                --height=70% \
                --layout=reverse \
                --border=rounded \
                --prompt="📱 Select Node > " \
                --header="[Enter: Select] [Esc: Exit]" \
                --preview="python3 ~/.config/scripts/mesh_core.py preview {1}" \
                --preview-window="right:55%:border-left:wrap")

            if test -z "$selected_node"
                return 0
            end

            set target (string trim -- (string split '│' -- $selected_node)[1])
            test -z "$target"; and return 0

            # --- Step 2: Select Action (SSH, RDP, VNC, Commands) ---
            set -l action_list (python3 ~/.config/scripts/mesh_core.py list-actions "$target" 2>/dev/null)
            
            # If target has only default SSH shell (no tunnels or commands), break directly
            if test (count $action_list) -le 1
                set action ""
                break
            end

            set -l selected_action (printf "%s\n" $action_list | fzf \
                --height=60% \
                --layout=reverse \
                --border=rounded \
                --prompt="⚡ $target Action > " \
                --header="[Enter: Run] [Esc: Back to Nodes]")

            if test -z "$selected_action"
                # Pressed Esc -> go back to node selection
                set target ""
                continue
            end

            if string match -q "🐚*" -- "$selected_action"
                set action ""
            else
                # Extract action key (e.g. 'rdp', 'vnc', 'reboot')
                set -l raw_act (string replace -r '^[^\s]+\s+' '' -- "$selected_action")
                set action (string trim -- (string split '│' -- $raw_act)[1])
            end
            break
        end
    end

    # Resolve target and action via mesh_core.py
    set -l json_res (python3 ~/.config/scripts/mesh_core.py resolve "$target" "$action" $extra_args 2>/dev/null)
    if test -z "$json_res"
        # Fallback to direct ssh if python fails
        command ssh "$target" $action $extra_args
        return $status
    end

    set -l best_route (echo "$json_res" | python3 -c "import sys, json; print(json.load(sys.stdin).get('route', ''))")
    set -l act_type (echo "$json_res" | python3 -c "import sys, json; print(json.load(sys.stdin).get('action_type', ''))")
    set -l ssh_args (echo "$json_res" | python3 -c "import sys, json; print('\n'.join(json.load(sys.stdin).get('ssh_args', [])))")

    test -z "$best_route"; and set best_route "$target"

    # Handle RDP / VNC helper launching
    if string match -q "tunnel:rdp*" -- "$act_type"
        echo -e "🖥️  \033[1;36m[RDP Tunnel]\033[0m Connecting via \033[1;32m$best_route\033[0m (127.0.0.1:3390)..."
        if test -n "$TERMUX_VERSION"; or string match -qi "*s24*" (cat ~/.config/name 2>/dev/null)
            if command -q am
                am start -n com.microsoft.rdc.androidx/com.microsoft.windowsapp.ui.HomeActivity >/dev/null 2>&1
            end
        else if command -q remmina
            remmina -c "rdp://127.0.0.1:3390" >/dev/null 2>&1 &
        end
    else if string match -q "tunnel:vnc*" -- "$act_type"
        echo -e "🖼️  \033[1;36m[VNC Tunnel]\033[0m Connecting via \033[1;32m$best_route\033[0m (127.0.0.1:5901)..."
        if test -n "$TERMUX_VERSION"; or string match -qi "*s24*" (cat ~/.config/name 2>/dev/null)
            if command -q am
                am start -n com.realvnc.viewer.android/.app.ConnectionChooserActivity >/dev/null 2>&1
            end
        else if command -q remmina
            remmina -c "vnc://127.0.0.1:5901" >/dev/null 2>&1 &
        end
    else if string match -q "command:*" -- "$act_type"
        echo -e "⚡ \033[1;33m[Executing]\033[0m on $best_route: $ssh_args"
    else
        echo -e "🚀 \033[1;32m[Connecting]\033[0m -> $best_route"
    end

    # Direct OpenSSH execution
    command ssh "$best_route" $ssh_args
    return $status
end

# Auto-completion
complete -c s -f -n '__fish_is_first_arg' -a '(python3 ~/.config/scripts/mesh_core.py complete targets 2>/dev/null)'
complete -c s -f -n 'test (count (commandline -poc)) -eq 2' -a '(python3 ~/.config/scripts/mesh_core.py complete actions (commandline -poc)[2] 2>/dev/null)'
