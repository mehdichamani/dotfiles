function gcb --description 'Interactive cleanup of non-default git branches'
    # Check if inside a git repository
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo -e "\033[1;31m❌ Error: Not a git repository.\033[0m"
        return 1
    end

    # Fetch latest remote references and prune deleted remotes
    git fetch --prune

    # Get default branch (e.g., main or master)
    set -l default_branch (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | string replace 'refs/remotes/origin/' '')
    if test -z "$default_branch"
        # Fallback detection if origin/HEAD isn't set
        if git show-ref --verify --quiet refs/heads/main
            set default_branch "main"
        else if git show-ref --verify --quiet refs/heads/master
            set default_branch "master"
        end
    end

    # Get current branch
    set -l current_branch (git branch --show-current)

    # Collect branches to delete (exclude current and default)
    set -l local_to_delete
    set -l remote_to_delete

    for b in (git branch --format='%(refname:short)')
        if test "$b" != "$default_branch" -a "$b" != "$current_branch"
            set -a local_to_delete $b
            if git rev-parse --verify "origin/$b" >/dev/null 2>&1
                set -a remote_to_delete $b
            end
        end
    end

    if test (count $local_to_delete) -eq 0
        echo -e "\033[0;32m✅ No extra branches to delete. (Keeping: '$default_branch' and '$current_branch')\033[0m"
        return 0
    end

    # Display preview
    echo ""
    echo -e "\033[1;36m🌿 Git Branch Cleaner\033[0m"
    echo -e "\033[0;90m────────────────────────────────────────────────────────────\033[0m"
    echo -e "Default branch : \033[1;36m$default_branch\033[0m"
    echo -e "Current branch : \033[1;36m$current_branch\033[0m"
    echo ""
    echo -e "\033[1;33mLocal branches to be DELETED:\033[0m"
    for b in $local_to_delete
        echo "  - $b"
    end

    if test (count $remote_to_delete) -gt 0
        echo ""
        echo -e "\033[1;31mRemote branches (origin) to be DELETED:\033[0m"
        for b in $remote_to_delete
            echo "  - origin/$b"
        end
    end

    echo ""
    read -P "Are you sure you want to delete these branches locally and remotely? [y/N] " -l confirm
    if string match -ri '^[yY]$' -- "$confirm" >/dev/null
        echo ""
        echo -e "\033[1;33mDeleting local branches...\033[0m"
        for b in $local_to_delete
            git branch -D $b
        end

        if test (count $remote_to_delete) -gt 0
            echo ""
            echo -e "\033[1;31mDeleting remote branches...\033[0m"
            for b in $remote_to_delete
                git push origin --delete $b
            end
        end
        echo ""
        echo -e "\033[1;32m✅ Cleaned up successfully!\033[0m"
    else
        echo -e "\033[0;90mOperation cancelled.\033[0m"
    end
end