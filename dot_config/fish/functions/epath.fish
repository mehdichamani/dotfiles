function epath --description 'Edit fish_user_paths in default editor or VS Code'
    argparse 'v/vscode' 'h/help' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: epath [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -v, --vscode    Open in VS Code (code --wait)"
        echo "  -h, --help      Show this help message"
        echo ""
        echo "Without options, opens in your default editor (\$EDITOR, \$VISUAL, or nvim/nano/vi)."
        return 0
    end

    set -l temp (mktemp)
    printf '%s\n' $fish_user_paths > $temp

    if set -q _flag_vscode
        if command -q code
            code --wait $temp
        else
            echo "Error: VS Code ('code') was not found in PATH."
            rm -f $temp
            return 1
        end
    else
        set -l editor_cmd
        if set -q EDITOR
            set editor_cmd (string split ' ' -- $EDITOR)
        else if set -q VISUAL
            set editor_cmd (string split ' ' -- $VISUAL)
        else if command -q nvim
            set editor_cmd nvim
        else if command -q nano
            set editor_cmd nano
        else if command -q vi
            set editor_cmd vi
        end

        if test -z "$editor_cmd"
            echo "No default editor found. Set \$EDITOR or use 'epath --vscode'."
            rm -f $temp
            return 1
        end

        $editor_cmd $temp
    end

    set -l new_paths (string match -r '\S+' (string trim < $temp))
    set -U fish_user_paths $new_paths
    rm -f $temp
    echo "fish_user_paths updated. New PATH:"
    echo $PATH | tr ' ' '\n'
end
