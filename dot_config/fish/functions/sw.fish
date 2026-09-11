function sw --description "Interactive Cisco Telnet selector (via Python helper)"
    python3 ~/.config/scripts/sw.py $argv
end

function __fish_sw_complete
    set -l ssh_config "$HOME/.ssh/config"
    if test -f "$ssh_config" -a -r "$ssh_config"
        for line in (grep '^#\s*@switch\s\+' "$ssh_config" 2>/dev/null)
            set -l raw (string replace -r '^#\s*@switch\s+' '' -- $line | string trim)
            if string match -q "*|*" -- $raw
                set -l parts (string split "|" -- $raw)
                set -l ip (string trim -- $parts[1])
                set -l name (string trim -- $parts[2])
                set -l desc ""
                if test (count $parts) -ge 3
                    set desc (string trim -- $parts[3])
                end
                printf "%s\t%s - %s\n" $name $ip $desc
                printf "%s\t%s - %s\n" $ip $name $desc
            else
                set -l parts (string split " " -- $raw)
                set -l ip $parts[1]
                set -l name $parts[2]
                set -l desc ""
                if test (count $parts) -ge 3
                    set desc (string join " " $parts[3..-1])
                end
                printf "%s\t%s - %s\n" $name $ip $desc
                printf "%s\t%s - %s\n" $ip $name $desc
            end
        end
    end
    echo -e "-h\tShow help message"
    echo -e "--help\tShow help message"
end

complete -c sw -f -a "(__fish_sw_complete)"
