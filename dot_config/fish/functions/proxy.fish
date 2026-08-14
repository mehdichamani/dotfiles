function proxy --description "Manage shell proxy configuration"
    # Helper to print usage instructions
    function _proxy_help
        set_color cyan; echo "Usage:"; set_color normal
        echo "  proxy [URL|PORT]    Set proxy to specific address/port"
        echo "  proxy off           Clear proxy configuration"
        echo "  proxy status        Show current proxy status"
        echo "  proxy --help, -h    Show this help message"
        echo "  proxy               Interactive menu with default presets"
        echo ""
        set_color cyan; echo "Examples:"; set_color normal
        echo "  proxy 3067                  -> http://localhost:3067"
        echo "  proxy :3068                 -> http://localhost:3068"
        echo "  proxy 192.168.1.10:8080     -> http://192.168.1.10:8080"
        echo "  proxy socks5://127.0.0.1:1080"
        echo "  proxy off"
    end

    # Helper to show proxy status
    function _proxy_status
        if set -q http_proxy; or set -q HTTP_PROXY
            set_color green; echo "● Proxy ON"; set_color normal
            echo "  http_proxy  : "(set -q http_proxy; and echo "$http_proxy"; or echo "not set")
            echo "  https_proxy : "(set -q https_proxy; and echo "$https_proxy"; or echo "not set")
            echo "  all_proxy   : "(set -q all_proxy; and echo "$all_proxy"; or echo "not set")
        else
            set_color yellow; echo "○ Proxy OFF"; set_color normal
        end
    end

    # Location for temporary proxy file
    set -l proxy_file (test -n "$XDG_RUNTIME_DIR" -a -d "$XDG_RUNTIME_DIR"; and echo "$XDG_RUNTIME_DIR/current_proxy"; or echo "/tmp/current_proxy")

    # Helper to turn proxy off
    function _proxy_off --inherit-variable proxy_file
        set -e -U http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
        set -e -g http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
        rm -f "$proxy_file"
        set_color yellow; echo "○ Proxy OFF"; set_color normal
    end

    # Helper to set proxy given a parsed full target
    function _proxy_set --argument-names target --inherit-variable proxy_file
        if test -z "$target"
            return 1
        end

        set -Ux http_proxy "$target"
        set -Ux https_proxy "$target"
        set -Ux HTTP_PROXY "$target"
        set -Ux HTTPS_PROXY "$target"
        set -Ux all_proxy "$target"
        set -Ux ALL_PROXY "$target"

        echo "$target" > "$proxy_file"

        set_color green; echo "● Proxy ON -> $target"; set_color normal
    end

    # Helper to format/normalize input to full URL
    function _proxy_normalize --argument-names input
        set -l val (string trim "$input")

        # If it has a scheme already, return as is
        if string match -qr '^[a-zA-Z0-9+-]+://' -- "$val"
            echo "$val"
            return 0
        end

        # Strip leading colon if provided (e.g. :3068)
        set val (string replace -r '^:' '' -- "$val")

        # If it is only digits (a port number), default host is localhost
        if string match -qr '^\d+$' -- "$val"
            echo "http://localhost:$val"
            return 0
        end

        # If it matches host:port
        if string match -qr '^.+:\d+$' -- "$val"
            echo "http://$val"
            return 0
        end

        # Default fallback
        echo "http://$val"
    end

    # Argument handling
    switch (count $argv)
        case 0
            # Interactive mode
            set -l default_presets \
                "http://localhost:3067" \
                "http://localhost:3068" \
                "http://localhost:10808" \
                "http://localhost:10809" \
                "http://localhost:7890" \
                "http://localhost:2080" \
                "socks5://127.0.0.1:1080"

            set_color cyan; echo "Current Status:"; set_color normal
            _proxy_status
            echo ""
            set_color cyan; echo "Select an option:"; set_color normal
            echo "  [0] Turn proxy OFF"
            for i in (seq (count $default_presets))
                echo "  [$i] $default_presets[$i]"
            end
            echo "  [c] Enter custom address / port"
            echo "  [q] Cancel / Quit"
            echo ""

            read -P "Choice [default: 1]: " -l choice
            if test -z "$choice"
                set choice 1
            end

            switch "$choice"
                case 0 "off"
                    _proxy_off
                case q "quit" "exit"
                    return 0
                case c "custom"
                    read -P "Enter proxy address or port (e.g. 3068, 127.0.0.1:3068, http://...): " -l custom_input
                    if test -n "$custom_input"
                        set -l normalized (_proxy_normalize "$custom_input")
                        _proxy_set "$normalized"
                    else
                        echo "No input provided."
                    end
                case (seq (count $default_presets))
                    set -l selected $default_presets[$choice]
                    _proxy_set "$selected"
                case '*'
                    # Check if user directly typed a port or URL at the prompt
                    set -l normalized (_proxy_normalize "$choice")
                    _proxy_set "$normalized"
            end

        case 1
            switch "$argv[1]"
                case "-h" "--help" "help"
                    _proxy_help
                case "off" "clear" "disable"
                    _proxy_off
                case "status" "show"
                    _proxy_status
                case '*'
                    set -l normalized (_proxy_normalize "$argv[1]")
                    _proxy_set "$normalized"
            end

        case '*'
            _proxy_help
            return 1
    end
end
