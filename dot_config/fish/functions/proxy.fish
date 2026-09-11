function proxy --description "Manage shell and system proxy configurations"
    set -l proxy_file "$HOME/.config/proxy_state"

    # Run the core bash proxy script
    bash -c ". ~/.config/scripts/proxy.sh && proxy \"\$@\"" -- $argv

    # Sync environment variables to the active Fish session
    if test -f "$proxy_file"
        set -l val (cat "$proxy_file" 2>/dev/null)
        set -gx http_proxy "$val"; set -gx HTTP_PROXY "$val"
        set -gx https_proxy "$val"; set -gx HTTPS_PROXY "$val"
        set -gx all_proxy "$val"; set -gx ALL_PROXY "$val"
        set -gx no_proxy "localhost,127.0.0.1,::1,localaddress,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
        set -gx NO_PROXY "$no_proxy"

        if type -q socat; and test -n "$val"
            set -l parsed (python3 -c "
import urllib.parse
u = urllib.parse.urlparse('$val')
scheme = u.scheme or 'http'
host = u.hostname or '127.0.0.1'
port = u.port or (1080 if 'socks' in scheme else 8080)
print(f'{scheme} {host} {port}')
" 2>/dev/null)
            if test -n "$parsed"
                set -l parts (string split " " "$parsed")
                set -l p_scheme $parts[1]
                set -l p_host $parts[2]
                set -l p_port $parts[3]
                set -l socks_type "SOCKS5"
                set -gx GIT_SSH_COMMAND "ssh -o ProxyCommand='socat - $socks_type:$p_host:%h:%p,socksport=$p_port'"
            end
        end
    else
        set -e http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY GIT_SSH_COMMAND
    end
end
