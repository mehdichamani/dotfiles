# $env:POWERSHELL_UPDATECHECK = 'Off'

# 1. Gather session data
$ParentProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
$ParentName = (Get-Process -Id $ParentProcess.ParentProcessId).Name
$CommandLine = $ParentProcess.CommandLine

# 2. DEFINE THE "SILENCE" CONDITION
# We stay silent if the command contains 'sftp-server' or the parent is 'sshd'
$IsScpSession = ($CommandLine -match "sftp-server") -or ($ParentName -eq "sshd")

if (-not $IsScpSession) {
    # LOAD EVERYTHING (Interactive/Human Sessions)
    
    # Load custom functions and aliases
    if (Test-Path "$PSScriptRoot\pwsh.ps1") {
        . "$PSScriptRoot\pwsh.ps1"
    }
} else {
    # LOAD NOTHING (SCP/SFTP Sessions)
    # Keeping this block empty ensures no output is sent to scp
}