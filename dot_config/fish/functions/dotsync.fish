function dotsync --description "Intelligent P2P Git sync and dotfiles manager for Chezmoi"
    set -l repo_dir "$HOME/.local/share/chezmoi"

    # Identify devices.toml (prioritize live ~/.ssh/devices.toml, fallback to chezmoi source repo)
    set -l devices_toml "$HOME/.ssh/devices.toml"
    if not test -f "$devices_toml"
        set devices_toml "$HOME/.local/share/chezmoi/dot_ssh/devices.toml"
    end

    # Dynamically extract sync-enabled peers from devices.toml (or fallback to ~/.ssh/config)
    set -l all_peers
    if test -f "$devices_toml"
        set all_peers (python3 -c "
import sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open('$devices_toml', 'rb') as f:
    data = tomllib.load(f)
peers = [k for k, v in data.get('ssh', {}).items() if v.get('sync') is True]
print('\n'.join(peers))
" 2>/dev/null)
    end

    # Fallback to ~/.ssh/config if devices.toml produced nothing
    if test (count $all_peers) -eq 0
        set -l ssh_config "$HOME/.ssh/config"
        if not test -f "$ssh_config"; and test -f "$HOME/.local/share/chezmoi/dot_ssh/config"
            set ssh_config "$HOME/.local/share/chezmoi/dot_ssh/config"
        end
        if test -f "$ssh_config"
            set all_peers (awk '
                BEGIN { cur_group = ""; is_sync = 0 }
                /^# @group/ {
                    if (cur_group != "" && is_sync) print cur_group;
                    cur_group = $3;
                    is_sync = 0;
                    next
                }
                /^# @sync/ && $3 ~ /true|yes|1/ {
                    is_sync = 1;
                    next
                }
                /^#/ && !/^# @/ {
                    if (cur_group != "" && is_sync) print cur_group;
                    cur_group = "";
                    is_sync = 0;
                }
                END {
                    if (cur_group != "" && is_sync) print cur_group;
                }
            ' "$ssh_config" 2>/dev/null)
        end
    end

    # Parse arguments
    set -l action "sync"
    set -l target_peer ""
    set -l is_dryrun 0
    set -l is_force 0
    set -l positional_args

    for arg_item in $argv
        switch "$arg_item"
            case -f --force
                set is_force 1
            case -h --help help
                set action "help"
            case dry-run dryrun -n --dry-run
                set action "dry-run"
                set is_dryrun 1
            case apply
                set action "apply"
            case install
                set action "install"
            case refresh
                set action "refresh"
            case '*'
                set -a positional_args "$arg_item"
        end
    end

    if test "$action" = "help"
        echo -e "\033[1;33mUsage:\033[0m dotsync [dry-run | apply | install | refresh | <peer_device>] [--force]"
        echo ""
        echo "Commands & Options:"
        echo "  (none)         Sync dotfiles repository with all reachable peer devices"
        echo "  <peer>         Sync dotfiles repository with a specific peer device (e.g. dotsync s24)"
        echo "  --force, -f    Force push current branch to peer without merging (e.g. dotsync s24 --force)"
        echo "  dry-run, -n    Check connections and commit differences without merging or pushing"
        echo "  apply          Apply dotfiles changes to the live system (chezmoi apply)"
        echo "  install        Run package verification and installer (~/.config/scripts/check-packages.sh)"
        echo "  refresh        Apply chezmoi, reload desktop components, hooks, and fish config"
        echo "  -h, --help     Show this help message"
        echo ""
        echo "Available Peer Devices (from ~/.ssh/devices.toml):"
        if test (count $all_peers) -gt 0
            echo "  $all_peers"
        else
            echo "  (No sync peers discovered in $devices_toml)"
        end
        return 0
    end

    if test (count $positional_args) -gt 1
        echo -e "\033[1;31m⚠️ Too many arguments.\033[0m dotsync accepts at most one peer or action command."
        echo "Run 'dotsync --help' for usage."
        return 1
    else if test (count $positional_args) -eq 1
        set -l raw_peer "$positional_args[1]"
        set -l peer_lower (string lower -- "$raw_peer")
        set -l matched 0
        for p in $all_peers
            if test "$peer_lower" = "$p"
                set matched 1
                set target_peer "$p"
                break
            end
        end

        if test $matched -eq 0
            echo -e "\033[1;31m❌ Unknown argument or peer device:\033[0m '$raw_peer'"
            echo ""
            echo "Available Peer Devices:"
            if test (count $all_peers) -gt 0
                echo "  $all_peers"
            else
                echo "  (none found in $devices_toml)"
            end
            echo ""
            echo "Run 'dotsync --help' for usage."
            return 1
        end
    end

    # Dispatch non-sync actions
    if test "$action" = "apply"
        echo -e "\033[1;36m🔄 Applying Chezmoi state to home directory...\033[0m"
        chezmoi apply
        return $status
    else if test "$action" = "install"
        set -l inst_script "$HOME/.config/scripts/check-packages.sh"
        if test -f "$inst_script"
            echo -e "\033[1;36m📦 Running system package verification...\033[0m"
            bash "$inst_script"
            return $status
        else
            echo -e "\033[1;31m❌ Package checker script not found at:\033[0m $inst_script"
            return 1
        end
    else if test "$action" = "refresh"
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
    end

    # --- P2P SYNC ENGINE ---
    set -l current_host (string trim (cat "$HOME/.config/name" 2>/dev/null))
    if test -z "$current_host"
        set current_host (hostname -s 2>/dev/null; or echo "unknown")
    end

    echo -e "\033[1;35m╔══════════════════════════════════════════════════════════════╗\033[0m"
    if test $is_dryrun -eq 1
        echo -e "\033[1;35m║\033[0m  \033[1;33m🔍 Dotsync P2P Mesh (DRY-RUN / INSPECTION MODE)\033[0m             \033[1;35m║\033[0m"
    else
        echo -e "\033[1;35m║\033[0m  \033[1;36m🔄 Dotsync P2P Mesh Synchronization\033[0m                         \033[1;35m║\033[0m"
    end
    echo -e "\033[1;35m║\033[0m  \033[0;90mHost: \033[1;32m$current_host\033[0;90m | Repo: $repo_dir\033[0m \033[1;35m║\033[0m"
    echo -e "\033[1;35m╚══════════════════════════════════════════════════════════════╝\033[0m"

    if not test -d "$repo_dir/.git"
        echo -e "\033[1;31m❌ Error:\033[0m $repo_dir is not a valid git repository."
        return 1
    end

    # 1. Local Status Check (Do not touch uncommitted changes)
    set -l dirty_files (git -C "$repo_dir" status --porcelain 2>/dev/null)
    if test -n "$dirty_files"
        echo -e "\n\033[1;33m⚠️ Uncommitted local changes detected in $repo_dir:\033[0m"
        git -C "$repo_dir" status --short
        echo -e "\033[0;90m  (Note: Uncommitted changes will be left untouched. Only committed history is synced.)\033[0m"
    else
        echo -e "\n\033[1;32m✓\033[0m Local repository clean (no uncommitted changes)."
    end

    # Determine peer list to sync
    set -l sync_peers
    if test -n "$target_peer"
        set sync_peers "$target_peer"
    else
        for p in $all_peers
            if test "$p" != "$current_host"
                set -a sync_peers "$p"
            end
        end
    end

    if test (count $sync_peers) -eq 0
        echo -e "\033[1;33mℹ️ No other peer devices to sync with.\033[0m"
        return 0
    end

    set -l total_peers (count $sync_peers)
    set -l synced_count 0
    set -l new_commits_pulled 0

    for peer in $sync_peers
        echo -e "\n\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "📡 \033[1;36mSyncing with peer:\033[0m \033[1;33m$peer\033[0m"
        echo -e "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

        # Discover remote repo path and candidate hosts for peer
        set -l peer_repo (python3 -c "
import sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open('$devices_toml', 'rb') as f:
    data = tomllib.load(f)
print(data.get('ssh', {}).get('$peer', {}).get('repo', '~/.local/share/chezmoi'))
" 2>/dev/null)
        if test -z "$peer_repo"
            set peer_repo "~/.local/share/chezmoi"
        end

        set -l peer_routes (python3 -c "
import sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open('$devices_toml', 'rb') as f:
    data = tomllib.load(f)
routes = data.get('ssh', {}).get('$peer', {}).get('routes', ['$peer'])
for r in routes:
    print(r)
" 2>/dev/null)
        if test (count $peer_routes) -eq 0
            set peer_routes "$peer"
        end

        # Fast parallel probe for reachable routes
        set -l reachable_host ""
        set -l tmp_dir (mktemp -d 2>/dev/null; or mktemp -d -t dotsync_probe)
        set -l idx 1

        for h in $peer_routes
            set -l h_info (command ssh -G "$h" 2>/dev/null | awk '/^hostname / {hn=$2} /^port / {pt=$2} END {print hn; print pt}')
            set -l hn $h_info[1]
            set -l pt $h_info[2]
            test -z "$pt"; and set pt 22

            fish -c "
                if command -q nc
                    if nc -z -w 1 '$hn' '$pt' >/dev/null 2>&1
                        touch '$tmp_dir/succ_$idx'
                    end
                else
                    if command ssh -o ConnectTimeout=1 -o BatchMode=yes -o ClearAllForwardings=yes -q '$h' \"exit 0\" >/dev/null 2>&1
                        touch '$tmp_dir/succ_$idx'
                    end
                end
            " &
            set idx (math $idx + 1)
        end

        for t in (seq 1 20)
            if test -f "$tmp_dir/succ_1"
                break
            end
            if test (count (jobs -p)) -eq 0
                break
            end
            sleep 0.05
        end

        for i in (seq 1 (count $peer_routes))
            if test -f "$tmp_dir/succ_$i"
                set reachable_host $peer_routes[$i]
                break
            end
        end

        kill (jobs -p) 2>/dev/null
        rm -rf "$tmp_dir"

        if test -z "$reachable_host"
            echo -e "  \033[1;31m✕ Unreachable:\033[0m All routes for '$peer' ($peer_routes) failed to respond."
            continue
        end

        echo -e "  \033[1;32m✓ Connected via:\033[0m \033[1;32m$reachable_host\033[0m"

        set -l remote_name "peer-$peer"
        set -l remote_url "$reachable_host:$peer_repo"

        # Configure or update git remote dynamically
        set -l existing_url (git -C "$repo_dir" remote get-url "$remote_name" 2>/dev/null)
        if test -z "$existing_url"
            git -C "$repo_dir" remote add "$remote_name" "$remote_url"
        else if test "$existing_url" != "$remote_url"
            git -C "$repo_dir" remote set-url "$remote_name" "$remote_url"
        end

        set -l current_branch (git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null; or echo "main")

        if test $is_dryrun -eq 1
            echo -e "  \033[1;33m[Dry-Run]\033[0m Fetching metadata from $remote_name ($remote_url)..."
            git -C "$repo_dir" fetch "$remote_name" "$current_branch" 2>&1 | string replace -r '^' '    '
            set -l behind (git -C "$repo_dir" rev-list --count "HEAD..$remote_name/$current_branch" 2>/dev/null; or echo 0)
            set -l ahead (git -C "$repo_dir" rev-list --count "$remote_name/$current_branch..HEAD" 2>/dev/null; or echo 0)
            echo -e "  📊 Commits Status: \033[1;36mAhead: $ahead\033[0m | \033[1;35mBehind: $behind\033[0m"
            set synced_count (math $synced_count + 1)
            continue
        end

        # Live Sync / Push Engine
        if test $is_force -eq 1
            echo -e "  🚀 \033[1;33mForce-pushing local branch '$current_branch' to $peer...\033[0m"
            if git -C "$repo_dir" push --force "$remote_name" "$current_branch"
                echo -e "  \033[1;32m✓ Successfully force-pushed to $peer.\033[0m"
                set synced_count (math $synced_count + 1)
            else
                echo -e "  \033[1;31m✕ Failed to force-push to $peer.\033[0m"
            end
            continue
        end

        # Step 1: Fetch latest commits from remote peer
        echo "  📥 Fetching latest commits from $peer..."
        if not git -C "$repo_dir" fetch "$remote_name" "$current_branch"
            echo -e "  \033[1;31m✕ Failed to fetch from $peer.\033[0m"
            continue
        end

        set -l remote_ref "$remote_name/$current_branch"
        set -l behind (git -C "$repo_dir" rev-list --count "HEAD..$remote_ref" 2>/dev/null; or echo 0)
        set -l ahead (git -C "$repo_dir" rev-list --count "$remote_ref..HEAD" 2>/dev/null; or echo 0)

        # Step 2: Conflict Check (Dry merge-tree without touching index or working tree)
        if test "$behind" -gt 0 -a "$ahead" -gt 0
            if not git -C "$repo_dir" merge-tree --write-tree HEAD "$remote_ref" >/dev/null 2>&1
                echo -e "  \033[1;31m❌ Conflict detected with $peer!\033[0m Local and remote have diverged and cannot merge cleanly."
                echo -e "  \033[1;33m💡 Aborted without making any changes to working tree.\033[0m"
                echo -e "  \033[0;90m   (To overwrite $peer with your local version, use: dotsync $peer --force)\033[0m"
                return 1
            end
        end

        # Step 3: If behind, perform clean merge
        if test "$behind" -gt 0
            echo -e "  🔀 Merging $behind incoming commit(s) from $peer..."
            if not git -C "$repo_dir" merge --no-edit "$remote_ref" -m "merge: sync with $peer"
                echo -e "  \033[1;31m❌ Merge conflict detected during merge! Aborting...\033[0m"
                git -C "$repo_dir" merge --abort 2>/dev/null
                return 1
            end
            set new_commits_pulled 1
        else
            echo "  ✓ Already up-to-date with commits from $peer."
        end

        # Step 4: Push to peer (if ahead or merged)
        set -l final_ahead (git -C "$repo_dir" rev-list --count "$remote_ref..HEAD" 2>/dev/null; or echo 0)
        if test "$final_ahead" -gt 0
            echo -e "  📤 Pushing $final_ahead commit(s) to $peer..."
            if git -C "$repo_dir" push "$remote_name" "$current_branch"
                echo -e "  \033[1;32m✓ Successfully synced to $peer.\033[0m"
            else
                echo -e "  \033[1;31m✕ Failed to push to $peer.\033[0m"
                return 1
            end
        else
            echo -e "  \033[1;32m✓ In sync with $peer (no push needed).\033[0m"
        end

        set synced_count (math $synced_count + 1)
    end

    echo -e "\n\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "🏁 \033[1;32mDotsync finished:\033[0m Synced with $synced_count/$total_peers peer(s)."

    if test $new_commits_pulled -eq 1
        echo -e "\033[1;33m💡 New commits pulled!\033[0m Run '\033[1;36mdotsync refresh\033[0m' or '\033[1;32mdotsync apply\033[0m' to update your live system."
    end
end

# Auto-completion for dotsync (dynamic from devices.toml + subcommands)
complete -c dotsync -f -a '(
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
peers = [k for k, v in data.get(\"ssh\", {}).items() if v.get(\"sync\") is True]
print(\"\n\".join(peers))
" 2>/dev/null
    end
    echo dry-run
    echo apply
    echo install
    echo refresh
    echo --force
    echo -f
    echo --help
)'
