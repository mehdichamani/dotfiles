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
peers = [k for k, v in data.get('devices', {}).items() if v.get('sync') is True]
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
        echo ""
        echo "Behavior:"
        echo "  • Ahead:  Automatically pushes to peer safely."
        echo "  • Behind: Automatically fast-forward pulls from peer safely."
        echo "  • Diverged: Prompts interactively for Rebase & Push, Push Force, Pull Force, or Abort."
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

        set -l peer_shell (python3 -c "
import sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
with open('$devices_toml', 'rb') as f:
    data = tomllib.load(f)
print(data.get('ssh', {}).get('$peer', {}).get('shell', 'bash'))
" 2>/dev/null)
        if test -z "$peer_shell"
            set peer_shell "bash"
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
            for i in (seq 1 (count $peer_routes))
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

        set -l remote_name "$peer"
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

        # Live Push Engine (No merge, no conflict resolution: only push or push --force)
        # Configure peer git repo to accept push to checked-out branch (receive.denyCurrentBranch=updateInstead)
        if test "$peer_shell" = "pwsh"
            ssh -o ConnectTimeout=2 -o BatchMode=yes "$reachable_host" "pwsh -NoProfile -Command \"git -C '$peer_repo' config receive.denyCurrentBranch updateInstead\"" >/dev/null 2>&1
        else
            ssh -o ConnectTimeout=2 -o BatchMode=yes "$reachable_host" "r='$peer_repo'; r=\"\${r/#\\~/\$HOME}\"; git -C \"\$r\" config receive.denyCurrentBranch updateInstead" >/dev/null 2>&1
        end

        # 1. Fetch latest metadata from peer
        echo "  📥 Fetching latest metadata from $peer..."
        set -l fetch_out (git -C "$repo_dir" fetch "$remote_name" "+refs/heads/$current_branch:refs/remotes/$remote_name/$current_branch" 2>&1)
        if test $status -ne 0
            if test -n "$fetch_out"
                for line in $fetch_out
                    echo "    $line"
                end
            end
            echo -e "  \033[1;31m✕ Failed to fetch from $peer.\033[0m"
            continue
        end

        set -l remote_ref "$remote_name/$current_branch"
        set -l behind (git -C "$repo_dir" rev-list --count "HEAD..$remote_ref" 2>/dev/null; or echo 0)
        set -l ahead (git -C "$repo_dir" rev-list --count "$remote_ref..HEAD" 2>/dev/null; or echo 0)

        # 2. Case A: Both in sync
        if test "$ahead" -eq 0 -a "$behind" -eq 0
            echo -e "  \033[1;32m✓ In sync with $peer (no changes).\033[0m"
            set synced_count (math $synced_count + 1)
            continue
        end

        # 3. Case B: Local is strictly ahead -> Safe Push
        if test "$ahead" -gt 0 -a "$behind" -eq 0
            echo -e "  📤 Local is ahead by $ahead commit(s). Pushing to $peer..."
            if git -C "$repo_dir" push "$remote_name" "$current_branch"
                echo -e "  \033[1;32m✓ Successfully pushed to $peer.\033[0m"
                set synced_count (math $synced_count + 1)
            else
                echo -e "  \033[1;31m✕ Failed to push to $peer.\033[0m"
                return 1
            end
            continue
        end

        # 4. Case C: Local is strictly behind -> Safe Pull (Fast-Forward Only)
        if test "$behind" -gt 0 -a "$ahead" -eq 0
            echo -e "  📥 Peer $peer has $behind new commit(s). Fast-forward pulling..."
            if git -C "$repo_dir" pull --ff-only "$remote_name" "$current_branch"
                echo -e "  \033[1;32m✓ Successfully pulled from $peer (fast-forwarded).\033[0m"
                set synced_count (math $synced_count + 1)
            else
                echo -e "  \033[1;31m✕ Failed to fast-forward pull from $peer.\033[0m"
                return 1
            end
            continue
        end

        # 5. Case D: History has diverged (ahead > 0 and behind > 0) -> Interactive Prompt
        if test "$ahead" -gt 0 -a "$behind" -gt 0
            echo -e "\n  \033[1;33m⚠️ Diverged history detected between local and $peer!\033[0m"
            echo -e "  \033[1;36m• Local has $ahead unique commit(s):\033[0m"
            git -C "$repo_dir" log --oneline --no-merges -n 3 "$remote_ref..HEAD" | sed 's/^/      /'
            echo -e "  \033[1;35m• Peer $peer has $behind unique commit(s):\033[0m"
            git -C "$repo_dir" log --oneline --no-merges -n 3 "HEAD..$remote_ref" | sed 's/^/      /'
            echo ""
            echo -e "  \033[1;37mHow would you like to resolve this divergence?\033[0m"
            echo -e "    \033[1;32m[1]\033[0m Rebase & Push \033[0;90m(Rebase local on $peer and push back to $peer)\033[0m"
            echo -e "    \033[1;33m[2]\033[0m Push Force   \033[0;90m(Overwrite $peer with local state)\033[0m"
            echo -e "    \033[1;36m[3]\033[0m Pull Force   \033[0;90m(Overwrite local with $peer state)\033[0m"
            echo -e "    \033[1;31m[4]\033[0m Cancel/Abort \033[0;90m(Default - do nothing)\033[0m"
            echo ""

            read -l -P "  Select action [1/2/3/4] (default 4): " user_choice

            switch "$user_choice"
                case 1 "rebase" "rb" "r"
                    echo -e "  🔄 \033[1;32mChecking if rebase can apply cleanly without conflicts...\033[0m"
                    set -l mb (git -C "$repo_dir" merge-base HEAD "$remote_ref" 2>/dev/null)
                    set -l can_rebase 0
                    if test -n "$mb"
                        # Pre-flight conflict check via merge-tree
                        git -C "$repo_dir" merge-tree --write-tree HEAD "$remote_ref" >/dev/null 2>&1
                        if test $status -eq 0
                            set can_rebase 1
                        end
                    end

                    if test $can_rebase -eq 0
                        echo -e "  \033[1;31m⚠️ Rebase conflict detected!\033[0m Rebase cannot be applied cleanly without manual resolution."
                        echo -e "  \033[0;90mResolve manually with: git -C '$repo_dir' rebase $remote_ref\033[0m"
                        return 1
                    end

                    echo -e "  🔄 \033[1;32mRebasing local branch '$current_branch' onto $remote_ref...\033[0m"
                    if git -C "$repo_dir" rebase "$remote_ref"
                        echo -e "  \033[1;32m✓ Local branch successfully rebased onto $peer.\033[0m"
                        echo -e "  📤 Pushing rebased commits to $peer..."
                        if git -C "$repo_dir" push "$remote_name" "$current_branch"
                            echo -e "  \033[1;32m✓ Successfully synced & pushed to $peer.\033[0m"
                            set synced_count (math $synced_count + 1)
                        else
                            echo -e "  \033[1;31m✕ Failed to push rebased branch to $peer.\033[0m"
                            return 1
                        end
                    else
                        echo -e "  \033[1;31m✕ Git rebase failed.\033[0m Aborting rebase to preserve state..."
                        git -C "$repo_dir" rebase --abort >/dev/null 2>&1
                        return 1
                    end

                case 2 "push" "push-force" "pf"
                    echo -e "  🚀 \033[1;33mForce-pushing local branch '$current_branch' to $peer...\033[0m"
                    if git -C "$repo_dir" push --force "$remote_name" "$current_branch"
                        if test "$peer_shell" = "pwsh"
                            ssh -o ConnectTimeout=2 -o BatchMode=yes "$reachable_host" "pwsh -NoProfile -Command \"git -C '$peer_repo' reset --hard HEAD\"" >/dev/null 2>&1
                        else
                            ssh -o ConnectTimeout=2 -o BatchMode=yes "$reachable_host" "r='$peer_repo'; r=\"\${r/#\\~/\$HOME}\"; git -C \"\$r\" reset --hard HEAD" >/dev/null 2>&1
                        end
                        echo -e "  \033[1;32m✓ Successfully force-pushed to $peer (mirrored).\033[0m"
                        set synced_count (math $synced_count + 1)
                    else
                        echo -e "  \033[1;31m✕ Failed to force-push to $peer.\033[0m"
                        return 1
                    end

                case 3 "pull" "pull-force"
                    echo -e "  📥 \033[1;36mForce-pulling $peer state into local branch '$current_branch'...\033[0m"
                    if git -C "$repo_dir" reset --hard "$remote_ref"
                        echo -e "  \033[1;32m✓ Local repository successfully reset to match $peer.\033[0m"
                        set synced_count (math $synced_count + 1)
                    else
                        echo -e "  \033[1;31m✕ Failed to reset local repository to $remote_ref.\033[0m"
                        return 1
                    end

                case '*'
                    echo -e "  \033[1;33m⏸️ Aborted by user. No changes made.\033[0m"
                    return 0
            end
        end
    end

    echo -e "\n\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "🏁 \033[1;32mDotsync finished:\033[0m Synced with $synced_count/$total_peers peer(s)."
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
peers = [k for k, v in data.get(\"devices\", {}).items() if v.get(\"sync\") is True]
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
