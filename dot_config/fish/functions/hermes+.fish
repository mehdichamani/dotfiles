function hermes+ --wraps='/home/unreal/.local/bin/hermes' --description 'Run Hermes Agent with root privileges while preserving user HOME'
    sudo HOME=/home/unreal /home/unreal/.local/bin/hermes $argv
end

funcsave hermes+
