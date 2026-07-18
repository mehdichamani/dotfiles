# Environment Variables
set -gx EDITOR nvim 
set -gx VISUAL nvim
set -gx FIGLET_FONTDIR "$HOME/.local/share/figlet"
fish_add_path --prepend $HOME/.venv/bin

# Disable the greeting
set -g fish_greeting

set -g no_proxy localhost,127.0.0.1
set -g NO_PROXY localhost,127.0.0.1

# user shell tools
if status is-interactive
    # starship (fish-specific config)
    set -gx STARSHIP_CONFIG ~/.config/starship.toml
    starship init fish | source
    
    if type -q zoxide
        zoxide init --cmd cd fish | source
    end

    # fastfetch
    if type -q fastfetch
        fastfetch
    end

    # yazi
    function y
        set tmp (mktemp -t "yazi-cwd.XXXXXX")
        command yazi $argv --cwd-file="$tmp"
        if read -z cwd < "$tmp"; and [ "$cwd" != "$PWD" ]; and test -d "$cwd"
            builtin cd -- "$cwd"
        end
        command rm -f -- "$tmp"
    end

    # Proxy status
    if set -q http_proxy; or set -q HTTP_PROXY
        set_color green; echo "● Proxy ON ($http_proxy)"; set_color normal
    else
        set_color yellow; echo "○ Proxy OFF"; set_color normal
    end

    # Termux SSH Automation 
    if test -n "$TERMUX_VERSION" # More reliable check than $PREFIX
        if not pgrep -f sshd >/dev/null
            echo "🚀 Starting SSH server..."
            sshd
        end
    end
end

# Load aliases
if test -f ~/.config/fish/aliases.fish
    source ~/.config/fish/aliases.fish
end

set name_path "$HOME/.config/name"

if test -f $name_path
    read -l content < $name_path
    if test -z "$content"
        if status is-interactive
            set_color yellow
            echo "⚠️  WARNING: Starship name file is empty!"
            set_color normal
        end
        set -gx STARSHIP_ENV "notDefined"
    else
        set -gx STARSHIP_ENV $content
    end
else
    if status is-interactive
        set_color red
        echo "⚠️  WARNING: Starship name file not found at $name_path"
        set_color normal
    end
    set -gx STARSHIP_ENV "notDefined"
end

source ~/.venv/bin/activate.fish