function _agyp_run --description "Internal runner for agyp multi-account in Ubuntu PRoot"
    set -l acc_id "$argv[1]"
    set -e argv[1]

    withproxy fish -c '
        set -l id "$argv[1]"
        set -e argv[1]
        set -l token_dir "/root/.gemini/antigravity-cli"
        set -l active_token "$token_dir/antigravity-oauth-token"
        set -l acc_token "$token_dir/antigravity-oauth-token.$id"

        # If this account has a saved token, swap it in
        if test -s "$acc_token"
            cp -f "$acc_token" "$active_token"
        else
            # First time using this account: remove any existing active token so agy triggers a fresh login
            rm -f "$active_token"
        end

        # Run agy inside proot preserving exact arguments
        proot-distro login ubuntu --work-dir "$PWD" -- env \
            http_proxy="$http_proxy" \
            https_proxy="$https_proxy" \
            all_proxy="$all_proxy" \
            /root/.local/bin/agy --dangerously-skip-permissions $argv

        set -l ret $status

        # After execution (or login), save the new/refreshed token to this account
        if test -s "$active_token"
            cp -f "$active_token" "$acc_token"
        end

        return $ret
    ' -- "$acc_id" $argv
end
