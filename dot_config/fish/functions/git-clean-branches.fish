function git-clean-branches
    # Check if inside a git repository
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "Error: Not a git repository."
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
        echo "No extra branches to delete. (Keeping: '$default_branch' and '$current_branch')"
        return 0
    end

    # Display preview
    echo "Default branch : $default_branch"
    echo "Current branch : $current_branch"
    echo ""
    echo "Local branches to be DELETED:"
    for b in $local_to_delete
        echo "  - $b"
    end

    if test (count $remote_to_delete) -gt 0
        echo ""
        echo "Remote branches (origin) to be DELETED:"
        for b in $remote_to_delete
            echo "  - origin/$b"
        end
    end

    echo ""
    read -P "Are you sure you want to delete these branches locally and remotely? [y/N] " -l confirm
    if string match -ri '^[yY]$' -- "$confirm" >/dev/null
        echo ""
        echo "Deleting local branches..."
        for b in $local_to_delete
            git branch -D $b
        end

        if test (count $remote_to_delete) -gt 0
            echo ""
            echo "Deleting remote branches..."
            for b in $remote_to_delete
                git push origin --delete $b
            end
        end
        echo ""
        echo "Cleaned up successfully!"
    else
        echo "Operation cancelled."
    end
end