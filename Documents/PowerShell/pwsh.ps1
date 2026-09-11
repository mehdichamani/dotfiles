# =============================================================================
# PowerShell Profile - Combined Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# Setup and Initialization
# -----------------------------------------------------------------------------

# Check if current session is interactive
$isInteractive = -not ([Environment]::GetCommandLineArgs() -match '-(Command|c|EncodedCommand|e|File|f|NonInteractive)')

# Fast fetch (interactive only)
if ($isInteractive -and (Get-Command fastfetch -ErrorAction SilentlyContinue)) {
    fastfetch
}

# Fetch system proxy settings
$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
if (Test-Path $regPath) {
    $proxySettings = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue

    # Apply proxy to session if enabled
    if ($proxySettings -and $proxySettings.ProxyEnable -eq 1) {
        $proxyServer = $proxySettings.ProxyServer
        
        # Handle multiple protocols or single server
        if ($proxyServer -match ';') {
            $proxies = $proxyServer -split ';'
            $httpVal = "http://" + (($proxies | Select-String "http=").ToString() -replace "http=", "")
            $httpsVal = "http://" + (($proxies | Select-String "https=").ToString() -replace "https=", "")
            $env:http_proxy = $httpVal
            $env:HTTP_PROXY = $httpVal
            $env:https_proxy = $httpsVal
            $env:HTTPS_PROXY = $httpsVal
            $env:all_proxy = $httpVal
            $env:ALL_PROXY = $httpVal
        } else {
            $proxyVal = "http://$proxyServer"
            $env:http_proxy = $proxyVal
            $env:HTTP_PROXY = $proxyVal
            $env:https_proxy = $proxyVal
            $env:HTTPS_PROXY = $proxyVal
            $env:all_proxy = $proxyVal
            $env:ALL_PROXY = $proxyVal
        }

        # Apply to native .NET/PowerShell web cmdlets
        [System.Net.WebRequest]::DefaultWebProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    } else {
        Remove-Item env:http_proxy, env:HTTP_PROXY, env:https_proxy, env:HTTPS_PROXY, env:all_proxy, env:ALL_PROXY -ErrorAction SilentlyContinue
    }
}

# Starship initialization
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# Starship environment name
$namePath = "$HOME\.config\name"
if (Test-Path $namePath) {
    $content = Get-Content -Raw $namePath
    if ([string]::IsNullOrWhiteSpace($content)) {
        if ($isInteractive) {
            Write-Host "⚠️  WARNING: Starship name file is empty!" -ForegroundColor Yellow
        }
        $env:STARSHIP_ENV = "notDefined"
    } else {
        $env:STARSHIP_ENV = $content.Trim()
    }
} else {
    if ($isInteractive) {
        Write-Host "⚠️  WARNING: Starship name file not found at $namePath" -ForegroundColor Red
    }
    $env:STARSHIP_ENV = "notDefined"
}

# Zoxide initialization
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
}

# PowerToys CommandNotFound module
if (Get-Module -ListAvailable -Name Microsoft.WinGet.CommandNotFound) {
    Import-Module -Name Microsoft.WinGet.CommandNotFound -ErrorAction SilentlyContinue
}

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ls variants (eza)
# -----------------------------------------------------------------------------

if (Get-Command eza -ErrorAction SilentlyContinue) {
    # Remove default ls alias
    Remove-Item -Path Alias:ls -Force -ErrorAction SilentlyContinue

    # ls command with icons, sort by name, hyperlink
    function ls { eza --icons=auto --group-directories-first --sort=name --hyperlink }

    # ls long with git info, human-readable time
    function ll { eza --icons=auto --group-directories-first --sort=name --hyperlink --long --git --time-style=relative }

    # ls long with all files (including hidden)
    function la { eza --icons=auto --group-directories-first --sort=name --hyperlink --long --git --all }

    # ls long, newest first
    function ld { eza --long --icons=auto --git --sort=modified --reverse --time-style=relative --all }

    # ls tree, 2 levels deep
    function lt { eza --tree --level=2 --icons=auto }

    # ls tree, 3 levels deep
    function lt3 { eza --tree --level=3 --icons=auto }

    # ls tree, unlimited depth
    function ltu { eza --tree --icons=auto }
}

# -----------------------------------------------------------------------------
# Navigation shortcuts
# -----------------------------------------------------------------------------

# Clear screen shortcut
function c { Clear-Host }

# Exit shortcut
function q { exit }

# -----------------------------------------------------------------------------
# yt-dlp wrapper
# -----------------------------------------------------------------------------

function yt-dlp { python -m yt_dlp @args }

# -----------------------------------------------------------------------------
# Git shortcuts
# -----------------------------------------------------------------------------

function gs { git status @args }
function ga { git add @args }
function gaa { git add . }
function gc { git commit -m @args }
function gp { git push @args }
function gl { git log --oneline --graph --decorate --all @args }
function gco { git checkout @args }
function gb { git branch @args }
function gd { git diff @args }
function gpl { git pull @args }
function gst { git stash @args }

# -----------------------------------------------------------------------------
# Script launchers
# -----------------------------------------------------------------------------

# ffmpeg tools script launcher
function ffm { py "$HOME/.config/scripts/ffm.py" @args }

# MKV organizer script
function mkv { py "$HOME/.config/scripts/mkvOrganizer.py" @args }

# -----------------------------------------------------------------------------
# Auto-load Custom Functions
# -----------------------------------------------------------------------------

$functionsDir = Join-Path $PSScriptRoot "Functions"
if (Test-Path $functionsDir) {
    Get-ChildItem -Path $functionsDir -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}




