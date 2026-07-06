function sub2root --description 'Move all files to current dir, skip duplicates, and remove empty subfolders'
    set -l files (find . -mindepth 2 -type f)
    set -l count (count $files)

    if test $count -eq 0
        echo "No files found in subdirectories."
        return
    end

    echo "Found $count files to move to the current directory."
    echo "Files with duplicate names will be skipped."
    read -l -P "Press Enter to continue or Ctrl+C to cancel: " confirm

    # Move files
    for file in $files
        mv -n $file .
    end
    
    # Remove empty subdirectories
    # -mindepth 2 ensures we don't try to remove the current directory
    # -type d looks for directories, -empty finds only empty ones
    find . -mindepth 1 -type d -empty -delete
    
    echo "Operation completed. Empty subdirectories have been removed."
end