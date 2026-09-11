function sc --description "Control and mirror Android device via scrcpy"
    if not type -q scrcpy
        echo -e "\033[1;31m✘ scrcpy is not installed or not in PATH.\033[0m" >&2
        return 1
    end

    set -l mode "default"
    set -l foreground 0
    set -l extra_args

    set -l i 1
    set -l total (count $argv)

    while test $i -le $total
        set -l arg $argv[$i]
        switch $arg
            case -h --help help
                echo -e "\033[1;36m📱 sc\033[0m - Control and mirror Android device via scrcpy"
                echo ""
                echo -e "\033[1;33mUsage:\033[0m"
                echo "  sc                      Mirror device (screen on, background)"
                echo "  sc --off                Mirror device with physical screen turned off"
                echo "  sc --dex                Open virtual 1080p desktop display"
                echo "  sc --apps               Select and launch installed app via fzf"
                echo ""
                echo -e "\033[1;33mOptions:\033[0m"
                echo "  -f, --stay, --foreground   Do not detach to background"
                echo "  -h, --help                 Show this help message"
                return 0

            case -f --stay --foreground
                set foreground 1

            case --off -off off
                set mode "off"

            case --dex -dex dex
                set mode "dex"

            case --apps -apps apps
                set mode "apps"

            case '*'
                set -a extra_args $arg
        end
        set i (math $i + 1)
    end

    switch $mode
        case apps
            if not type -q fzf
                # Fallback to plain listing if fzf is not installed
                scrcpy --list-apps $extra_args
                return $status
            end

            echo -e "\033[0;90mFetching installed applications from device...\033[0m"
            set -l raw_apps (scrcpy --list-apps 2>/dev/null | string match -r '^[[:space:]]*[\*\-][[:space:]]+.*')
            if test (count $raw_apps) -eq 0
                echo -e "\033[1;31m✘ Failed to retrieve applications or no device connected.\033[0m" >&2
                return 1
            end

            set -l selected (printf "%s\n" $raw_apps | fzf --height=40% --reverse --prompt="📱 Select App > " --header="Choose an app to launch with scrcpy")
            if test -z "$selected"
                return 0
            end

            # Extract package name (last word) and clean display name
            set -l pkg (string match -r '\S+$' -- "$selected")
            if test -z "$pkg"
                echo -e "\033[1;31m✘ Could not determine package name.\033[0m" >&2
                return 1
            end

            # Human-readable title from app line
            set -l title (string trim (string replace -r '^[[:space:]]*[\*\-][[:space:]]+' '' -- "$selected" | string replace -r '\s+\S+$' ''))
            test -z "$title"; and set title "$pkg"

            echo -e "\033[1;32m🚀 Launching $title ($pkg)...\033[0m"
            _sc_run $foreground --new-display --start-app=$pkg --window-title="$title" $extra_args

        case off
            _sc_run $foreground --turn-screen-off $extra_args

        case dex
            _sc_run $foreground --new-display=1920x1080/284 --turn-screen-off $extra_args

        case default
            _sc_run $foreground $extra_args
    end
end

function _sc_run -a foreground
    set -e argv[1]
    if test "$foreground" -eq 1
        scrcpy $argv
    else
        nohup scrcpy $argv >/dev/null 2>&1 &
        disown
        echo -e "\033[1;32m✔ scrcpy started in background.\033[0m"
    end
end

# Auto-completions for 'sc'
complete -c sc -f
complete -c sc -l off -d "Mirror with device screen turned off"
complete -c sc -l dex -d "Virtual 1080p desktop display"
complete -c sc -l apps -d "Select and launch app via fzf"
complete -c sc -s f -l stay -l foreground -d "Run in foreground (keep terminal attached)"
complete -c sc -s h -l help -d "Show help and usage"
