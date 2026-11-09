function cm --description "Unified Chezmoi Dotfiles & Mesh Manager"
    set -l cmd $argv[1]

    switch "$cmd"
        case -h --help help ""
            echo -e "\033[1;35m== Chezmoi Dotfiles Manager (cm) ==\033[0m"
            echo -e "\033[1;33mUsage:\033[0m cm <subcommand> [options]"
            echo ""
            echo "Subcommands:"
            echo "  sync [<peer>] [-n]  Sync dotfiles P2P with all or a specific peer device"
            echo "  apply [deep|none]   Apply dotfiles changes to system (deep=auto reload desktop, none=skip reload)"
            echo "  patch [status]      Apply or inspect system patches (omarchy icon-font)"
            echo "  install             Run package verification & installer scripts"
            echo "  diff                Show differences between target and destination (chezmoi diff)"
            echo "  status              Show status of managed files (chezmoi status)"
            echo "  -h, --help          Show this help message"
            return 0

        case sync
            set -l py_args "dotsync"
            set -l has_peer 0
            for arg in $argv[2..-1]
                switch "$arg"
                    case -n --dry-run dry-run dryrun
                        set -a py_args "-n"
                    case '*'
                        set -a py_args "$arg"
                end
            end
            python3 ~/.config/scripts/mesh_core.py $py_args
            return $status

        case apply
            set -l mode "interactive"
            if test (count $argv) -ge 2
                set mode $argv[2]
            end

            echo -e "\033[1;36m🔄 Applying Chezmoi state to home directory...\033[0m"
            chezmoi apply
            if test $status -ne 0
                echo -e "\033[1;31m❌ Chezmoi apply failed.\033[0m"
                return 1
            end

            # Reload shell configuration
            if test -f "$HOME/.config/fish/config.fish"
                echo -e "\033[1;36m🐚 Reloading Fish config...\033[0m"
                source "$HOME/.config/fish/config.fish"
                echo -e "\033[1;32m✅ Fish config reloaded.\033[0m"
            end

            # Skip desktop reload if mode is 'none' or on Termux
            if test "$mode" = "none"; or test -n "$TERMUX_VERSION"
                return 0
            end

            # On Omarchy Linux desktop: check if reload tools exist
            if begin command -q omarchy-restart-hyprctl; or command -q omarchy-restart-shell; end
                set -l should_reload 0
                if test "$mode" = "deep"
                    set should_reload 1
                else
                    read -l -P "Reload desktop components (Hyprland WM & top bar)? [y/N]: " confirm_desktop
                    if string match -qi "y" "$confirm_desktop"
                        set should_reload 1
                    end
                end

                if test $should_reload -eq 1
                    if command -q omarchy-restart-hyprctl
                        echo -e "\033[1;36m🖥️  Reloading Hyprland WM...\033[0m"
                        omarchy-restart-hyprctl >/dev/null 2>&1
                    end
                    if command -q omarchy-restart-shell
                        echo -e "\033[1;36m📊 Reloading Omarchy shell bar...\033[0m"
                        omarchy-restart-shell >/dev/null 2>&1
                    end
                    echo -e "\033[1;32m✅ Desktop components reloaded.\033[0m"
                else
                    echo -e "\033[0;90mSkipped desktop reload.\033[0m"
                end
            end
            return 0

        case patch
            set -l patch_action "install"
            if test (count $argv) -ge 2
                set patch_action $argv[2]
            end

            set -l patch_script "$HOME/.config/scripts/patch-omarchy-icon-font.sh"
            if not test -f "$patch_script"
                set patch_script (dirname (status filename))/../../scripts/executable_patch-omarchy-icon-font.sh
            end

            if not test -f "$patch_script"
                echo -e "\033[1;31m❌ Patch script not found:\033[0m $patch_script"
                return 1
            end

            bash "$patch_script" "$patch_action"
            return $status

        case install
            set -l inst_script "$HOME/.config/scripts/check-packages.sh"
            if test -f "$inst_script"
                bash "$inst_script"
            else
                echo -e "\033[1;31m❌ Package checker script not found at:\033[0m $inst_script"
                return 1
            end

            set -l omarchy_plugins_script "$HOME/.config/scripts/setup-omarchy-plugins.sh"
            if test -f "$omarchy_plugins_script"
                bash "$omarchy_plugins_script"
            end

            set -l symlinks_script "$HOME/.config/scripts/setup-repo-symlinks.sh"
            if test -f "$symlinks_script"
                bash "$symlinks_script"
            end
            return 0

        case diff
            chezmoi diff $argv[2..-1]
            return $status

        case status
            chezmoi status $argv[2..-1]
            return $status

        case '*'
            echo -e "\033[1;31mUnknown subcommand:\033[0m '$cmd'"
            echo "Run 'cm --help' for available subcommands."
            return 1
    end
end

# Autocompletions for cm
complete -c cm -f -n '__fish_use_subcommand' -a 'sync' -d 'Sync dotfiles P2P across mesh devices'
complete -c cm -f -n '__fish_use_subcommand' -a 'apply' -d 'Apply dotfiles changes to system'
complete -c cm -f -n '__fish_use_subcommand' -a 'patch' -d 'Manage system dotfile patches'
complete -c cm -f -n '__fish_use_subcommand' -a 'install' -d 'Run installer and dependency verification'
complete -c cm -f -n '__fish_use_subcommand' -a 'diff' -d 'Show diff between target and destination'
complete -c cm -f -n '__fish_use_subcommand' -a 'status' -d 'Show status of managed files'
complete -c cm -f -n '__fish_use_subcommand' -a '--help' -d 'Show help message'

# Subcommand: sync
complete -c cm -f -n '__fish_seen_subcommand_from sync' -a '(python3 ~/.config/scripts/mesh_core.py complete sync_peers 2>/dev/null)' -d 'Peer device'
complete -c cm -f -n '__fish_seen_subcommand_from sync' -s n -l dry-run -d 'Check connections without pulling or pushing'

# Subcommand: apply
complete -c cm -f -n '__fish_seen_subcommand_from apply' -a 'deep' -d 'Apply and automatically reload Hyprland & Shell Bar'
complete -c cm -f -n '__fish_seen_subcommand_from apply' -a 'none' -d 'Apply dotfiles without reloading desktop components'

# Subcommand: patch
complete -c cm -f -n '__fish_seen_subcommand_from patch' -a 'status' -d 'Check patch installation status'
