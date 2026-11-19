<#
.SYNOPSIS
    sm - Unified SSH & Secrets Vault Manager (PowerShell 7+)
.DESCRIPTION
    Manages ~/.ssh and ~/.ssh/secrets across P2P mesh devices and Cloudflare KV Vault.
.EXAMPLE
    sm sync
.EXAMPLE
    sm push
.EXAMPLE
    sm pull
.EXAMPLE
    sm diff
#>
function sm {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$false)]
        [string]$Subcommand,

        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        [string[]]$RemainingArgs
    )

    $repoDir = Join-Path $HOME ".local\share\chezmoi"
    $pyScript = Join-Path $HOME ".config\scripts\ssh_vault_core.py"
    if (-not (Test-Path $pyScript)) {
        $pyScript = Join-Path $repoDir "dot_config\scripts\ssh_vault_core.py"
    }

    $cmd = if ($Subcommand) { $Subcommand.ToLower() } else { "" }

    switch ($cmd) {
        { $_ -in @("-h", "--help", "help", "") } {
            Write-Host "== SSH & Secrets Vault Manager (sm) ==" -ForegroundColor Magenta
            Write-Host "Usage: sm <subcommand> [options]" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Subcommands:"
            Write-Host "  sync [<peer>] [-n]  P2P Mesh sync ~/.ssh with peer device(s)"
            Write-Host "  push | send         Encrypt and push local ~/.ssh & secrets to Cloud Vault"
            Write-Host "  pull | get [-v N]   Download, diff and pull Cloud Vault snapshot into local ~/.ssh"
            Write-Host "  diff [t1] [t2]      Compare ~/.ssh between local, cloud snapshots, or peer hosts"
            Write-Host "  status              Quick dirty check of local files against latest Cloud Vault"
            Write-Host "  history             List available snapshot versions stored in Cloud Vault"
            Write-Host "  -h, --help          Show this help message"
            return
        }

        { $_ -in @("sync", "push", "send", "pull", "get", "diff", "status", "history") } {
            if (-not (Test-Path $pyScript)) {
                Write-Error "Backend script not found at: $pyScript"
                return
            }
            $allArgs = @($Subcommand) + $RemainingArgs
            & python3 $pyScript @allArgs
            return
        }

        default {
            Write-Host "Unknown subcommand: '$Subcommand'" -ForegroundColor Red
            Write-Host "Run 'sm --help' for available subcommands."
            return
        }
    }
}
