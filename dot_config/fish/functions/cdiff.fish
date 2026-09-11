function cdiff --description "Visual live-vs-repo side-by-side diff editor for chezmoi"
    argparse -n cdiff 'h/help' 'r/reverse' 'e/editor=' -- $argv
    or return 1

    # Text formatting & colors (safe across tty and pipes)
    set -l bold ""
    set -l cyan ""
    set -l yellow ""
    set -l green ""
    set -l white ""
    set -l reset ""
    if isatty stdout
        set bold (set_color --bold)
        set cyan (set_color cyan)
        set yellow (set_color yellow)
        set green (set_color green)
        set white (set_color white)
        set reset (set_color normal)
    end

    # Help documentation
    if set -q _flag_help
        echo "$bold""Usage:""$reset cdiff [options] [target]"
        echo
        echo "Visual live-vs-repo side-by-side diff editor for chezmoi managed files."
        echo "Opens the actual live file (system) and source file (repo) side-by-side."
        echo
        echo "$bold""Arguments:""$reset"
        echo "  $yellow""target$reset                File path or name of the chezmoi managed file."
        echo "                        If omitted, an interactive picker (fzf) of modified files is shown."
        echo
        echo "$bold""Options:""$reset"
        echo "  $cyan""-e, --editor <cmd>$reset    Diff editor to use (default: nvim)"
        echo "  $cyan""-r, --reverse$reset         Reverse diff sides (repo on left, live system on right)"
        echo "  $cyan""-h, --help$reset            Show this help message and exit"
        echo
        echo "$bold""Examples:""$reset"
        echo "  cdiff"
        echo "  cdiff settings.json"
        echo "  cdiff ~/.config/fish/config.fish"
        echo "  cdiff -r"
        echo "  cdiff -e code"
        return 0
    end

    # 1. Determine editor command (strictly nvim by default, or custom with --editor)
    set -l selected_editor "nvim"
    if set -q _flag_editor
        set -l editor_binary (string split ' ' -- $_flag_editor)[1]
        if not type -q "$editor_binary"
            echo "Error: Editor binary '$editor_binary' was not found in PATH." >&2
            return 1
        end
        set selected_editor $_flag_editor
    end

    # 2. If no target specified, inspect chezmoi status
    set -l target $argv[1]
    if test -z "$target"
        set -l status_lines (chezmoi status)
        if test -z "$status_lines"
            echo "$green""✓ No differences between live system and chezmoi repo.""$reset"
            return 0
        end

        set -l modified (printf '%s\n' $status_lines | string replace -r '^\s*\S+\s+' '')
        set -l count (count $modified)

        if test $count -eq 0
            echo "$green""✓ No modified files found.""$reset"
            return 0
        else if test $count -eq 1
            set target $modified[1]
            echo "$cyan""Opening: $target""$reset"
        else if type -q fzf
            set target (printf '%s\n' $modified | fzf --prompt="Select file to diff (chezmoi) > " --height=40% --reverse)
            test -z "$target"; and return 0
        else
            echo "$yellow""Multiple modified files found:""$reset"
            for file in $modified
                echo "  - $file"
            end
            echo
            echo "$cyan""Usage: cdiff [options] [target]""$reset"
            return 1
        end
    end

    # 3. Resolve destination (live system) and source (repo) paths
    set -l dest (chezmoi target-path "$target" 2>/dev/null)
    set -l src (chezmoi source-path "$target" 2>/dev/null)

    # If src not found, try relative to HOME (e.g. from chezmoi status: .config/...)
    if test -z "$src"
        set src (chezmoi source-path "$HOME/$target" 2>/dev/null)
        if test -n "$src" -a -z "$dest"
            set dest "$HOME/$target"
        end
    end

    # If dest not found, but src was found, resolve target from src
    if test -z "$dest" -a -n "$src"
        set dest (chezmoi target-path "$src" 2>/dev/null)
    end

    # If src not found, but dest was found, resolve source from dest
    if test -z "$src" -a -n "$dest"
        set src (chezmoi source-path "$dest" 2>/dev/null)
    end

    # Fallback for local files in current working directory
    if test -z "$src" -a -e "$target"
        set -l abs_target (realpath "$target" 2>/dev/null)
        set src (chezmoi source-path "$abs_target" 2>/dev/null)
        test -z "$dest"; and set dest (chezmoi target-path "$abs_target" 2>/dev/null)
    end

    if test -z "$src" -o ! -e "$src"
        echo "Error: Could not resolve chezmoi source path for '$target'. Is this file managed by chezmoi?" >&2
        return 1
    end

    echo "$white""Live (System): $yellow""$dest$reset"
    echo "$white""Repo (Source): $cyan""$src$reset"

    # 4. Open in editor (default: Left=Live, Right=Repo; Reverse: Left=Repo, Right=Live)
    set -l left "$dest"
    set -l right "$src"
    if set -q _flag_reverse
        set left "$src"
        set right "$dest"
    end

    set -l editor_parts (string split -n ' ' -- $selected_editor)
    set -l editor_bin $editor_parts[1]
    set -l editor_args
    if test (count $editor_parts) -gt 1
        set editor_args $editor_parts[2..-1]
    end

    switch $editor_bin
        case code agy cursor
            $editor_bin $editor_args --wait --diff "$left" "$right"
        case nvim vim
            $editor_bin $editor_args -d "$left" "$right"
        case '*'
            $editor_bin $editor_args "$left" "$right"
    end
end
