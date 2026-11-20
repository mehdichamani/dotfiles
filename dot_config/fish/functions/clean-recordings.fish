function clean-recordings --description 'Clean old call recordings from /sdcard/Recordings/Call'
    set -l days 180
    set -l dry_run 0
    set -l target_dir "/sdcard/Recordings/Call"

    # Argument parsing
    set -l i 1
    while test $i -le (count $argv)
        switch $argv[$i]
            case -n --dry-run
                set dry_run 1
            case -d --days
                set i (math $i + 1)
                set days $argv[$i]
            case -h --help
                echo -e "\033[1;35m== Clean Call Recordings ==\033[0m"
                echo -e "\033[1;33mUsage:\033[0m clean-recordings [options]"
                echo ""
                echo "Options:"
                echo "  -d, --days <N>   Keep recordings newer than N days (default: 180 days / 6 months)"
                echo "  -n, --dry-run    Preview files and calculated size without deleting"
                echo "  -h, --help       Show this help message"
                return 0
            case '*'
                if string match -qr '^[0-9]+$' -- $argv[$i]
                    set days $argv[$i]
                else
                    echo -e "\033[1;31m❌ Unknown option or argument:\033[0m $argv[$i]"
                    echo "Run 'clean-recordings --help' for details."
                    return 1
                end
        end
        set i (math $i + 1)
    end

    if not test -d "$target_dir"
        echo -e "\033[1;31m❌ Directory not found:\033[0m $target_dir"
        return 1
    end

    set -l count (find "$target_dir" -maxdepth 1 -type f -mtime +$days | wc -l)
    if test "$count" -eq 0
        echo -e "\033[1;32m✔ No recordings found older than $days days.\033[0m"
        return 0
    end

    set -l total_size (find "$target_dir" -maxdepth 1 -type f -mtime +$days -exec du -ch {} + | tail -n 1 | awk '{print $1}')

    if test "$dry_run" -eq 1
        echo -e "\033[1;34mℹ [Dry-run]\033[0m Found \033[1;33m$count\033[0m files (~$total_size) older than $days days."
        echo "Run without -n/--dry-run to delete them."
        return 0
    end

    read -l -P "Found $count recordings (~$total_size) older than $days days. Delete? [y/N] " confirm
    if test "$confirm" = "y" -o "$confirm" = "Y"
        find "$target_dir" -maxdepth 1 -type f -mtime +$days -delete
        echo -e "\033[1;32m✔ Successfully cleaned $count recordings (~$total_size freed).\033[0m"
    else
        echo -e "\033[1;33mAborted.\033[0m No files were deleted."
    end
end

# Completions
complete -c clean-recordings -f
complete -c clean-recordings -s d -l days -d "Keep recordings newer than N days (default: 180)"
complete -c clean-recordings -s n -l dry-run -d "Preview files to delete without deleting"
complete -c clean-recordings -s h -l help -d "Show help message"
