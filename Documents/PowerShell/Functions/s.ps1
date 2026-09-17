<#
.SYNOPSIS
    Fast, ergonomic SSH, tunnels and command runner powered by devices.toml & OpenSSH
.DESCRIPTION
    Wraps SSH execution using the unified python backend (~/.config/scripts/mesh_core.py)
    to query routes, tunnels, and named commands from ~/.ssh/devices.toml.
.PARAMETER Target
    The device name, switch IP, or host defined in ~/.ssh/devices.toml.
.PARAMETER Action
    Optional tunnel name (rdp, vnc), named command (reboot, shutdown), or port.
.EXAMPLE
    s work rdp
.EXAMPLE
    s work reboot
.EXAMPLE
    s it-miz
#>
function s {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$false)]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $pyScript = Join-Path $HOME ".config\scripts\mesh_core.py"
            if (-not (Test-Path $pyScript)) {
                $pyScript = Join-Path $HOME ".local\share\chezmoi\dot_config\scripts\mesh_core.py"
            }
            if (Test-Path $pyScript) {
                & python $pyScript complete targets | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
            }
        })]
        [string]$Target,

        [Parameter(Position=1, Mandatory=$false)]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $tVal = $fakeBoundParameters['Target']
            if (-not $tVal -and $commandAst -and $commandAst.CommandElements.Count -gt 1) {
                $tVal = $commandAst.CommandElements[1].Extent.Text.Trim('"', "'")
            }
            if (-not $tVal) { return }
            $pyScript = Join-Path $HOME ".config\scripts\mesh_core.py"
            if (-not (Test-Path $pyScript)) {
                $pyScript = Join-Path $HOME ".local\share\chezmoi\dot_config\scripts\mesh_core.py"
            }
            if (Test-Path $pyScript) {
                & python $pyScript complete actions $tVal | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
            }
        })]
        [string]$Action,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$ExtraArgs
    )

    $pyScript = Join-Path $HOME ".config\scripts\mesh_core.py"
    if (-not (Test-Path $pyScript)) {
        $pyScript = Join-Path $HOME ".local\share\chezmoi\dot_config\scripts\mesh_core.py"
    }

    # Interactive 2-step picker if target is empty
    if ([string]::IsNullOrWhiteSpace($Target)) {
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            while ($true) {
                $selectedNode = & python $pyScript list-nodes | fzf --height=70% --reverse --prompt="Select Node > " --header="[Enter: Select] [Esc: Cancel]" --preview="python $pyScript preview {1}" --preview-window="right:55%:border-left:wrap"
                if (-not $selectedNode) { return }
                $Target = (($selectedNode -split '│')[0]).Trim()

                $actionList = & python $pyScript list-actions $Target
                if ($actionList.Count -le 1) {
                    $Action = ""
                    break
                }

                $selectedAction = $actionList | fzf --height=60% --reverse --prompt="$Target Action > " --header="[Enter: Run] [Esc: Back to Nodes]"
                if (-not $selectedAction) {
                    $Target = ""
                    continue
                }

                if ($selectedAction -match '🐚') {
                    $Action = ""
                } else {
                    $raw = ($selectedAction -split '│')[0].Trim()
                    $Action = ($raw -replace '^[^\s]+\s+').Trim()
                }
                break
            }
        } else {
            & python $pyScript list-nodes
            return
        }
    }

    # Resolve target and action via mesh_core.py
    $resolveArgs = @($pyScript, "resolve", $Target)
    if ($Action) { $resolveArgs += $Action }
    if ($ExtraArgs) { $resolveArgs += $ExtraArgs }

    $jsonStr = & python $resolveArgs 2>$null
    if (-not $jsonStr) {
        & ssh $Target $Action $ExtraArgs
        return
    }

    $res = $jsonStr | ConvertFrom-Json
    $bestRoute = if ($res.route) { $res.route } else { $Target }
    $actType = if ($res.action_type) { $res.action_type } else { "" }
    $sshArgs = if ($res.ssh_args) { @($res.ssh_args) } else { @() }

    # Launch RDP/VNC clients if applicable on Windows
    if ($actType -like "tunnel:rdp*") {
        Write-Host "🖥️  [RDP Tunnel] Connecting via ${bestRoute} (127.0.0.1:3390)..." -ForegroundColor Cyan
        if (Get-Command mstsc.exe -ErrorAction SilentlyContinue) {
            Start-Process mstsc.exe -ArgumentList "/v:127.0.0.1:3390"
        }
    } elseif ($actType -like "tunnel:vnc*") {
        Write-Host "🖼️  [VNC Tunnel] Connecting via ${bestRoute} (127.0.0.1:5901)..." -ForegroundColor Cyan
        $vnc = Get-Command "vncviewer.exe", "TigerVNC.exe", "RealVNC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($vnc) {
            Start-Process $vnc.Source -ArgumentList "127.0.0.1:5901"
        }
    } elseif ($actType -like "command:*") {
        Write-Host "⚡ [Executing] on ${bestRoute}: $($sshArgs -join ' ')" -ForegroundColor Yellow
    } else {
        Write-Host "🚀 [Connecting] -> $bestRoute" -ForegroundColor Green
    }

    # Direct OpenSSH execution
    & ssh $bestRoute $sshArgs
}
