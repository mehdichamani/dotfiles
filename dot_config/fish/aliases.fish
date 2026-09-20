# Eza (Enhanced ls) [cite: 6, 7]
if type -q eza
    # ls command with icons sort hyperlink
    alias ls='eza --icons=auto --group-directories-first --sort=name --hyperlink'
    # ls long git human-time
    alias ll='eza --icons=auto --group-directories-first --sort=name --hyperlink --long --git --time-style=relative'
    # ls long hidden machine-time
    alias la='eza --icons=auto --group-directories-first --sort=name --hyperlink --long --git --all'
    # ls long newest first
    alias ld='eza --long --icons=auto --git --sort=modified --reverse --time-style=relative --all'
    # ls tree 2
    alias lt='eza --tree --level=2 --icons=auto'
    # ls tree 3
    alias lt3='eza --tree --level=3 --icons=auto'
    # ls tree unlimited
    alias ltu='eza --tree --icons=auto'
end

# Shared cross-platform helpers
alias c='clear'
alias q='exit'


# System shortcuts
alias mkv='python3 ~/.config/scripts/mkvOrganizer.py'
alias ffm='python3 ~/.config/scripts/ffm.py'
alias pinstall='~/.config/scripts/pinstall.sh'
alias ipl='~/.config/scripts/ipl'
alias myip='~/.config/scripts/ipl'



if command -v batcat > /dev/null
    alias bat='batcat'
end

# Nvim 
alias v='nvim'
alias nv='nvim .'
alias sv='sudo -E nvim' # Preserves your nvim config even as root

# Git 
abbr -a gs 'git status'
abbr -a ga 'git add'
abbr -a gaa 'git add .'
abbr -a gc 'git commit -m'
abbr -a gp 'git push'
abbr -a gl 'git log --oneline --graph --decorate --all'
abbr -a gco 'git checkout'
abbr -a gb 'git branch'
abbr -a gd 'git diff'
abbr -a gpl 'git pull'
abbr -a gst 'git stash'

# Docker
abbr -a dps 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"'
abbr -a dup 'docker compose up'
abbr -a dupd 'docker compose up -d'
abbr -a dbu 'docker compose up -d --build'
abbr -a dupbd 'docker compose up -d --build'
abbr -a ddown 'docker compose down'
abbr -a ddownv 'docker compose down -v --remove-orphans'
abbr -a dlogs 'docker compose logs -f'
abbr -a dres 'docker compose restart'
abbr -a dimg 'docker images'

# yt-dlp
abbr -a yt-dlp 'yt-dlp --cookies-from-browser firefox --js-runtimes node'

# aria2
abbr -a aria2c 'aria2c -c -x 16 -s 16 -k 1M'

# Python & uv shortcuts
if type -q uv
    abbr -a uvi 'uv pip install'
    abbr -a uvu 'uv pip uninstall'
    abbr -a uvl 'uv pip list'
    abbr -a uvt 'uv pip tree'
    abbr -a uvr 'uv run'
    abbr -a uvx 'uvx'
end

# Cross-platform Update alias (Arch, Ubuntu/Debian, and Termux)
if type -q pacman
    alias update='sudo pacman -Syu'
else if test -n "$TERMUX_VERSION"
    # pkg is the preferred wrapper in Termux
    alias update='pkg update && pkg upgrade -y'
    # Full Termux backup & restore (interactive selection & progress bar)
    abbr -a tbackup '~/.config/scripts/termux-backup-tool.sh backup'
    abbr -a trestore '~/.config/scripts/termux-backup-tool.sh restore'
    # Termux-X11 and XFCE4 GUI Launcher
    abbr -a xfce '~/.config/scripts/start-xfce.sh'
    alias wake-home='wol b4:2e:99:5b:ac:3c'
else if type -q apt
    alias update='sudo apt update && sudo apt upgrade -y'
end

# Network connection switching (Ethernet / Wi-Fi)
abbr -a lanup 'nmcli connection up "Wired connection 1"'
abbr -a landown 'nmcli connection down "Wired connection 1"'


if test -z "$TERMUX_VERSION"
    function cline
        mise exec node@22 -- cline $argv
    end
end