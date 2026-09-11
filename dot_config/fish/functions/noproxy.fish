function noproxy --description "Run a command temporarily without proxy environment variables"
    if test (count $argv) -eq 0
        echo "Usage: noproxy <command> [args...]" >&2
        return 1
    end

    env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
        -u all_proxy -u ALL_PROXY -u ftp_proxy -u FTP_PROXY \
        -u rsync_proxy -u RSYNC_PROXY -u no_proxy -u NO_PROXY \
        -u GIT_SSH_COMMAND $argv
end
