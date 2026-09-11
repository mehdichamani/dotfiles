<#
.SYNOPSIS
    Transparent wrapper routing pip and pip3 commands to uv pip.
.DESCRIPTION
    Provides fast, uv-backed package management for Windows / PowerShell 7.
#>

function pip {
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        if ($args.Count -eq 1 -and ($args[0] -eq '-V' -or $args[0] -eq '--version')) {
            $uvVer = (uv --version 2>$null) -replace '^uv\s+', ''
            Write-Output "pip 24.0 (uv $uvVer)"
            return
        }
        uv pip @args
    } else {
        $realPip = Get-Command pip.exe -ErrorAction SilentlyContinue
        if ($realPip) {
            & $realPip.Source @args
        } else {
            Write-Error "pip: command not found (neither uv nor pip installed)"
        }
    }
}

function pip3 {
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        if ($args.Count -eq 1 -and ($args[0] -eq '-V' -or $args[0] -eq '--version')) {
            $uvVer = (uv --version 2>$null) -replace '^uv\s+', ''
            Write-Output "pip 24.0 (uv $uvVer)"
            return
        }
        uv pip @args
    } else {
        $realPip = Get-Command pip3.exe, pip.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($realPip) {
            & $realPip.Source @args
        } else {
            Write-Error "pip3: command not found (neither uv nor pip installed)"
        }
    }
}
