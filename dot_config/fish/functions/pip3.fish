function pip3 --wraps "uv pip" --description "Transparent wrapper redirecting pip3 to uv pip"
    if type -q uv
        if test (count $argv) -eq 1; and test "$argv[1]" = "-V" -o "$argv[1]" = "--version"
            set -l _uv_ver (uv --version 2>/dev/null | string split ' ')[2]
            echo "pip 24.0 (uv $_uv_ver)"
            return 0
        end
        uv pip $argv
    else if type -q /usr/bin/pip3
        /usr/bin/pip3 $argv
    else if type -q /usr/bin/pip
        /usr/bin/pip $argv
    else
        echo "pip3: command not found (neither uv nor pip installed)" >&2
        return 127
    end
end
