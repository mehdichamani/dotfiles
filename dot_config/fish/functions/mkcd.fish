# Shared cross-platform helper: make directory and change into it
function mkcd -d "Create a new directory and immediately change into it"
    mkdir -p $argv[1]
    and cd $argv[1]
end
