<#
.SYNOPSIS
    Fast GeoIP & Public IP Checker (Proxy & Direct / No-Proxy).
.DESCRIPTION
    Runs the multi-service concurrent IP checker script with GeoIP details,
    supporting proxy, direct connection, and raw output modes.
.EXAMPLE
    ipl
.EXAMPLE
    ipl -p
.EXAMPLE
    ipl -d
.EXAMPLE
    ipl -r
#>
function ipl {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ScriptArgs
    )

    $scriptPath = "$HOME\.config\scripts\ipl"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        $scriptPath = "$HOME\.local\share\chezmoi\dot_config\scripts\executable_ipl"
    }

    $pythonExe = Get-Command python, py -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
    if (-not $pythonExe) {
        Write-Error "ipl: Python is required to run the IP checker script but was not found in PATH."
        return
    }

    & $pythonExe $scriptPath @ScriptArgs
}
