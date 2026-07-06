# Shared cross-platform helper: make directory and change into it
function mkcd
    mkdir -p $argv[1]
    and cd $argv[1]
end
