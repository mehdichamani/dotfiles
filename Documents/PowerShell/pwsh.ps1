# =============================================================================
# PowerShell Profile - Combined Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# Setup and Initialization
# -----------------------------------------------------------------------------

# Fast fetch
fastfetch

# Starship initialization
Invoke-Expression (&starship init powershell)

# Starship environment name
$namePath = "$HOME\Documents\PowerShell\name"
if (Test-Path $namePath) {
    $content = Get-Content -Raw $namePath
    if ([string]::IsNullOrWhiteSpace($content)) {
        Write-Host "⚠️  WARNING: Starship name file is empty!" -ForegroundColor Yellow
        $env:STARSHIP_ENV = "notDefined"
    } else {
        $env:STARSHIP_ENV = $content.Trim()
    }
} else {
    Write-Host "⚠️  WARNING: Starship name file not found at $namePath" -ForegroundColor Red
    $env:STARSHIP_ENV = "Windows-PC"
}

# Zoxide initialization
Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })

# PowerToys CommandNotFound module
Import-Module -Name Microsoft.WinGet.CommandNotFound

# -----------------------------------------------------------------------------
# Proxy Configuration
# -----------------------------------------------------------------------------

# Fetch system proxy settings
$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$proxySettings = Get-ItemProperty -Path $regPath

# Apply proxy to session if enabled
if ($proxySettings.ProxyEnable -eq 1) {
    $proxyServer = $proxySettings.ProxyServer
    
    # Handle multiple protocols or single server
    if ($proxyServer -match ';') {
        $proxies = $proxyServer -split ';'
        $env:http_proxy = "http://" + (($proxies | Select-String "http=").ToString() -replace "http=", "")
        $env:https_proxy = "http://" + (($proxies | Select-String "https=").ToString() -replace "https=", "")
    } else {
        $env:http_proxy = "http://$proxyServer"
        $env:https_proxy = "http://$proxyServer"
    }

    # Apply to native .NET/PowerShell web cmdlets
    [System.Net.WebRequest]::DefaultWebProxy = [System.Net.WebRequest]::GetSystemWebProxy()
    [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
}

# Print proxy status
if ($proxySettings.ProxyEnable -eq 1) {
    Write-Host "Proxy: " -NoNewline; Write-Host "ENABLED" -ForegroundColor Green
    Write-Host "Address:   " -NoNewline; Write-Host $env:http_proxy -ForegroundColor Cyan
} else {
    Write-Host "Status: " -NoNewline; Write-Host "DISABLED (Direct Connection)" -ForegroundColor Gray
}

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ls variants
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Navigation shortcuts
# -----------------------------------------------------------------------------

# Clear screen shortcut
function c { Clear-Host }

# Exit shortcut
function q { exit }

# -----------------------------------------------------------------------------
# Directory management
# -----------------------------------------------------------------------------

# Create directory and cd into it
function mkcd {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    Set-Location -Path $Path
}

# -----------------------------------------------------------------------------
# Path editor
# -----------------------------------------------------------------------------

# Edit shell path with vscode with save on exit
function Edit-Path {
    [CmdletBinding()]
    param (
        [ValidateSet('User', 'Machine')]
        [string]$Target = 'User'
    )

    # 1. Get the current PATH from the registry based on target
    $RegistryTarget = if ($Target -eq 'User') { [EnvironmentVariableTarget]::User } else { [EnvironmentVariableTarget]::Machine }
    $CurrentPath = [Environment]::GetEnvironmentVariable('Path', $RegistryTarget)

    if ([string]::IsNullOrEmpty($CurrentPath)) {
        Write-Error "Could not retrieve the $Target PATH variable."
        return
    }

    # 2. Split paths by the system delimiter (;) and create a temporary file
    $PathLines = $CurrentPath -split ';' | Where-Object { $_ -ne "" }
    $TempFile = [System.IO.Path]::GetTempFileName() + ".txt"
    $PathLines | Out-File -FilePath $TempFile -Encoding utf8

    Write-Host "Opening $Target PATH in VS Code. Please edit, save, and close the file to apply changes..." -ForegroundColor Cyan

    # 3. Open in VS Code and WAIT
    Start-Process -FilePath "code" -ArgumentList "--wait", "`"$TempFile`"" -NoNewWindow -Wait

    # 4. Read the modified file
    if (Test-Path $TempFile) {
        $NewLines = Get-Content -Path $TempFile | Where-Object { $_ -notmatch '^\s*$' }
        $NewPath = $NewLines -join ';'

        # Clean up the temp file
        Remove-Item $TempFile -Force

        # 5. Save the updated PATH back to the environment
        try {
            [Environment]::SetEnvironmentVariable('Path', $NewPath, $RegistryTarget)
            Write-Host "Successfully updated $Target PATH!" -ForegroundColor Green
            Write-Host "Note: You may need to restart your terminal/apps to see the changes." -ForegroundColor Yellow
        }
        catch {
            Write-Error "Failed to save PATH. If editing 'Machine' target, ensure you ran PowerShell as Administrator.`nDetails: $_"
        }
    }
    else {
        Write-Error "Temporary file was lost. No changes were applied."
    }
}

# -----------------------------------------------------------------------------
# chezmoi management
# -----------------------------------------------------------------------------

# Apply chezmoi and reload shell
function refresh {
    <#
    .SYNOPSIS
        Applies chezmoi dotfile updates and reloads the PowerShell profile.
    #>
    Write-Host "Applying chezmoi changes..." -ForegroundColor Cyan
    
    # Run chezmoi apply
    chezmoi apply
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Chezmoi applied successfully. Reloading profile..." -ForegroundColor Green
        
        # Reload the current profile if it exists
        if (Test-Path $PROFILE) {
            . $PROFILE
            Write-Host "Profile reloaded!" -ForegroundColor Green
        } else {
            Write-Warning "PowerShell profile path ($PROFILE) not found."
        }
    } else {
        Write-Error "Chezmoi apply failed. Skipping profile reload."
    }
}

# -----------------------------------------------------------------------------
# yt-dlp wrapper
# -----------------------------------------------------------------------------

# yt-dlp with python and underscore
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
# Network utilities
# -----------------------------------------------------------------------------

# Change metrics of all network adapters
function metric {
    Write-Host "`n🔧 Interfaces found:" -ForegroundColor Cyan

    # Get interfaces and store them in an array to avoid pipeline binding issues
    $interfaces = @(Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -ne "Loopback Pseudo-Interface 1" })

    # Display current metrics
    $interfaces | Sort-Object InterfaceMetric | Format-Table ifIndex, InterfaceAlias, InterfaceMetric

    foreach ($interface in $interfaces) {
        $name = $interface.InterfaceAlias
        $current = $interface.InterfaceMetric

        # Prompt user for new metric
        $input = Read-Host ">> Enter new metric for `"$name`" (Current: $current) [Enter to skip]"

        if ([string]::IsNullOrWhiteSpace($input)) {
            Write-Host "⏭️ Skipping $name (no change)" -ForegroundColor Yellow
            continue
        }

        if ($input -match '^\d+$') {
            try {
                Set-NetIPInterface -InterfaceAlias $name -InterfaceMetric $input -ErrorAction Stop
                Write-Host "✅ Metric of $name changed from $current to $input" -ForegroundColor Green
            } catch {
                Write-Host "❌ Error setting metric for ${name}: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "⚠️ Invalid input. Skipping $name..." -ForegroundColor Red
        }
    }

    Write-Host "`n📊 Final interface metrics:" -ForegroundColor Cyan
    Get-NetIPInterface -AddressFamily IPv4 | Sort-Object InterfaceMetric | Format-Table ifIndex, InterfaceAlias, InterfaceMetric
}

# -----------------------------------------------------------------------------
# File management
# -----------------------------------------------------------------------------

# Moves all files from subfolders to the current directory root
function sub2root {
    Write-Host "`n📁 Moving files from subfolders to root of: $($PWD.Path)" -ForegroundColor Cyan
    Write-Host "Press Enter to start, Ctrl+C to cancel..."
    Read-Host

    $filesMoved = 0
    Get-ChildItem -Recurse -File | Where-Object { $_.DirectoryName -ne $PWD.Path } | ForEach-Object {
        $destination = Join-Path $PWD.Path $_.Name
        if (-not (Test-Path $destination)) {
            Write-Host "📦 Moving: $($_.FullName)"
            Move-Item $_.FullName $PWD.Path
            $filesMoved++
        } else {
            Write-Host "⚠️ Skipped (already exists): $($_.Name)" -ForegroundColor Yellow
        }
    }

    Write-Host "`n✅ Move completed! $filesMoved file(s) moved." -ForegroundColor Green

    Write-Host "`n🧹 Remove all empty folders?"
    Write-Host "Press Enter to confirm, Ctrl+C to cancel..."
    Read-Host

    $emptyFolders = Get-ChildItem -Directory -Recurse | Where-Object { (Get-ChildItem $_.FullName).Count -eq 0 }
    if ($emptyFolders.Count -gt 0) {
        $emptyFolders | Remove-Item
        Write-Host "🗑️ Empty folders removed!" -ForegroundColor Green
    } else {
        Write-Host "📂 No empty folders found." -ForegroundColor Gray
    }
}

# -----------------------------------------------------------------------------
# Security utilities
# -----------------------------------------------------------------------------

# Lock BitLocker-enabled drive
function DriveLocker {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "This script requires administrative privileges. Please run PowerShell as Administrator." -ForegroundColor Red
        return
    }
    $allVolumes = Get-BitLockerVolume
    $enabledVolumes = $allVolumes | Where-Object {
        $_.KeyProtector.Count -gt 0 -and $_.MountPoint
    }
    if (-not $enabledVolumes) {
        Write-Host "No BitLocker-enabled volumes found." -ForegroundColor Yellow
        return
    }
    Write-Host "`nBitLocker-Enabled Volumes:"
    $enabledVolumes | ForEach-Object {
        $status = if ($_.VolumeStatus -eq $null) {
            '🔒 Locked'
        } elseif ($_.VolumeStatus -eq 'FullyEncrypted') {
            '🔓 Unlocked'
        } else {
            '❌ Not Encrypted'
        }
        Write-Host "Drive Letter: $($_.MountPoint) | Status: $status"
    }
    $inputDrive = Read-Host "`nEnter the drive letter you want to lock (e.g., D or D:)"
    $normalizedDrive = $inputDrive.Trim().ToUpper().TrimEnd('\')
    if ($normalizedDrive.Length -eq 1) {
        $normalizedDrive += ":"
    }
    $selectedVolume = $enabledVolumes | Where-Object { $_.MountPoint.TrimEnd('\').ToUpper() -eq $normalizedDrive }
    if (-not $selectedVolume) {
        Write-Host "Drive letter '$normalizedDrive' is not a valid BitLocker-enabled volume or not unlocked." -ForegroundColor Red
        return
    }
    Write-Host "`nLocking drive $normalizedDrive..."
    $lockResult = manage-bde -lock $normalizedDrive
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Drive $normalizedDrive locked successfully." -ForegroundColor Green
    } else {
        Write-Host "Failed to lock drive $normalizedDrive." -ForegroundColor Red
    }
    Write-Host "`nDone."
}

# -----------------------------------------------------------------------------
# Network diagnostics
# -----------------------------------------------------------------------------

# TCP leak check
function Get-TCPLeak {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Closed', 'CloseWait', 'Closing', 'DeleteTCB', 'Established', 'FinWait1', 'FinWait2', 'Listen', 'SynReceived', 'SynSent', 'TimeWait', 'Bound')]
        [string[]]$States = @('FinWait2', 'CloseWait', 'Bound'),

        [Parameter()]
        [int]$MinCount = 1
    )

    process {
        # Build a regex pattern from the target states
        $Pattern = ($States | ForEach-Object { [regex]::Escape($_) }) -join '|'

        Get-NetTCPConnection | 
            Where-Object { $_.State -match $Pattern } | 
            Group-Object OwningProcess | 
            Select-Object Count, 
                          @{Name="PID"; Expression={[int]$_.Name}}, 
                          @{Name="ProcessName"; Expression={(Get-Process -Id $_.Name -ErrorAction SilentlyContinue).Name}} | 
            Where-Object { $_.Count -ge $MinCount } |
            Sort-Object Count -Descending
    }
}

function mimo {
    wt -w 0 -p "MiMoCode" -d "$PWD"
}