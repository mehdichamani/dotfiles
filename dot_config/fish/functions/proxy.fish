function proxy --description "Manage shell and system proxy configurations"
    set -l proxy_file (test -n "$XDG_RUNTIME_DIR" -a -d "$XDG_RUNTIME_DIR"; and echo "$XDG_RUNTIME_DIR/current_proxy"; or echo "/tmp/current_proxy")

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
    else
        set -e http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    end
end
