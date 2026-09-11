function withproxy --description "Run a command temporarily with proxy environment variables (falls back to default preset)"
    if test (count $argv) -eq 0
        echo "Usage: withproxy <command> [args...]" >&2
        return 1
    end

    set -l default_preset "http://localhost:10808"
    set -l proxy_file "$HOME/.config/proxy_state"
    set -l proxy_last_used_file "$HOME/.config/proxy_last_used"
    set -l target_proxy ""

    if set -q http_proxy; and test -n "$http_proxy"
        set target_proxy "$http_proxy"
    else if set -q HTTP_PROXY; and test -n "$HTTP_PROXY"
        set target_proxy "$HTTP_PROXY"
    else if set -q all_proxy; and test -n "$all_proxy"
        set target_proxy "$all_proxy"
    else if set -q ALL_PROXY; and test -n "$ALL_PROXY"
        set target_proxy "$ALL_PROXY"
    else if test -s "$proxy_file"
        set target_proxy (cat "$proxy_file" 2>/dev/null)
    else if test -s "$proxy_last_used_file"
        set target_proxy (cat "$proxy_last_used_file" 2>/dev/null)
    end

    if test -z "$target_proxy"
        set target_proxy "$default_preset"
    end

    set -l no_proxy_val "localhost,127.0.0.1,::1,localaddress,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
    set -l git_ssh_cmd ""

    if type -q socat; and test -n "$target_proxy"
        set -l parsed (python3 -c "
import urllib.parse, sys
u = urllib.parse.urlparse('$target_proxy')
scheme = u.scheme or 'http'
host = u.hostname or '127.0.0.1'
port = u.port or (1080 if 'socks' in scheme else 8080)
print(f'{scheme} {host} {port}')
" 2>/dev/null)
        if test -n "$parsed"
            set -l parts (string split " " "$parsed")
            set -l p_host $parts[2]
            set -l p_port $parts[3]
            set git_ssh_cmd "ssh -o ProxyCommand='socat - SOCKS5:$p_host:%h:%p,socksport=$p_port'"
        end
    end

    if test -n "$git_ssh_cmd"
        env http_proxy="$target_proxy" https_proxy="$target_proxy" \
            HTTP_PROXY="$target_proxy" HTTPS_PROXY="$target_proxy" \
            all_proxy="$target_proxy" ALL_PROXY="$target_proxy" \
            no_proxy="$no_proxy_val" NO_PROXY="$no_proxy_val" \
            GIT_SSH_COMMAND="$git_ssh_cmd" $argv
    else
        env http_proxy="$target_proxy" https_proxy="$target_proxy" \
            HTTP_PROXY="$target_proxy" HTTPS_PROXY="$target_proxy" \
            all_proxy="$target_proxy" ALL_PROXY="$target_proxy" \
            no_proxy="$no_proxy_val" NO_PROXY="$no_proxy_val" $argv
    end
end
