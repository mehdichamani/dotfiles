<#
.SYNOPSIS
    Interactive cleanup of non-default git branches.
.DESCRIPTION
    Fetches and prunes remotes, detects default branch (main/master) and current branch,
    previews all non-default local and tracking remote branches, and asks for confirmation to delete.
.EXAMPLE
    gcb
#>
function gcb {
    # Ensure we are inside a Git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Error "Error: Not a git repository."
        return
    }

    # Fetch latest remote refs and prune deleted remotes
    git fetch --prune

    # Detect default branch (e.g., main or master)
    $defaultBranch = (git symbolic-ref refs/remotes/origin/HEAD 2>$null) -replace 'refs/remotes/origin/', ''
    if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
        if (git show-ref --verify --quiet refs/heads/main) { $defaultBranch = "main" }
        elseif (git show-ref --verify --quiet refs/heads/master) { $defaultBranch = "master" }
    }

    $currentBranch = (git branch --show-current).Trim()

    # Collect local branches to delete (excluding default and current)
    $allLocal = git for-each-ref --format='%(refname:lstrip=2)' refs/heads/
    $localToDelete = @()
    $remoteToDelete = @()

    foreach ($b in $allLocal) {
        $b = $b.Trim()
        if ($b -and $b -ne $defaultBranch -and $b -ne $currentBranch) {
            $localToDelete += $b
            git rev-parse --verify "refs/remotes/origin/$b" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $remoteToDelete += $b
            }
        }
    }

    if ($localToDelete.Count -eq 0) {
        Write-Host "No extra branches to delete. (Keeping: '$defaultBranch' and '$currentBranch')" -ForegroundColor Green
        return
    }

    # Display preview
    Write-Host "Default branch : " -NoNewline; Write-Host $defaultBranch -ForegroundColor Cyan
    Write-Host "Current branch : " -NoNewline; Write-Host $currentBranch -ForegroundColor Cyan
    Write-Host "`nLocal branches to be DELETED:" -ForegroundColor Yellow
    $localToDelete | ForEach-Object { Write-Host "  - $_" }

    if ($remoteToDelete.Count -gt 0) {
        Write-Host "`nRemote branches to be DELETED from origin:" -ForegroundColor Red
        $remoteToDelete | ForEach-Object { Write-Host "  - origin/$_" }
    }

    Write-Host ""
    $confirmation = Read-Host "Are you sure you want to delete these branches locally and remotely? [y/N]"

    if ($confirmation -match '^[yY]$') {
        Write-Host "`nDeleting local branches..." -ForegroundColor Yellow
        foreach ($b in $localToDelete) {
            git branch -D $b
        }

        if ($remoteToDelete.Count -gt 0) {
            Write-Host "`nDeleting remote branches..." -ForegroundColor Red
            foreach ($b in $remoteToDelete) {
                git push origin --delete $b
            }
        }
        Write-Host "`nCleaned up successfully!" -ForegroundColor Green
    } else {
        Write-Host "Operation cancelled." -ForegroundColor Gray
    }
}
