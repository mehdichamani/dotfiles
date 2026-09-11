<#
.SYNOPSIS
    Smart SSH, RDP, VNC, and Named Commands manager with multi-route probing from devices.toml.
.DESCRIPTION
    Tests network reachability for routes defined in ~/.ssh/devices.toml 
    and connects to the fastest available route (LAN or WAN fallback).
    Supports pre-configured named commands (e.g. s 2011 wake-workpc, s work reboot)
    and special tunnel modes (-rdp, -vnc, -jellyfin, -L).
.PARAMETER Target
    The SSH node name or direct host defined in ~/.ssh/devices.toml.
.PARAMETER CommandName
    Optional named command to execute on remote target.
.PARAMETER Rdp
    Forward local port 3390 to target 3389 and launch Remote Desktop.
.PARAMETER Vnc
    Forward local port 5901 to target 5900 and establish VNC tunnel.
.PARAMETER ListCommands
    List all pre-configured named commands for the target.
.PARAMETER ExtraArgs
    Any additional arguments passed directly to the ssh executable.
.EXAMPLE
    s home
.EXAMPLE
    s 2011 wake-workpc
.EXAMPLE
    s work reboot
.EXAMPLE
    s work -rdp
.EXAMPLE
    s 2011 -Commands
#>
function s {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$false)]
        [string]$Target,
        [Parameter(Position=1, Mandatory=$false)]
        [string]$CommandName,
        [Parameter(Mandatory=$false)]
        [switch]$Rdp,
        [Parameter(Mandatory=$false)]
        [switch]$Vnc,
        [Parameter(Mandatory=$false)]
        [switch]$Jellyfin,
        [Parameter(Mandatory=$false)]
        [Alias("L")]
        [string]$Port,
        [Parameter(Mandatory=$false)]
        [Alias("l", "Commands")]
        [switch]$ListCommands,
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$ExtraArgs
    )

    $allTokens = @()
    if ($Target) { $allTokens += $Target }
    if ($CommandName) { $allTokens += $CommandName }
    if ($ExtraArgs) { $allTokens += $ExtraArgs }

    $isRdp = $Rdp.IsPresent
    $isVnc = $Vnc.IsPresent
    $isJellyfin = $Jellyfin.IsPresent
    $showCommands = $ListCommands.IsPresent
    $forwardSpec = $Port
    $cleanTokens = @()

    $i = 0
    while ($i -lt $allTokens.Count) {
        $tok = $allTokens[$i]
        if ($tok -in @("-rdp", "--rdp", "/rdp")) {
            $isRdp = $true
        } elseif ($tok -in @("-vnc", "--vnc", "/vnc")) {
            $isVnc = $true
        } elseif ($tok -in @("-jellyfin", "--jellyfin", "/jellyfin")) {
            $isJellyfin = $true
        } elseif ($tok -in @("-l", "--commands", "-commands", "/commands")) {
            $showCommands = $true
        } elseif ($tok -in @("-L", "--port", "-p", "/L")) {
            if ($i + 1 -lt $allTokens.Count) {
                $i++
                $forwardSpec = $allTokens[$i]
            }
        } elseif ($tok -match '^-[Ll](.+)$') {
            $forwardSpec = $Matches[1]
        } else {
            $cleanTokens += $tok
        }
        $i++
    }

    $actualTarget = if ($cleanTokens.Count -gt 0) { $cleanTokens[0] } else { "" }
    $actualExtraArgs = if ($cleanTokens.Count -gt 1) { $cleanTokens[1..($cleanTokens.Count - 1)] } else { @() }

    $devicesToml = Join-Path $HOME ".ssh\devices.toml"
    if (-not (Test-Path $devicesToml)) {
        $chezToml = Join-Path $HOME ".local\share\chezmoi\dot_ssh\devices.toml"
        if (Test-Path $chezToml) { $devicesToml = $chezToml }
    }

    # Helper TOML Parser for PowerShell
    $nodes = @{}
    if (Test-Path $devicesToml) {
        $curNode = ""
        $inCommands = $false
        Get-Content $devicesToml | ForEach-Object {
            $line = $_.Trim()
            if ($line -match '^\[ssh\.([^\]]+)\.commands\]') {
                $curNode = $Matches[1].ToLower()
                $inCommands = $true
                if (-not $nodes.ContainsKey($curNode)) { $nodes[$curNode] = @{ Routes = @(); Commands = @{} } }
            } elseif ($line -match '^\[ssh\.([^\]]+)\]') {
                $curNode = $Matches[1].ToLower()
                $inCommands = $false
                if (-not $nodes.ContainsKey($curNode)) { $nodes[$curNode] = @{ Routes = @(); Commands = @{} } }
            } elseif ($line -match '^\[') {
                $inCommands = $false
                $curNode = ""
            } elseif ($curNode) {
                if ($inCommands -and ($line -match '^([a-zA-Z0-9_-]+)\s*=\s*["''](.*)["'']')) {
                    $nodes[$curNode].Commands[$Matches[1]] = $Matches[2]
                } elseif (-not $inCommands -and ($line -match '^routes\s*=\s*\[(.*)\]')) {
                    $rawList = $Matches[1]
                    $nodes[$curNode].Routes = ($rawList -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") })
                } elseif (-not $inCommands -and ($line -match '^name\s*=\s*["''](.*)["'']')) {
                    $nodes[$curNode].Name = $Matches[1]
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($actualTarget)) {
        Write-Host "Usage: s <target> [-rdp | -vnc | -jellyfin | -L <port_or_spec>] [<named_command> | extra_args...]" -ForegroundColor Yellow
        Write-Host "       s <target> <named_command>       (e.g. s 2011 wake-workpc, s work reboot)"
        Write-Host "       s <target> -Commands             (List all defined commands for target)"
        Write-Host "       s -rdp <target>"
        Write-Host "       s -vnc <target>"
        Write-Host "       s -jellyfin <target>"
        Write-Host "       s -L 8096 <target>"
        Write-Host "`nModes & Presets:" -ForegroundColor Cyan
        Write-Host "  -rdp, --rdp            Establish tunnel & launch RDP (port 3390 -> localhost:3389)"
        Write-Host "  -vnc, --vnc            Establish tunnel & launch VNC (port 5901 -> localhost:5900)"
        Write-Host "  -jellyfin, --jellyfin  Establish tunnel for Jellyfin (port 8096 -> localhost:8096)"
        Write-Host "  -L, --port <spec>      Forward port (e.g. 8080, 8080:3000, 8080:localhost:8080)"
        Write-Host "  -l, -Commands          List pre-configured named commands for target"
        Write-Host "`n💡 Tip: For Cisco Switch Telnet connections, use 'sw' (inventory: `$HOME\.ssh\devices.toml)" -ForegroundColor DarkCyan
        Write-Host "`nAvailable SSH Nodes & Routes in ~/.ssh/devices.toml:"
        foreach ($k in $nodes.Keys) {
            $n = $nodes[$k]
            $cmdList = ($n.Commands.Keys -join ', ')
            $cmdStr = if ($cmdList) { " [cmds: $cmdList]" } else { "" }
            Write-Host "  Node: $($k.PadRight(12)) " -NoNewline -ForegroundColor Cyan
            Write-Host "($($n.Name))$cmdStr" -ForegroundColor DarkGray
            foreach ($r in $n.Routes) {
                Write-Host "    - $r" -ForegroundColor White
            }
        }
        return
    }

    $tLower = $actualTarget.ToLower()

    # Handle -Commands
    if ($showCommands) {
        if ($nodes.ContainsKey($tLower) -and $nodes[$tLower].Commands.Count -gt 0) {
            Write-Host "📋 Commands for $($nodes[$tLower].Name):" -ForegroundColor Cyan
            foreach ($cmdKey in $nodes[$tLower].Commands.Keys) {
                Write-Host "  - $($cmdKey.PadRight(16)) : $($nodes[$tLower].Commands[$cmdKey])" -ForegroundColor Green
            }
        } else {
            Write-Host "ℹ️ No named commands defined for target '$actualTarget'." -ForegroundColor DarkGray
        }
        return
    }

    # Check for named command
    $finalCommand = ""
    if ($actualExtraArgs.Count -gt 0 -and $nodes.ContainsKey($tLower)) {
        $potentialCmd = $actualExtraArgs[0]
        if ($nodes[$tLower].Commands.ContainsKey($potentialCmd)) {
            $finalCommand = $nodes[$tLower].Commands[$potentialCmd]
            $actualExtraArgs = if ($actualExtraArgs.Count -gt 1) { $actualExtraArgs[1..($actualExtraArgs.Count - 1)] } else { @() }
        }
    }

    $ConnectAction = {
        param([string]$HostToConnect)

        if ($finalCommand) {
            Write-Host "🚀 [Executing Command] on ${HostToConnect}: $finalCommand" -ForegroundColor Cyan
            & ssh $HostToConnect $finalCommand $actualExtraArgs
            return
        }

        if ($isJellyfin) {
            Write-Host "🍿 [Jellyfin Tunnel] Forwarding local port 8096 to ${HostToConnect}:8096..." -ForegroundColor Magenta
            Write-Host "🌐 Web UI: http://127.0.0.1:8096" -ForegroundColor Green
            Write-Host "🔒 SSH Tunnel is active. Press Ctrl+C to close." -ForegroundColor Yellow
            & ssh -N -L 8096:localhost:8096 $HostToConnect $actualExtraArgs
            return
        } elseif ($forwardSpec) {
            $normSpec = $forwardSpec
            if ($normSpec -match '^\d+$') {
                $normSpec = "$normSpec:localhost:$normSpec"
            } elseif ($normSpec -match '^\d+:\d+$') {
                $p = $normSpec.Split(':')
                $normSpec = "$($p[0]):localhost:$($p[1])"
            }
            $localPort = $normSpec.Split(':')[0]
            Write-Host "🔌 [Port Forward] Local $normSpec via ${HostToConnect}..." -ForegroundColor Cyan
            Write-Host "🌐 Local Address: http://127.0.0.1:$localPort" -ForegroundColor Green
            Write-Host "🔒 SSH Tunnel is active. Press Ctrl+C to close." -ForegroundColor Yellow
            & ssh -N -L $normSpec $HostToConnect $actualExtraArgs
            return
        } elseif ($isRdp) {
            Write-Host "🖥️  [RDP Mode] Forwarding local port 3390 to ${HostToConnect}:3389..." -ForegroundColor Cyan
            if (Get-Command mstsc.exe -ErrorAction SilentlyContinue) {
                $sshJob = Start-Job -ScriptBlock {
                    param($h, $extra)
                    & ssh -N -L 3390:localhost:3389 $h $extra
                } -ArgumentList $HostToConnect, $actualExtraArgs

                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                while ($sw.ElapsedMilliseconds -lt 3000) {
                    if ($sshJob.State -ne 'Running') { break }
                    try {
                        $testTcp = [System.Net.Sockets.TcpClient]::new()
                        $ar = $testTcp.BeginConnect('127.0.0.1', 3390, $null, $null)
                        if ($ar.AsyncWaitHandle.WaitOne(100, $false) -and $testTcp.Connected) {
                            $testTcp.EndConnect($ar)
                            $testTcp.Close()
                            break
                        }
                        $testTcp.Close()
                    } catch {}
                    Start-Sleep -Milliseconds 100
                }

                if ($sshJob.State -ne 'Running') {
                    Write-Host "❌ Failed to establish SSH tunnel." -ForegroundColor Red
                    Receive-Job $sshJob
                    Remove-Job $sshJob -ErrorAction SilentlyContinue
                    return
                }

                Write-Host "🚀 Launching Remote Desktop (mstsc /v:127.0.0.1:3390)..." -ForegroundColor Green
                Start-Process mstsc -ArgumentList "/v:127.0.0.1:3390"
                Write-Host "`n💡 Target Address: 127.0.0.1:3390" -ForegroundColor Yellow
                Write-Host "🔒 SSH Tunnel is active in foreground. Press Ctrl+C to close." -ForegroundColor Green

                try {
                    Wait-Job $sshJob 2>$null
                } finally {
                    Stop-Job $sshJob -ErrorAction SilentlyContinue
                    Remove-Job $sshJob -ErrorAction SilentlyContinue
                }
                return
            } else {
                & ssh -N -L 3390:localhost:3389 $HostToConnect $actualExtraArgs
                return
            }
        } elseif ($isVnc) {
            Write-Host "🖼️  [VNC Mode] Forwarding local port 5901 to ${HostToConnect}:5900..." -ForegroundColor Cyan
            $vncApp = (Get-Command vncviewer.exe, vncviewer, "C:\Program Files\RealVNC\VNC Viewer\vncviewer.exe" -ErrorAction SilentlyContinue | Select-Object -First 1)

            if ($vncApp) {
                $sshJob = Start-Job -ScriptBlock {
                    param($h, $extra)
                    & ssh -N -L 5901:localhost:5900 $h $extra
                } -ArgumentList $HostToConnect, $actualExtraArgs

                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                while ($sw.ElapsedMilliseconds -lt 3000) {
                    if ($sshJob.State -ne 'Running') { break }
                    try {
                        $testTcp = [System.Net.Sockets.TcpClient]::new()
                        $ar = $testTcp.BeginConnect('127.0.0.1', 5901, $null, $null)
                        if ($ar.AsyncWaitHandle.WaitOne(100, $false) -and $testTcp.Connected) {
                            $testTcp.EndConnect($ar)
                            $testTcp.Close()
                            break
                        }
                        $testTcp.Close()
                    } catch {}
                    Start-Sleep -Milliseconds 100
                }

                if ($sshJob.State -ne 'Running') {
                    Write-Host "❌ Failed to establish SSH tunnel." -ForegroundColor Red
                    Receive-Job $sshJob
                    Remove-Job $sshJob -ErrorAction SilentlyContinue
                    return
                }

                Write-Host "🚀 Launching VNC Viewer (127.0.0.1:5901)..." -ForegroundColor Green
                Start-Process $vncApp.Source -ArgumentList "127.0.0.1:5901"
                Write-Host "`n💡 Target Address: 127.0.0.1:5901" -ForegroundColor Yellow
                Write-Host "🔒 SSH Tunnel is active in foreground. Press Ctrl+C to close." -ForegroundColor Green

                try {
                    Wait-Job $sshJob 2>$null
                } finally {
                    Stop-Job $sshJob -ErrorAction SilentlyContinue
                    Remove-Job $sshJob -ErrorAction SilentlyContinue
                }
                return
            } else {
                & ssh -N -L 5901:localhost:5900 $HostToConnect $actualExtraArgs
                return
            }
        } else {
            & ssh $HostToConnect $actualExtraArgs
            return
        }
    }

    $candidates = if ($nodes.ContainsKey($tLower)) { $nodes[$tLower].Routes } else { @() }

    if ($candidates.Count -eq 0) {
        & $ConnectAction $actualTarget
        return
    }

    Write-Host "🔍 Probing target '$actualTarget': $($candidates -join ', ')" -ForegroundColor Cyan

    $asyncSockets = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($h in $candidates) {
        try {
            $tcp = [System.Net.Sockets.TcpClient]::new()
            $ar = $tcp.BeginConnect($h, 22, $null, $null)
            $asyncSockets.Add([PSCustomObject]@{
                HostName    = $h
                TcpClient   = $tcp
                AsyncResult = $ar
            })
        } catch {}
    }

    $bestHost = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 1200) {
        if ($asyncSockets.Count -gt 0 -and $asyncSockets[0].AsyncResult.IsCompleted -and $asyncSockets[0].TcpClient.Connected) {
            $bestHost = $asyncSockets[0].HostName
            break
        }
        $completedCount = ($asyncSockets | Where-Object { $_.AsyncResult.IsCompleted }).Count
        if ($completedCount -eq $asyncSockets.Count) { break }
        Start-Sleep -Milliseconds 25
    }

    if (-not $bestHost) {
        foreach ($item in $asyncSockets) {
            if ($item.TcpClient.Connected) {
                $bestHost = $item.HostName
                break
            }
        }
    }

    foreach ($item in $asyncSockets) {
        try {
            if ($item.TcpClient.Connected) { $item.TcpClient.EndConnect($item.AsyncResult) }
            $item.TcpClient.Close()
            $item.TcpClient.Dispose()
        } catch {}
    }

    if ($bestHost) {
        Write-Host "  ✅ Best route: $bestHost" -ForegroundColor Green
        & $ConnectAction $bestHost
        return
    }

    Write-Host "⚠️ All routes for '$actualTarget' failed to respond." -ForegroundColor Red
}
