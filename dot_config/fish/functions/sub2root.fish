function sub2root --description 'Move all files to current dir, skip duplicates, and remove empty subfolders'
    set -l files (find . -mindepth 2 -type f)
    set -l count (count $files)

    if test $count -eq 0
        echo -e "\033[0;32m✅ No files found in subdirectories.\033[0m"
        return
    end

    echo ""
    echo -e "\033[1;36m📁 Flatten Subdirectories to Root: \033[1;33m"(pwd)"\033[0m"
    echo -e "\033[0;90m────────────────────────────────────────────────────────────\033[0m"
    echo -e "Found \033[1;32m$count\033[0m file(s) to move into the current directory."
    echo -e "\033[0;90mNote: Files with duplicate names will be safely skipped.\033[0m"
    read -l -P "Press Enter to continue, or Ctrl+C to cancel: " confirm

    # Move files
    set -l moved 0
    for file in $files
        set -l fname (path basename $file)
        if not test -e "./$fname"
            echo -e "  \033[0;36m📦 Moving:\033[0m $file"
            mv $file .
            set moved (math $moved + 1)
        else
            echo -e "  \033[0;33m⚠️ Skipped (already exists):\033[0m $fname"
        end
    end
    
    # Remove empty subdirectories
    find . -mindepth 1 -type d -empty -delete
    
    echo ""
    echo -e "\033[1;32m✅ Completed! $moved file(s) moved and empty folders removed.\033[0m"
end