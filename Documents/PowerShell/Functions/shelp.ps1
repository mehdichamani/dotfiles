<#
.SYNOPSIS
    Display cheatsheet of custom PowerShell functions and tools.
.DESCRIPTION
    Scans the custom Functions directory and outputs all functions with their
    synopsis or summary comment, with optional keyword filtering.
.PARAMETER Filter
    Keyword or search term to filter functions and descriptions.
.EXAMPLE
    shelp
.EXAMPLE
    shelp vlan
.EXAMPLE
    shelp proxy
#>
function shelp {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $false)]
        [string]$Filter
    )

    Write-Host "`n🛠️  Custom PowerShell Functions & Tools" -ForegroundColor Magenta
    if (-not [string]::IsNullOrWhiteSpace($Filter)) {
        Write-Host "Filtering by: '$Filter'" -ForegroundColor DarkGray
    }
    Write-Host "────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    # Determine Functions directory path
    $possibleDirs = @(
        (Join-Path $PSScriptRoot "..\Functions"),
        (Join-Path $HOME "Documents\PowerShell\Functions"),
        (Join-Path $HOME ".local\share\chezmoi\Documents\PowerShell\Functions")
    )

    $foundFiles = @()
    foreach ($dir in $possibleDirs) {
        if (Test-Path $dir) {
            $foundFiles = Get-ChildItem -Path $dir -Filter "*.ps1" -ErrorAction SilentlyContinue
            if ($foundFiles.Count -gt 0) { break }
        }
    }

    $seen = @{}

    foreach ($file in $foundFiles) {
        $fname = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        if ($seen.ContainsKey($fname)) { continue }
        $seen[$fname] = $true

        $content = Get-Content -Path $file.FullName -Raw
        $synopsis = ""

        # 1. Parse .SYNOPSIS from comment-based help block
        if ($content -match '(?ms)\.SYNOPSIS\s*\r?\n\s*(.*?)(?=\r?\n\s*\.[A-Z]+|\r?\n\s*#>)') {
            $synopsis = $Matches[1].Trim() -replace '\r?\n\s*', ' '
        }

        # 2. Fallback to first line comment
        if ([string]::IsNullOrWhiteSpace($synopsis)) {
            $firstLine = (Get-Content -Path $file.FullName -TotalCount 5) | Where-Object { $_ -match '^\s*#\s*(.+)' } | Select-Object -First 1
            if ($firstLine -match '^\s*#\s*(.+)') {
                $synopsis = $Matches[1].Trim()
            }
        }

        # Apply search filter if specified
        if (-not [string]::IsNullOrWhiteSpace($Filter)) {
            $matchTarget = "$fname $synopsis"
            if ($matchTarget -notmatch [regex]::Escape($Filter)) {
                continue
            }
        }

        $paddedName = $fname.PadRight(14)
        Write-Host "  $paddedName " -NoNewline -ForegroundColor Cyan
        Write-Host "$synopsis" -ForegroundColor White
    }

    Write-Host "────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "Tip: Run 'shelp <search>' to filter (e.g. shelp net, shelp git)`n" -ForegroundColor DarkGray
}
