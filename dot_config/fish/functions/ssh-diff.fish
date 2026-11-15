function ssh-diff --description "Zero-Knowledge Diff tool for ~/.ssh & ~/.ssh/secrets across hosts and cloud snapshots"
    set -l script_path "$HOME/.config/scripts/ssh_vault_diff.py"
    
    if not test -f "$script_path"
        echo "❌ Error: $script_path not found!" >&2
        return 1
    end

    python3 "$script_path" $argv
end

# Auto-completions for ssh-diff
complete -c ssh-diff -f
complete -c ssh-diff -s h -l help -d "Show help message"
complete -c ssh-diff -s l -l history -d "List cloud snapshot history versions"
complete -c ssh-diff -s v -l version -d "Cloud snapshot version number (1 to 5)"
complete -c ssh-diff -s d -l diff -d "Show detailed line-by-line diff directly"

# Positional targets completion (Local, Cloud, Cloud versions, and Devices from devices.toml)
set -l standard_targets local cloud cloud:v1 cloud:v2 cloud:v3 cloud:v4 cloud:v5
complete -c ssh-diff -n '__fish_is_first_token' -a "$standard_targets"
complete -c ssh-diff -n '__fish_is_first_token' -a '(python3 ~/.config/scripts/mesh_core.py complete 2>/dev/null)' -d "SSH Node"

complete -c ssh-diff -n 'not __fish_is_first_token' -a "$standard_targets"
complete -c ssh-diff -n 'not __fish_is_first_token' -a '(python3 ~/.config/scripts/mesh_core.py complete 2>/dev/null)' -d "SSH Node"
