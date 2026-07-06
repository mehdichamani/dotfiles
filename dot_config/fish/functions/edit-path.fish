function edit-path --description 'Edit fish_user_paths in your preferred editor (VS Code or Neovim)'
    # Use VS Code if available and waiting for save, otherwise fall back to $EDITOR
    if command -q code
        set -l temp (mktemp)
        printf '%s\n' $fish_user_paths > $temp
        code --wait $temp
        set -U fish_user_paths (string trim < $temp)
        rm $temp
        echo "fish_user_paths updated. New PATH:"
        echo $PATH | tr ' ' '\n'
    else if set -q EDITOR
        set -l temp (mktemp)
        printf '%s\n' $fish_user_paths > $temp
        $EDITOR $temp
        set -U fish_user_paths (string trim < $temp)
        rm $temp
        echo "fish_user_paths updated."
    else
        echo "No editor found. Set \$EDITOR or install 'code'."
    end
end