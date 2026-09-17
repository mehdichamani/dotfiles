function dotsync --description "Dynamic P2P Git sync for Chezmoi dotfiles across mesh devices"
    set -l action "sync"
    set -l is_dryrun 0
    set -l target_peer ""

    for arg in $argv
        switch "$arg"
            case -h --help help
                echo -e "\033[1;33mUsage:\033[0m dotsync [dry-run | apply | install | refresh | <peer_device>]"
                echo ""
                echo "Commands & Options:"
                echo "  (none)         Sync dotfiles repository with all reachable peer devices (auto push/pull)"
                echo "  <peer>         Sync dotfiles repository with a specific peer device (e.g. dotsync s24)"
                echo "  dry-run, -n    Check connections and commit differences without pushing or pulling"
                echo "  apply          Apply dotfiles changes to the live system (chezmoi apply)"
                echo "  install        Run package verification and installer (~/.config/scripts/check-packages.sh)"
                echo "  refresh        Apply chezmoi, reload desktop components, hooks, and fish config"
                echo "  -h, --help     Show this help message"
                return 0
            case dry-run dryrun -n --dry-run
                set is_dryrun 1
            case apply
                echo -e "\033[1;36m🔄 Applying Chezmoi state to home directory...\033[0m"
                chezmoi apply
                return $status
            case install
                set -l inst_script "$HOME/.config/scripts/check-packages.sh"
                if test -f "$inst_script"
                    echo -e "\033[1;36m📦 Running system package verification...\033[0m"
                    bash "$inst_script"
                    return $status
                else
                    echo -e "\033[1;31m❌ Package checker script not found at:\033[0m $inst_script"
                    return 1
                end
            case refresh
                echo -e "\033[1;36m✨ Refreshing live environment...\033[0m"
                chezmoi apply
                if test -f "$HOME/.config/fish/config.fish"
                    source "$HOME/.config/fish/config.fish"
                end
                if command -q hyprctl
                    hyprctl reload >/dev/null 2>&1
                end
                echo -e "\033[1;32m✅ Environment refreshed successfully.\033[0m"
                return 0
            case '*'
                set target_peer "$arg"
        end
    end

    # Delegate core git sync logic to mesh_core.py
    set -l py_args "dotsync"
    if test $is_dryrun -eq 1
        set -a py_args "-n"
    end
    if test -n "$target_peer"
        set -a py_args "$target_peer"
    end

    python3 ~/.config/scripts/mesh_core.py $py_args
    return $status
end

# Auto-completion
complete -c dotsync -f -a '(python3 ~/.config/scripts/mesh_core.py complete sync_peers 2>/dev/null; echo -e "dry-run\napply\ninstall\nrefresh\n--help")'
