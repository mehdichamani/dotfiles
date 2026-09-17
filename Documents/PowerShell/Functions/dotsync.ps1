<#
.SYNOPSIS
    Dotsync - Dynamic P2P Git Sync and Mesh Dotfiles Manager for Chezmoi (PowerShell 7+)
.DESCRIPTION
    Wraps dotsync execution using the unified python backend (~/.config/scripts/mesh_core.py).
.PARAMETER Target
    Optional peer to sync specifically with.
.PARAMETER DryRun
    Check connections and commit differences without pushing or pulling.
.EXAMPLE
    dotsync
.EXAMPLE
    dotsync work
.EXAMPLE
    dotsync -DryRun
#>
function dotsync {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$false)]
        [string]$Target,

        [Parameter(Mandatory=$false)]
        [Alias("n")]
        [switch]$DryRun
    )

    $repoDir = Join-Path $HOME ".local\share\chezmoi"
    $pyScript = Join-Path $HOME ".config\scripts\mesh_core.py"
    if (-not (Test-Path $pyScript)) {
        $pyScript = Join-Path $repoDir "dot_config\scripts\mesh_core.py"
    }

    if ($Target) {
        $tLower = $Target.ToLower()
        if ($tLower -in @("-h", "--help", "help")) {
            Write-Host "Usage: dotsync [dry-run | apply | install | refresh | <peer_device>]" -ForegroundColor Yellow
            return
        } elseif ($tLower -in @("dry-run", "dryrun", "-n", "--dry-run")) {
            $DryRun = $true
            $Target = ""
        } elseif ($tLower -eq "apply") {
            Write-Host "🔄 Applying Chezmoi state..." -ForegroundColor Cyan
            & chezmoi apply
            return
        } elseif ($tLower -eq "refresh") {
            Write-Host "✨ Refreshing live environment..." -ForegroundColor Cyan
            & chezmoi apply
            Write-Host "✅ Refreshed." -ForegroundColor Green
            return
        }
    }

    $syncArgs = @($pyScript, "dotsync")
    if ($DryRun) { $syncArgs += "-n" }
    if ($Target) { $syncArgs += $Target }

    & python $syncArgs
}
