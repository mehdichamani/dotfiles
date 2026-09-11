function shelp --description "Display cheatsheet of custom functions and shortcuts"
    set -l filter $argv[1]

    echo ""
    echo -e "\033[1;35m🛠️  Custom Shell Functions & Shortcuts\033[0m"
    if test -n "$filter"
        echo -e "\033[0;90mFiltering by: '$filter'\033[0m"
    end
    echo -e "\033[0;90m────────────────────────────────────────────────────────────\033[0m"

    # Search paths for custom fish functions
    set -l func_dirs ~/.config/fish/functions ~/.local/share/chezmoi/dot_config/fish/functions
    set -l seen_funcs

    for dir in $func_dirs
        test -d $dir; or continue
        for file in $dir/*.fish
            test -f $file; or continue
            set -l fname (path change-extension '' (path basename $file))
            
            # Avoid duplicates if found in multiple paths
            if contains $fname $seen_funcs
                continue
            end
            set -a seen_funcs $fname

            # Extract --description from function definition
            set -l desc (sed -n -E 's/^[[:space:]]*function[[:space:]]+'"$fname"'.*-d(escription)?[[:space:]]+(["\'].*["\']).*/\2/p' $file | head -n 1 | string trim -c "'\"")

            # Fallback to first line comment if no -d is present
            if test -z "$desc"
                set desc (sed -n -E 's/^[[:space:]]*#[[:space:]]*(.*)/\1/p' $file | head -n 1)
            end

            # Apply filter if provided
            if test -n "$filter"
                if not string match -qi "*$filter*" -- "$fname $desc"
                    continue
                end
            end

            printf "  \033[1;36m%-14s\033[0m %s\n" "$fname" "$desc"
        end
    end


    echo -e "\033[0;90m────────────────────────────────────────────────────────────\033[0m"
    echo -e "\033[0;90mTip: Run 'shelp <search>' to filter (e.g., shelp git, shelp proxy)\033[0m\n"
end
