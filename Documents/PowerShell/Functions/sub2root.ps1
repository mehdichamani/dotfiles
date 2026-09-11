<#
.SYNOPSIS
    Flatten directory by moving files from all subfolders to current root.
.DESCRIPTION
    Recursively finds all files inside subdirectories, moves them into the current
    working directory, and prompts to clean up empty leftover directories.
.EXAMPLE
    sub2root
#>
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
