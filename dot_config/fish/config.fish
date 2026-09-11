# Environment Variables
test -d /usr/share/omarchy; and set -gx OMARCHY_PATH /usr/share/omarchy
set -gx EDITOR nvim 
set -gx VISUAL nvim
fish_add_path --prepend $HOME/.venv/bin

set -gx ANDROID_HOME $HOME/Android/Sdk
fish_add_path $ANDROID_HOME/cmdline-tools/latest/bin
fish_add_path $ANDROID_HOME/platform-tools


# Disable the greeting
set -g fish_greeting


# user shell tools
if status is-interactive
    # Load persistent proxy state
    set -l proxy_state_file "$HOME/.config/proxy_state"
    if test -s "$proxy_state_file"
        set -l _p_val (cat "$proxy_state_file" 2>/dev/null)
        if test -n "$_p_val"
            set -gx http_proxy "$_p_val"; set -gx HTTP_PROXY "$_p_val"
            set -gx https_proxy "$_p_val"; set -gx HTTPS_PROXY "$_p_val"
            set -gx all_proxy "$_p_val"; set -gx ALL_PROXY "$_p_val"
            set -gx no_proxy "localhost,127.0.0.1,::1,localaddress,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
            set -gx NO_PROXY "$no_proxy"

            if type -q socat
                set -l parsed (python3 -c "
import urllib.parse
u = urllib.parse.urlparse('$_p_val')
scheme = u.scheme or 'http'
host = u.hostname or '127.0.0.1'
port = u.port or (1080 if 'socks' in scheme else 8080)
print(f'{scheme} {host} {port}')
" 2>/dev/null)
                if test -n "$parsed"
                    set -l parts (string split " " "$parsed")
                    set -l p_host $parts[2]
                    set -l p_port $parts[3]
                    set -gx GIT_SSH_COMMAND "ssh -o ProxyCommand='socat - SOCKS5:$p_host:%h:%p,socksport=$p_port'"
                end
            end
        end
    end

    # Detect Termius on Android (connecting locally to Termux OpenSSH via 127.0.0.1)
    set -l is_termius 0
    if test -n "$TERMUX_VERSION" -a -n "$SSH_CLIENT"
        set -l _ssh_ip (string split " " -- "$SSH_CLIENT")[1]
        if test "$_ssh_ip" = "127.0.0.1"
            set is_termius 1
        end
    end

    if test $is_termius -eq 0
        # starship (fish-specific config)
        set -gx STARSHIP_CONFIG ~/.config/starship.toml
        starship init fish | source
    end
    
    if type -q zoxide
        zoxide init --cmd cd fish | source
    end

    if type -q direnv
        direnv hook fish | source
    end

    if type -q mise
        mise activate fish | source
    end

    # fastfetch
    if test $is_termius -eq 0; and type -q fastfetch
        fastfetch
    end


    # Termux SSH Automation (start on local shell open, stop on exit)
    if test -n "$TERMUX_VERSION" # More reliable check than $PREFIX
        if not pgrep -f sshd >/dev/null
            echo "🚀 Starting SSH server..."
            sshd
        end

        # Stop SSH server only when exiting the LAST local Termux session
        if test -z "$SSH_CONNECTION"
            function __termux_cleanup_sshd --on-event fish_exit
                # Count local fish shells (excluding sub-shells attached to sshd-session)
                set -l local_sessions (pgrep -f "fish" | while read -l p
                    # Check if process is not a descendant of sshd
                    if not pstree -s $p 2>/dev/null | grep -q sshd
                        echo $p
                    end
                end)

                # If this is the only/last local fish session exiting, stop sshd
                if test (count $local_sessions) -le 1
                    pkill -f sshd >/dev/null 2>&1
                end
            end
        end
    end
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


# Load aliases
if test -f ~/.config/fish/aliases.fish
    source ~/.config/fish/aliases.fish
end

# Auto-switch between project venv and global venv
function __auto_python_venv --on-variable PWD --description "Auto switch Python venvs"
    set -l dir $PWD
    set -l project_venv ""
    while test "$dir" != "/" -a -n "$dir"
        if test -f "$dir/.venv/bin/activate.fish"
            set project_venv "$dir/.venv"
            break
        else if test -f "$dir/venv/bin/activate.fish"
            set project_venv "$dir/venv"
            break
        end
        set dir (path dirname $dir)
    end

    if test -n "$project_venv"
        if test "$VIRTUAL_ENV" != "$project_venv"
            source "$project_venv/bin/activate.fish"
        end
    else
        if test -f "$HOME/.venv/bin/activate.fish"; and test "$VIRTUAL_ENV" != "$HOME/.venv"
            source "$HOME/.venv/bin/activate.fish"
        end
    end
end

__auto_python_venv

# Load secrets
if test -f ~/.config/fish/secrets.fish
    source ~/.config/fish/secrets.fish
end