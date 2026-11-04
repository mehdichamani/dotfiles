<#
.SYNOPSIS
    cm - Unified Chezmoi Dotfiles & Mesh Manager (PowerShell 7+)
.DESCRIPTION
    Wraps chezmoi and mesh dotfiles sync using the unified python backend (~/.config/scripts/mesh_core.py).
.EXAMPLE
    cm sync
.EXAMPLE
    cm sync work
.EXAMPLE
    cm apply
.EXAMPLE
    cm diff
#>
function cm {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$false)]
        [string]$Subcommand,

        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        [string[]]$RemainingArgs
    )

    $repoDir = Join-Path $HOME ".local\share\chezmoi"
    $pyScript = Join-Path $HOME ".config\scripts\mesh_core.py"
    if (-not (Test-Path $pyScript)) {
        $pyScript = Join-Path $repoDir "dot_config\scripts\mesh_core.py"
    }

    $cmd = if ($Subcommand) { $Subcommand.ToLower() } else { "" }

    switch ($cmd) {
        { $_ -in @("-h", "--help", "help", "") } {
            Write-Host "== Chezmoi Dotfiles Manager (cm) ==" -ForegroundColor Magenta
            Write-Host "Usage: cm <subcommand> [options]" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Subcommands:"
            Write-Host "  sync [<peer>] [-n]  Sync dotfiles P2P with all or a specific peer device"
            Write-Host "  apply [deep|none]   Apply dotfiles changes to system"
            Write-Host "  patch [status]      Apply or inspect system patches"
            Write-Host "  install             Run package verification & installer scripts"
            Write-Host "  diff                Show differences between target and destination (chezmoi diff)"
            Write-Host "  status              Show status of managed files (chezmoi status)"
            Write-Host "  -h, --help          Show this help message"
            return
        }

        "sync" {
            $syncArgs = @($pyScript, "dotsync")
            if ($RemainingArgs) {
                foreach ($arg in $RemainingArgs) {
                    if ($arg -in @("-n", "--dry-run", "dry-run", "dryrun")) {
                        $syncArgs += "-n"
                    } else {
                        $syncArgs += $arg
                    }
                }
            }
            & python3 @syncArgs
            return
        }

        "apply" {
            Write-Host "🔄 Applying Chezmoi state to home directory..." -ForegroundColor Cyan
            & chezmoi apply
            return
        }

        "patch" {
            Write-Host "ℹ️ System patches are primarily managed on Linux (Omarchy)." -ForegroundColor Yellow
            return
        }

        "install" {
            Write-Host "📦 Running package verification & installer..." -ForegroundColor Cyan
            $checkPkgScript = Join-Path $HOME ".config\scripts\check-packages.ps1"
            if (Test-Path $checkPkgScript) {
                & pwsh -NoProfile -ExecutionPolicy Bypass -File $checkPkgScript
            } else {
                & chezmoi execute-template (Get-Content (Join-Path $repoDir "dot_config\scripts\check-packages.ps1.tmpl") -Raw) | & pwsh -NoProfile -ExecutionPolicy Bypass -Command -
            }
            return
        }

        "diff" {
            & chezmoi diff @RemainingArgs
            return
        }

        "status" {
            & chezmoi status @RemainingArgs
            return
        }

        Default {
            Write-Host "❌ Unknown subcommand: '$Subcommand'" -ForegroundColor Red
            Write-Host "Run 'cm --help' for available subcommands."
            return
        }
    }
}
