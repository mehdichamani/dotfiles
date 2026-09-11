<#
.SYNOPSIS
    Edit system or user environment PATH in default editor or VS Code.
.DESCRIPTION
    Opens the current PATH registry entries in a temporary file,
    waits for edits and save, and automatically writes back the updated PATH to the registry.
.PARAMETER Target
    The environment scope to edit: 'User' (default) or 'Machine' (requires Admin).
.PARAMETER VsCode
    Open in VS Code (--vscode) instead of the default editor.
.EXAMPLE
    epath
.EXAMPLE
    epath --vscode
.EXAMPLE
    epath -Target Machine --vscode
.EXAMPLE
    epath Machine --vscode
#>
function epath {
    [CmdletBinding(PositionalBinding = $false)]
    param (
        [ValidateSet('User', 'Machine')]
        [string]$Target = 'User',

        [Alias('code', 'c')]
        [switch]$VsCode,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$RemainingArgs
    )

    # Handle flexible argument styles (--vscode, -vscode, Machine/User positional)
    $isVsCode = [bool]($VsCode -or ($RemainingArgs -and ($RemainingArgs -contains '--vscode' -or $RemainingArgs -contains '-vscode' -or $RemainingArgs -contains '--code' -or $RemainingArgs -contains '-code')))

    if ($RemainingArgs) {
        if ($RemainingArgs -contains 'Machine' -or $RemainingArgs -contains '-Machine') {
            $Target = 'Machine'
        }
        elseif ($RemainingArgs -contains 'User' -or $RemainingArgs -contains '-User') {
            $Target = 'User'
        }
    }

    # 1. Get the current PATH from the registry based on target
    $RegistryTarget = if ($Target -eq 'User') { [EnvironmentVariableTarget]::User } else { [EnvironmentVariableTarget]::Machine }
    $CurrentPath = [Environment]::GetEnvironmentVariable('Path', $RegistryTarget)

    if ([string]::IsNullOrEmpty($CurrentPath)) {
        Write-Error "Could not retrieve the $Target PATH variable."
        return
    }

    # 2. Split paths by the system delimiter (;) and create a temporary file
    $PathLines = $CurrentPath -split ';' | Where-Object { $_ -ne "" }
    $TempFile = [System.IO.Path]::GetTempFileName() + ".txt"
    $PathLines | Out-File -FilePath $TempFile -Encoding utf8

    # 3. Open in VS Code or Default Editor and WAIT
    if ($isVsCode) {
        if (Get-Command code -ErrorAction SilentlyContinue) {
            Write-Host "Opening $Target PATH in VS Code. Please edit, save, and close the file to apply changes..." -ForegroundColor Cyan
            Start-Process -FilePath "code" -ArgumentList "--wait", "`"$TempFile`"" -NoNewWindow -Wait
        }
        else {
            Write-Error "VS Code ('code') was not found in PATH."
            Remove-Item $TempFile -Force -ErrorAction SilentlyContinue
            return
        }
    }
    else {
        # Determine default editor: $env:EDITOR, $env:VISUAL, nvim, or fallback to notepad
        $editor = if ($env:EDITOR) {
            $env:EDITOR
        }
        elseif ($env:VISUAL) {
            $env:VISUAL
        }
        elseif (Get-Command nvim -ErrorAction SilentlyContinue) {
            "nvim"
        }
        else {
            "notepad"
        }

        Write-Host "Opening $Target PATH in default editor ($editor). Please edit, save, and close the file to apply changes..." -ForegroundColor Cyan

        if ($editor -match '^(code|code\.cmd|code\.exe)$') {
            Start-Process -FilePath "code" -ArgumentList "--wait", "`"$TempFile`"" -NoNewWindow -Wait
        }
        elseif ($editor -match '^(nvim|vim|vi|nano|micro)$' -and (Get-Command $editor -ErrorAction SilentlyContinue)) {
            & $editor $TempFile
        }
        else {
            Start-Process -FilePath $editor -ArgumentList "`"$TempFile`"" -Wait
        }
    }

    # 4. Read the modified file
    if (Test-Path $TempFile) {
        $NewLines = Get-Content -Path $TempFile | Where-Object { $_ -notmatch '^\s*$' }
        $NewPath = $NewLines -join ';'

        # Clean up the temp file
        Remove-Item $TempFile -Force

        # 5. Save the updated PATH back to the environment
        try {
            [Environment]::SetEnvironmentVariable('Path', $NewPath, $RegistryTarget)
            Write-Host "Successfully updated $Target PATH!" -ForegroundColor Green
            Write-Host "Note: You may need to restart your terminal/apps to see the changes." -ForegroundColor Yellow
        }
        catch {
            Write-Error "Failed to save PATH. If editing 'Machine' target, ensure you ran PowerShell as Administrator.`nDetails: $_"
        }
    }
    else {
        Write-Error "Temporary file was lost. No changes were applied."
    }
}
