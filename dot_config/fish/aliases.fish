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

# lvm status percent test
alias lvm-check="sudo lvs -o lv_name,vg_name,attr,size,snap_percent,origin"

# figlet auto load fonts
alias figlet="figlet -d ~/.local/share/figlet/fonts"

# ssh wake work pc
alias wake-workpc='ssh 2011 "/tool wol mac=5C:62:8B:C4:DE:9B interface=ether2"'
alias ping-workpc='ssh 2011 "/ping 172.20.2.200"'

alias mkv='python3 ~/.config/scripts/mkvOrganizer.py'
alias ffm='python3 ~/.config/scripts/ffm.py'

# Proxy
alias proxy='set -Ux http_proxy http://localhost:2080; set -Ux https_proxy http://localhost:2080; set -Ux HTTP_PROXY http://localhost:2080; set -Ux HTTPS_PROXY http://localhost:2080; echo "Proxy ON"'
alias noproxy='set -e http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy; echo "Proxy OFF"'

# Fish-only utilities
alias refresh='chezmoi apply; and source ~/.config/fish/config.fish'

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

# scrcpy
abbr -a dex 'scrcpy --new-display=1920x1080/284 --turn-screen-off --stay-awake'

# Cross-platform Update alias (Arch, Ubuntu/Debian, and Termux)
if type -q pacman
    alias update='sudo pacman -Syu'
else if test -n "$TERMUX_VERSION"
    # pkg is the preferred wrapper in Termux
    alias update='pkg update && pkg upgrade -y'
else if type -q apt
    alias update='sudo apt update && sudo apt upgrade -y'
end