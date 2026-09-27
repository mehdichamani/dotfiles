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
            Write-Host "Usage: dotsync [dry-run | apply | install | <peer_device>]" -ForegroundColor Yellow
            return
        } elseif ($tLower -in @("dry-run", "dryrun", "-n", "--dry-run")) {
            $DryRun = $true
            $Target = ""
        } elseif ($tLower -eq "install") {
            Write-Host "📦 Running package verification & installer..." -ForegroundColor Cyan
            $checkPkgScript = Join-Path $HOME ".config\scripts\check-packages.ps1"
            if (Test-Path $checkPkgScript) {
                & pwsh -NoProfile -ExecutionPolicy Bypass -File $checkPkgScript
            } else {
                Write-Host "⚠️  $checkPkgScript not found. Running via chezmoi execute-template..." -ForegroundColor DarkYellow
                & chezmoi execute-template (Get-Content (Join-Path $repoDir "dot_config\scripts\check-packages.ps1.tmpl") -Raw) | & pwsh -NoProfile -ExecutionPolicy Bypass -Command -
            }

            Write-Host "🔗 Checking Obsidian vault symlink..." -ForegroundColor Cyan
            $setupObsidianScript = Join-Path $HOME ".config\scripts\setup-obsidian.ps1"
            if (Test-Path $setupObsidianScript) {
                & pwsh -NoProfile -ExecutionPolicy Bypass -File $setupObsidianScript
            } else {
                Write-Host "⚠️  $setupObsidianScript not found. Running via chezmoi execute-template..." -ForegroundColor DarkYellow
                & chezmoi execute-template (Get-Content (Join-Path $repoDir "dot_config\scripts\setup-obsidian.ps1.tmpl") -Raw) | & pwsh -NoProfile -ExecutionPolicy Bypass -Command -
            }
            return
        } elseif ($tLower -eq "apply") {
            Write-Host "🔄 Applying Chezmoi state..." -ForegroundColor Cyan
            & chezmoi apply
            if ($LASTEXITCODE -eq 0 -or $? -eq $true) {
                Write-Host "🐚 Reloading PowerShell profile..." -ForegroundColor Cyan
                if (Test-Path $PROFILE) {
                    . $PROFILE
                }
                Write-Host "✅ Applied and profile reloaded." -ForegroundColor Green
            }
            return
        }
    }

    $syncArgs = @($pyScript, "dotsync")
    if ($DryRun) { $syncArgs += "-n" }
    if ($Target) { $syncArgs += $Target }

    & python $syncArgs
}
