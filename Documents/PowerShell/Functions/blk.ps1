<#
.SYNOPSIS
    Interactive BitLocker volume locker.
.DESCRIPTION
    Lists all BitLocker encrypted volumes, identifies unlocked drives,
    and prompts for the drive letter to immediately lock (via manage-bde).
    Requires administrative privileges.
.EXAMPLE
    blk
#>
function blk {
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
