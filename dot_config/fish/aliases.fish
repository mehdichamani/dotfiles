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
alias pinstall='~/.config/scripts/pinstall.sh'
alias ipl='~/.config/scripts/ipl'
alias agy-chat-sync-worker='python3 ~/.config/scripts/sync_live_chat.py'

if command -v batcat > /dev/null
    alias bat='batcat'
end

# Nvim 
alias v='nvim'
alias sv='sudo -E nvim' # Preserves your nvim config even as root

# Git 
abbr -a gs 'git status'
abbr -a ga 'git add'
abbr -a gaa 'git add .'
abbr -a gc 'git commit -m'
abbr -a gca 'git commit --amend --no-edit'
abbr -a gl "git log -n 5 --graph --pretty=format:'%C(yellow)%h%Creset -%C(auto)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset'"

# Docker
abbr -a dps 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"'
abbr -a dup 'docker compose up'
abbr -a dupd 'docker compose up -d'
abbr -a dbu 'docker compose up -d --build'
abbr -a dupbd 'docker compose up -d --build'
abbr -a ddown 'docker compose down'
abbr -a ddownv 'docker compose down -v --remove-orphans'
abbr -a dlogs 'docker compose logs -f'


# aria2
abbr -a aria2c 'aria2c -c -x 16 -s 16 -k 1M'



# Termux
if test -n "$TERMUX_VERSION"
    # pkg is the preferred wrapper in Termux
    alias update='pkg update && pkg upgrade -y'
    # Full Termux backup & restore (interactive selection & progress bar)
    abbr -a tbackup '~/.config/scripts/termux-backup-tool.sh backup'
    abbr -a trestore '~/.config/scripts/termux-backup-tool.sh restore'
    alias wake-home='wol b4:2e:99:5b:ac:3c'
end