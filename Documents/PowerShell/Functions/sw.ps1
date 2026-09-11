<#
.SYNOPSIS
    Interactive Cisco Telnet selector with fzf picker and automated login.
.DESCRIPTION
    Reads switch inventory & credentials directly from ~/.ssh/config,
    lets you fuzzy-pick a switch with fzf (or Out-ConsoleGridView), then
    opens an interactive Telnet session with automated login via a native
    .NET TCP socket handler (no third-party binaries or putty needed).
.PARAMETER Target
    Switch NAME (case-insensitive) or IP from the inventory.
    Omit to open the interactive picker.
.EXAMPLE
    sw
.EXAMPLE
    sw IT-MIZ
.EXAMPLE
    sw 192.168.30.13
#>
function Connect-CiscoSwitch {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $sshConfigFile = Join-Path $HOME ".ssh\config"
            $items = @()

            if (Test-Path $sshConfigFile) {
                Get-Content $sshConfigFile | Where-Object { $_ -match '^#\s*@switch\s+' } | ForEach-Object {
                    $raw = ($_ -replace '^#\s*@switch\s+', '').Trim()
                    if ($raw -match '\|') {
                        $p = $raw -split '\|'
                        $ip = $p[0].Trim()
                        $name = $p[1].Trim()
                        $desc = if ($p.Count -gt 2) { $p[2].Trim() } else { '' }
                        $items += [PSCustomObject]@{ IP = $ip; Name = $name; Desc = $desc }
                    } else {
                        $p = $raw -split '\s+'
                        $ip = $p[0].Trim()
                        $name = $p[1].Trim()
                        $desc = if ($p.Count -gt 2) { ($p[2..($p.Count - 1)] -join ' ') } else { '' }
                        $items += [PSCustomObject]@{ IP = $ip; Name = $name; Desc = $desc }
                    }
                }
            }

            foreach ($it in $items) {
                if ($it.Name -like "$wordToComplete*") {
                    [System.Management.Automation.CompletionResult]::new($it.Name, $it.Name, 'ParameterValue', "$($it.IP) - $($it.Desc)")
                }
                if ($it.IP -like "$wordToComplete*") {
                    [System.Management.Automation.CompletionResult]::new($it.IP, $it.IP, 'ParameterValue', "$($it.Name) - $($it.Desc)")
                }
            }
        })]
        [string]$Target
    )

    $scriptPath = Join-Path $HOME ".config\scripts\sw.py"
    if (-not (Test-Path $scriptPath)) {
        # Fallback to linux-style path if HOME is configured differently
        $scriptPath = "$HOME/.config/scripts/sw.py"
    }

    $python = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }
    if ($Target) {
        & $python $scriptPath $Target
    } else {
        & $python $scriptPath
    }
}

Set-Alias -Name sw -Value Connect-CiscoSwitch
