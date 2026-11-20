# Defined for Fish shell
function sm --description 'Unified SSH & Secrets Vault Manager'
    set -l cmd $argv[1]

    switch "$cmd"
        case -h --help help ""
            echo -e "\033[1;35m== SSH & Secrets Vault Manager (sm) ==\033[0m"
            echo -e "\033[1;33mUsage:\033[0m sm <subcommand> [options]"
            echo ""
            echo "Subcommands:"
            echo "  sync [<peer>] [-n|-m]  P2P Mesh sync ~/.ssh with peer(s) (-m: push & mirror)"
            echo "  push | send            Encrypt and push local ~/.ssh & secrets to Cloud Vault"
            echo "  pull | get [-v N]      Download, diff and pull Cloud Vault snapshot into local ~/.ssh"
            echo "  status                 Quick dirty check of local files against latest Cloud Vault"
            echo "  history                List available snapshot versions stored in Cloud Vault"
            echo "  -h, --help             Show this help message"
            return 0

        case sync push send pull get status history
            set -l script_path "$HOME/.config/scripts/ssh_vault_core.py"
            if not test -f "$script_path"
                set script_path "$HOME/.local/share/chezmoi/dot_config/scripts/ssh_vault_core.py"
            end

            if not test -f "$script_path"
                echo -e "\033[1;31m❌ Error:\033[0m Backend script not found at $script_path" >&2
                return 1
            end

            python3 "$script_path" $argv
            return $status

        case '*'
            echo -e "\033[1;31mUnknown subcommand:\033[0m '$cmd'"
            echo "Run 'sm --help' for available subcommands."
            return 1
    end
end

# Auto-completions for sm
complete -c sm -f
complete -c sm -s h -l help -d "Show help message"

# Subcommands
complete -c sm -n '__fish_is_first_token' -a "sync" -d "P2P Mesh sync with peer devices"
complete -c sm -n '__fish_is_first_token' -a "push" -d "Push and encrypt local vault to Cloud"
complete -c sm -n '__fish_is_first_token' -a "send" -d "Alias for push"
complete -c sm -n '__fish_is_first_token' -a "pull" -d "Pull and decrypt Cloud vault to local"
complete -c sm -n '__fish_is_first_token' -a "get" -d "Alias for pull"
complete -c sm -n '__fish_is_first_token' -a "status" -d "Check local status against cloud"
complete -c sm -n '__fish_is_first_token' -a "history" -d "List cloud snapshot versions"

# Flags for push/pull/sync
complete -c sm -n '__fish_seen_subcommand_from sync pull get' -s n -l dry-run -d "Preview changes without applying"
complete -c sm -n '__fish_seen_subcommand_from sync' -s m -l mirror -d "Push and mirror (delete extra files on peer)"
complete -c sm -n '__fish_seen_subcommand_from pull get' -s v -l version -d "Cloud snapshot version number (1 to 5)"
complete -c sm -n '__fish_seen_subcommand_from pull get sync' -s d -l diff -d "Show detailed line diff"
complete -c sm -n '__fish_seen_subcommand_from pull get' -s y -l yes -d "Apply changes without confirmation prompt"

# Targets completion for sync
complete -c sm -n '__fish_seen_subcommand_from sync' -a '(python3 ~/.config/scripts/mesh_core.py complete 2>/dev/null)' -d "Peer Node"
