<#
.SYNOPSIS
    Screen mirroring and remote control for Android devices via scrcpy.
.DESCRIPTION
    Provides clean 'sc' command for launching scrcpy in background mode,
    turning off screen, virtual displays, and interactive app selection via fzf.
.EXAMPLE
    sc
.EXAMPLE
    sc --off
.EXAMPLE
    sc --dex
.EXAMPLE
    sc --apps
#>

function sc {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet("--off", "--dex", "--apps", "-off", "-dex", "-apps", "off", "dex", "apps", "help", "--help", "-h")]
        [string]$Mode = "default",

        [Alias("f")]
        [switch]$Stay,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ExtraArgs
    )

    if (-not (Get-Command scrcpy -ErrorAction SilentlyContinue)) {
        Write-Error "✘ scrcpy is not installed or not in PATH."
        return
    }

    if ($Mode -in @("help", "--help", "-h")) {
        Get-Help sc
        return
    }

    $argList = [System.Collections.Generic.List[string]]::new()

    switch ($Mode) {
        { $_ -in @("--apps", "-apps", "apps") } {
            if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
                & scrcpy --list-apps @ExtraArgs
                return
            }

            Write-Host "Fetching installed applications from device..." -ForegroundColor DarkGray
            $rawApps = & scrcpy --list-apps 2>$null | Where-Object { $_ -match '^\s*[\*\-]\s+' }
            if (-not $rawApps) {
                Write-Error "✘ Failed to retrieve applications or no device connected."
                return
            }

            $selected = $rawApps | fzf --height=40% --reverse --prompt="📱 Select App > " --header="Choose an app to launch with scrcpy"
            if ([string]::IsNullOrWhiteSpace($selected)) {
                return
            }

            $pkg = ($selected.Trim() -split '\s+')[-1]
            if ([string]::IsNullOrWhiteSpace($pkg)) {
                Write-Error "✘ Could not determine package name."
                return
            }

            $cleanTitle = ($selected -replace '^\s*[\*\-]\s+', '') -replace '\s+\S+$', ''
            $cleanTitle = $cleanTitle.Trim()
            if ([string]::IsNullOrWhiteSpace($cleanTitle)) {
                $cleanTitle = $pkg
            }

            Write-Host "🚀 Launching $cleanTitle ($pkg)..." -ForegroundColor Green
            $argList.Add("--new-display")
            $argList.Add("--start-app=$pkg")
            $argList.Add("--window-title=`"$cleanTitle`"")
        }
        { $_ -in @("--off", "-off", "off") } {
            $argList.Add("--turn-screen-off")
        }
        { $_ -in @("--dex", "-dex", "dex") } {
            $argList.Add("--new-display=1920x1080/284")
            $argList.Add("--turn-screen-off")
        }
    }

    if ($ExtraArgs) {
        foreach ($extra in $ExtraArgs) {
            $argList.Add($extra)
        }
    }

    if ($Stay) {
        & scrcpy $argList
    } else {
        Start-Process scrcpy -ArgumentList $argList -WindowStyle Hidden
        Write-Host "✔ scrcpy started in background." -ForegroundColor Green
    }
}
