<#
.SYNOPSIS
    Visual live-vs-repo side-by-side diff editor for chezmoi managed files.

.DESCRIPTION
    Opens the actual live file (system) and source file (repo) side-by-side in your editor.
    Any changes saved to either side directly modify the real files (no temp files).
    If no target is given, presents an interactive fzf picker of modified files.

.PARAMETER Target
    File path or partial name of the chezmoi managed file.

.PARAMETER Editor
    Diff editor command to use (default: nvim).

.PARAMETER Reverse
    If specified, puts repo on the left and system on the right.

.PARAMETER Help
    Show usage and help documentation.

.EXAMPLE
    cdiff
    cdiff settings.json
    cdiff ~/.config/fish/config.fish
    cdiff -r
    cdiff -e code
#>
function cdiff {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [string]$Target,

        [Alias("e")]
        [Parameter()]
        [string]$Editor,

        [Alias("r")]
        [switch]$Reverse,

        [Alias("h")]
        [switch]$Help
    )

    # Help documentation
    if ($Help) {
        Write-Host "Usage: cdiff [options] [target]`n" -ForegroundColor Cyan
        Write-Host "Visual live-vs-repo side-by-side diff editor for chezmoi managed files."
        Write-Host "Opens the actual live file (system) and source file (repo) side-by-side.`n"
        Write-Host "Arguments:" -ForegroundColor Yellow
        Write-Host "  target                File path or name of the chezmoi managed file."
        Write-Host "                        If omitted, an interactive picker (fzf) of modified files is shown.`n"
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -e, --editor <cmd>    Diff editor to use (default: nvim)"
        Write-Host "  -r, --reverse         Reverse diff sides (repo on left, live system on right)"
        Write-Host "  -h, --help            Show this help message and exit`n"
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  cdiff"
        Write-Host "  cdiff settings.json"
        Write-Host "  cdiff ~/.config/fish/config.fish"
        Write-Host "  cdiff -r"
        Write-Host "  cdiff -e code"
        return
    }

    # 1. Determine editor command (strictly nvim by default, or custom with -Editor)
    if ($Editor) {
        $editorParts = $Editor -split '\s+'
        $editorBinary = $editorParts[0]
        if (-not (Get-Command $editorBinary -ErrorAction SilentlyContinue)) {
            Write-Error "Editor binary '$editorBinary' was not found in PATH."
            return
        }
        $selectedEditor = $Editor
    }
    else {
        $selectedEditor = "nvim"
    }

    # 2. If no target specified, inspect chezmoi status
    if ([string]::IsNullOrWhiteSpace($Target)) {
        $statusLines = chezmoi status
        if (-not $statusLines) {
            Write-Host "✓ No differences between live system and chezmoi repo." -ForegroundColor Green
            return
        }

        # Ensure $modifiedFiles is always an array
        $modifiedFiles = @($statusLines | ForEach-Object {
            $line = $_.Trim()
            $line -replace '^\S+\s+', ''
        } | Where-Object { [bool]$_ })

        if ($modifiedFiles.Count -eq 0) {
            Write-Host "✓ No modified files found." -ForegroundColor Green
            return
        }

        if ($modifiedFiles.Count -eq 1) {
            $Target = $modifiedFiles[0]
            Write-Host "Opening: $Target" -ForegroundColor Cyan
        }
        elseif (Get-Command fzf -ErrorAction SilentlyContinue) {
            $selected = $modifiedFiles | fzf --prompt="Select file to diff (chezmoi) > " --height=40% --reverse
            if (-not $selected) { return }
            $Target = $selected.Trim()
        }
        else {
            Write-Host "Multiple modified files found:" -ForegroundColor Yellow
            $modifiedFiles | ForEach-Object { Write-Host "  - $_" }
            Write-Host "`nUsage: cdiff [options] [target]" -ForegroundColor Cyan
            return
        }
    }

    # 3. Resolve destination (live system) and source (repo) paths
    try {
        $rawDest = chezmoi target-path "$Target" 2>$null
        $dest = if ($rawDest) { $rawDest.Trim() } else { $null }

        $rawSrc = chezmoi source-path "$Target" 2>$null
        if (-not $rawSrc -and $dest) {
            $rawSrc = chezmoi source-path "$dest" 2>$null
        }
        $src = if ($rawSrc) { $rawSrc.Trim() } else { $null }
    }
    catch {
        $dest = $null
        $src = $null
    }

    # If src not found, try relative to HOME (e.g. from chezmoi status: .config/...)
    if (-not $src) {
        $homePath = Join-Path $HOME $Target
        $rawSrc = chezmoi source-path "$homePath" 2>$null
        if ($rawSrc) {
            $src = $rawSrc.Trim()
            if (-not $dest) { $dest = $homePath }
        }
    }

    # If dest not found, but src was found, resolve target from src
    if (-not $dest -and $src) {
        $rawDest = chezmoi target-path "$src" 2>$null
        if ($rawDest) { $dest = $rawDest.Trim() }
    }

    # If src not found, but dest was found, resolve source from dest
    if (-not $src -and $dest) {
        $rawSrc = chezmoi source-path "$dest" 2>$null
        if ($rawSrc) { $src = $rawSrc.Trim() }
    }

    # Fallback for local files in current working directory
    if ((-not $src -or -not (Test-Path -LiteralPath $src)) -and (Test-Path -LiteralPath $Target)) {
        $candidate = (Resolve-Path -LiteralPath $Target -ErrorAction SilentlyContinue).Path
        if ($candidate) {
            $dest = $candidate
            $rawSrc = chezmoi source-path "$dest" 2>$null
            if ($rawSrc) { $src = $rawSrc.Trim() }
        }
    }

    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        Write-Error "Could not resolve chezmoi source path for '$Target'. Is this file managed by chezmoi?"
        return
    }

    Write-Host "Live (System): " -NoNewline -ForegroundColor Gray
    Write-Host $dest -ForegroundColor Yellow
    Write-Host "Repo (Source): " -NoNewline -ForegroundColor Gray
    Write-Host $src -ForegroundColor Cyan

    # 4. Open in editor (default: Left=Live, Right=Repo; Reverse: Left=Repo, Right=Live)
    $left = if ($Reverse) { $src } else { $dest }
    $right = if ($Reverse) { $dest } else { $src }

    $editorParts = $selectedEditor -split '\s+'
    $editorBin = $editorParts[0]
    $editorArgs = if ($editorParts.Count -gt 1) { $editorParts[1..($editorParts.Count - 1)] } else { @() }

    if ($editorBin -in @("code", "agy", "cursor")) {
        & $editorBin @editorArgs --diff "$left" "$right"
    }
    elseif ($editorBin -in @("nvim", "vim")) {
        & $editorBin @editorArgs -d "$left" "$right"
    }
    else {
        & $editorBin @editorArgs "$left" "$right"
    }
}
