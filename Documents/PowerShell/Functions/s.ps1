<#
.SYNOPSIS
    Smart SSH, RDP, VNC, Named Commands, and Cisco Switches manager with multi-route probing from devices.toml.
.DESCRIPTION
    Tests network reachability for routes defined in ~/.ssh/devices.toml 
    and connects to the fastest available route (LAN or WAN fallback).
    Categorized inventory:
      1. Workstations & Mobile (home, homet, work, s24)
      2. Network Routers (2011, mastermind)
      3. Cisco Network Switches (it-miz, anbar, departeman2, etc.)
.PARAMETER Target
    The device name, switch IP, or direct host defined in ~/.ssh/devices.toml.
.PARAMETER CommandName
    Optional named command to execute on remote target.
.PARAMETER Rdp
    Forward local port 3390 to target 3389 and launch Remote Desktop.
.PARAMETER Vnc
    Forward local port 5901 to target 5900 and establish VNC tunnel.
.PARAMETER Jellyfin
    Forward local port 8096 to target 8096 and establish Jellyfin tunnel.
.PARAMETER Port
    Forward custom port spec.
.PARAMETER ListCommands
    List all pre-configured named commands for the target.
.PARAMETER ExtraArgs
    Any additional arguments passed directly to the ssh executable.
.EXAMPLE
    s home
.EXAMPLE
    s it-miz
.EXAMPLE
    s 192.168.30.13
.EXAMPLE
    s 2011 wake-workpc
.EXAMPLE
    s work reboot
.EXAMPLE
    s work -rdp
#>
function s {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$false)]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $devicesToml = Join-Path $HOME ".ssh\devices.toml"
            if (-not (Test-Path $devicesToml)) {
                $chezToml = Join-Path $HOME ".local\share\chezmoi\dot_ssh\devices.toml"
                if (Test-Path $chezToml) { $devicesToml = $chezToml }
            }
            if (-not (Test-Path $devicesToml)) { return }

            $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
            $curDevice = ""
            $inCmd = $false
            $devs = [ordered]@{}

            Get-Content $devicesToml | ForEach-Object {
                $l = $_.Trim()
                if ($l -match '^\[devices\.([^\]\.]+)\.commands\]') {
                    $curDevice = $Matches[1].ToLower()
                    $inCmd = $true
                } elseif ($l -match '^\[devices\.([^\]\.]+)\]') {
                    $curDevice = $Matches[1].ToLower()
                    $inCmd = $false
                    if (-not $devs.Contains($curDevice)) {
                        $devs[$curDevice] = @{ Name = $curDevice; Type = "workstation"; Desc = ""; IP = "" }
                    }
                } elseif ($l -match '^\[') {
                    $curDevice = ""
                    $inCmd = $false
                } elseif ($curDevice -and -not $inCmd) {
                    if ($l -match '^name\s*=\s*["''](.*)["'']') { $devs[$curDevice].Name = $Matches[1] }
                    elseif ($l -match '^type\s*=\s*["''](.*)["'']') { $devs[$curDevice].Type = $Matches[1] }
                    elseif ($l -match '^desc\s*=\s*["''](.*)["'']') { $devs[$curDevice].Desc = $Matches[1] }
                    elseif ($l -match '^ip\s*=\s*["''](.*)["'']') { $devs[$curDevice].IP = $Matches[1] }
                }
            }

            foreach ($id in $devs.Keys) {
                $d = $devs[$id]
                $icon = switch ($d.Type) {
                    "router"      { "🌐" }
                    "switch"      { "🔌" }
                    "mobile"      { "📱" }
                    default       { "💻" }
                }
                $tip = if ($d.Desc) { "$icon $($d.Name) ($($d.Desc))" } else { "$icon $($d.Name)" }
                if ($id -like "$wordToComplete*") {
                    $results.Add([System.Management.Automation.CompletionResult]::new($id, $id, 'ParameterValue', $tip))
                }
                if ($d.Type -eq "switch" -and $d.IP -and $d.IP -like "$wordToComplete*") {
                    $results.Add([System.Management.Automation.CompletionResult]::new($d.IP, $d.IP, 'ParameterValue', "🔌 $($d.Name) ($($d.IP))"))
                }
            }

            return $results
        })]
        [string]$Target,

        [Parameter(Position=1, Mandatory=$false)]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $targetVal = $fakeBoundParameters['Target']
            if (-not $targetVal -and $commandAst) {
                $elements = $commandAst.CommandElements
                if ($elements.Count -gt 1) {
                    $targetVal = $elements[1].Extent.Text.Trim('"', "'")
                }
            }
            if (-not $targetVal) { return }

            $devicesToml = Join-Path $HOME ".ssh\devices.toml"
            if (-not (Test-Path $devicesToml)) {
                $chezToml = Join-Path $HOME ".local\share\chezmoi\dot_ssh\devices.toml"
                if (Test-Path $chezToml) { $devicesToml = $chezToml }
            }
            if (-not (Test-Path $devicesToml)) { return }

            $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
            $curDevice = ""
            $inCmd = $false
            $cmds = @{}

            Get-Content $devicesToml | ForEach-Object {
                $l = $_.Trim()
                if ($l -match '^\[devices\.([^\]\.]+)\.commands\]') {
                    $curDevice = $Matches[1].ToLower()
                    $inCmd = ($curDevice -eq $targetVal.ToLower())
                } elseif ($l -match '^\[') {
                    $inCmd = $false
                } elseif ($inCmd -and ($l -match '^([a-zA-Z0-9_-]+)\s*=\s*["''](.*)["'']')) {
                    $cmds[$Matches[1]] = $Matches[2]
                }
            }

            foreach ($k in $cmds.Keys) {
                if ($k -like "$wordToComplete*") {
                    $results.Add([System.Management.Automation.CompletionResult]::new($k, $k, 'ParameterValue', "⚡ $($cmds[$k])"))
                }
            }
            return $results
        })]
        [string]$CommandName,

        [Parameter(Mandatory=$false)]
        [switch]$Rdp,

        [Parameter(Mandatory=$false)]
        [switch]$Vnc,

        [Parameter(Mandatory=$false)]
        [switch]$Jellyfin,

        [Parameter(Mandatory=$false)]
        [string]$Port,

        [Parameter(Mandatory=$false)]
        [Alias("Commands")]
        [switch]$ListCommands,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$ExtraArgs
    )

    # Clean argv inspection
    $cleanTokens = [System.Collections.Generic.List[string]]::new()
    $isRdp = $Rdp.IsPresent
    $isVnc = $Vnc.IsPresent
    $isJellyfin = $Jellyfin.IsPresent
    $forwardSpec = $Port

    $allArgs = @()
    if ($Target) { $allArgs += $Target }
    if ($CommandName) { $allArgs += $CommandName }
    if ($ExtraArgs) { $allArgs += $ExtraArgs }

    foreach ($a in $allArgs) {
        $aLower = $a.ToLower()
        if ($aLower -in @("rdp", "-rdp", "--rdp")) {
            $isRdp = $true
        } elseif ($aLower -in @("vnc", "-vnc", "--vnc")) {
            $isVnc = $true
        } elseif ($aLower -in @("jellyfin", "-jellyfin", "--jellyfin")) {
            $isJellyfin = $true
        } elseif ($aLower -in @("-l", "--port") -and $allArgs.IndexOf($a) -lt ($allArgs.Length - 1)) {
            # Skip handled
        } else {
            $cleanTokens.Add($a)
        }
    }

    $actualTarget = if ($cleanTokens.Count -gt 0) { $cleanTokens[0] } else { "" }
    $actualExtraArgs = if ($cleanTokens.Count -gt 1) { $cleanTokens[1..($cleanTokens.Count - 1)] } else { @() }

    $devicesToml = Join-Path $HOME ".ssh\devices.toml"
    if (-not (Test-Path $devicesToml)) {
        $chezToml = Join-Path $HOME ".local\share\chezmoi\dot_ssh\devices.toml"
        if (Test-Path $chezToml) { $devicesToml = $chezToml }
    }

    # Central Standard TOML Parser (via python tomllib with regex fallback)
    $devices = [ordered]@{}
    $parsedViaPython = $false

    if (Test-Path $devicesToml) {
        if (Get-Command python -ErrorAction SilentlyContinue) {
            try {
                $pyScript = "import tomllib, json, sys; print(json.dumps(tomllib.load(open(sys.argv[1], chr(114)+chr(98)))))"
                $json = python -c $pyScript $devicesToml 2>$null
                if ($json) {
                    $parsed = $json | ConvertFrom-Json
                    if ($parsed.devices) {
                        foreach ($prop in $parsed.devices.PSObject.Properties) {
                            $k = $prop.Name.ToLower()
                            $v = $prop.Value
                            $cmds = [ordered]@{}
                            if ($v.commands) {
                                foreach ($cProp in $v.commands.PSObject.Properties) {
                                    $cmds[$cProp.Name] = $cProp.Value
                                }
                            }
                            $devices[$k] = @{
                                Name         = if ($v.name) { $v.name } else { $k }
                                Desc         = if ($v.desc) { $v.desc } else { "" }
                                Type         = if ($v.type) { $v.type } else { "workstation" }
                                Shell        = if ($v.shell) { $v.shell } else { "" }
                                IP           = if ($v.ip) { $v.ip } else { "" }
                                Web          = if ($v.web) { $v.web } else { "" }
                                Sync         = ($v.sync -eq $true)
                                Repo         = if ($v.repo) { $v.repo } else { "" }
                                Routes       = if ($v.routes) { @($v.routes) } else { @() }
                                Capabilities = if ($v.capabilities) { @($v.capabilities) } else { @() }
                                Commands     = $cmds
                            }
                        }
                        $parsedViaPython = $true
                    }
                }
            } catch {}
        }

        # Fallback if Python is unavailable
        if (-not $parsedViaPython) {
            $curDev = ""
            $inCommands = $false
            Get-Content $devicesToml | ForEach-Object {
                $line = $_.Trim()
                if ($line -match '^\[devices\.([^\]\.]+)\.commands\]') {
                    $curDev = $Matches[1].ToLower()
                    $inCommands = $true
                    if (-not $devices.Contains($curDev)) {
                        $devices[$curDev] = @{
                            Routes = @(); Commands = [ordered]@{}; Shell = ""; Name = $curDev
                            Type = "workstation"; Desc = ""; IP = ""; Web = ""; Capabilities = @()
                        }
                    }
                } elseif ($line -match '^\[devices\.([^\]\.]+)\]') {
                    $curDev = $Matches[1].ToLower()
                    $inCommands = $false
                    if (-not $devices.Contains($curDev)) {
                        $devices[$curDev] = @{
                            Routes = @(); Commands = [ordered]@{}; Shell = ""; Name = $curDev
                            Type = "workstation"; Desc = ""; IP = ""; Web = ""; Capabilities = @()
                        }
                    }
                } elseif ($line -match '^\[') {
                    $inCommands = $false
                    $curDev = ""
                } elseif ($curDev) {
                    if ($inCommands -and ($line -match '^([a-zA-Z0-9_-]+)\s*=\s*["''](.*)["'']')) {
                        $devices[$curDev].Commands[$Matches[1]] = $Matches[2]
                    } elseif (-not $inCommands) {
                        if ($line -match '^routes\s*=\s*\[(.*)\]') {
                            $rawList = $Matches[1]
                            $devices[$curDev].Routes = ($rawList -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") })
                        } elseif ($line -match '^name\s*=\s*["''](.*)["'']') {
                            $devices[$curDev].Name = $Matches[1]
                        } elseif ($line -match '^desc\s*=\s*["''](.*)["'']') {
                            $devices[$curDev].Desc = $Matches[1]
                        } elseif ($line -match '^type\s*=\s*["''](.*)["'']') {
                            $devices[$curDev].Type = $Matches[1]
                        } elseif ($line -match '^shell\s*=\s*["''](.*)["'']') {
                            $devices[$curDev].Shell = $Matches[1]
                        } elseif ($line -match '^ip\s*=\s*["''](.*)["'']') {
                            $devices[$curDev].IP = $Matches[1]
                        } elseif ($line -match '^web\s*=\s*["''](.*)["'']') {
                            $devices[$curDev].Web = $Matches[1]
                        } elseif ($line -match '^capabilities\s*=\s*\[(.*)\]') {
                            $rawCaps = $Matches[1]
                            $devices[$curDev].Capabilities = ($rawCaps -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") })
                        }
                    }
                }
            }
        }
    }

    # Group devices by type
    $computers = @($devices.Keys | Where-Object { $devices[$_].Type -in @("workstation", "server", "mobile") })
    $routers   = @($devices.Keys | Where-Object { $devices[$_].Type -eq "router" })
    $switches  = @($devices.Keys | Where-Object { $devices[$_].Type -eq "switch" })

    # Interactive picker when no target provided
    if ([string]::IsNullOrWhiteSpace($actualTarget)) {
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            $fzfLines = [System.Collections.Generic.List[string]]::new()

            foreach ($k in $computers) {
                $d = $devices[$k]
                $icon = if ($d.Type -eq "mobile") { "📱" } else { "💻" }
                $descStr = if ($d.Desc) { " - $($d.Desc)" } else { "" }
                $fzfLines.Add("$icon $($k.PadRight(13)) │ $($d.Name)$descStr")
            }

            foreach ($k in $routers) {
                $d = $devices[$k]
                $descStr = if ($d.Desc) { " - $($d.Desc)" } else { "" }
                $fzfLines.Add("🌐 $($k.PadRight(13)) │ $($d.Name)$descStr")
            }

            foreach ($k in $switches) {
                $d = $devices[$k]
                $descStr = if ($d.Desc) { " - $($d.Desc)" } else { "" }
                $ipStr = if ($d.IP) { "$($d.IP)" } else { "" }
                $fzfLines.Add("🔌 $($k.PadRight(13)) │ $ipStr$descStr")
            }

            $selected = $fzfLines | fzf --height=70% --reverse --prompt="📱 Select Device > " --header="[Enter: Connect] [Esc: Cancel]"
            if (-not $selected) { return }
            if ($selected -match '^\S+\s+([a-zA-Z0-9_-]+)') {
                $actualTarget = $Matches[1].Trim()
            } else {
                $actualTarget = (($selected -split '│')[0].Trim() -replace '^[^a-zA-Z0-9_-]+').Trim()
            }
        } else {
            Write-Host "Usage: s <target> [-rdp | -vnc | -jellyfin | -Port <port_or_spec>] [<named_command> | extra_args...]" -ForegroundColor Yellow
            Write-Host "       s <target> <named_command>       (e.g. s 2011 wake-workpc, s work reboot)"
            Write-Host "       s <target> -Commands             (List all defined commands for target)"
            Write-Host "       s <switch_name_or_ip>            (e.g. s it-miz, s 192.168.30.13)"
            
            Write-Host "`n💻 Computers & Mobile:" -ForegroundColor Cyan
            foreach ($k in $computers) {
                $d = $devices[$k]
                Write-Host "  $($k.PadRight(14)) : $($d.Name) $(if($d.Desc){"($($d.Desc))"})" -ForegroundColor White
            }

            Write-Host "`n🌐 Network Routers:" -ForegroundColor Yellow
            foreach ($k in $routers) {
                $d = $devices[$k]
                Write-Host "  $($k.PadRight(14)) : $($d.Name) $(if($d.Desc){"($($d.Desc))"})" -ForegroundColor White
            }

            Write-Host "`n🔌 Cisco Network Switches:" -ForegroundColor Green
            foreach ($k in $switches) {
                $d = $devices[$k]
                Write-Host "  $($k.PadRight(14)) : $($d.IP) $(if($d.Desc){"- $($d.Desc)"})" -ForegroundColor White
            }
            return
        }
    }

    $tLower = $actualTarget.ToLower()

    # Check if target matches a Cisco switch by key or IP
    $matchedSwitch = $null
    foreach ($k in $switches) {
        $d = $devices[$k]
        if ($k -eq $tLower -or $d.Name.ToLower() -eq $tLower -or ($d.IP -and $d.IP -eq $actualTarget)) {
            $matchedSwitch = $d
            break
        }
    }

    if ($matchedSwitch) {
        $connectIp = if ($matchedSwitch.IP) { $matchedSwitch.IP } else { $matchedSwitch.Routes[0] }
        Write-Host "🔐 Connecting to Switch $($matchedSwitch.Name) ($connectIp) via SSH..." -ForegroundColor Green
        & ssh $connectIp $actualExtraArgs
        return
    }

    # Handle -Commands
    if ($ListCommands) {
        if ($devices.Contains($tLower) -and $devices[$tLower].Commands.Count -gt 0) {
            Write-Host "⚡ Named Commands for '$actualTarget':" -ForegroundColor Cyan
            foreach ($cmdKey in $devices[$tLower].Commands.Keys) {
                Write-Host "  - $($cmdKey.PadRight(16)) : $($devices[$tLower].Commands[$cmdKey])" -ForegroundColor Green
            }
        } else {
            Write-Host "ℹ️ No named commands defined for target '$actualTarget'." -ForegroundColor DarkGray
        }
        return
    }

    # Check for named command
    $finalCommand = ""
    if ($actualExtraArgs.Count -gt 0 -and $devices.Contains($tLower)) {
        $potentialCmd = $actualExtraArgs[0]
        if ($devices[$tLower].Commands.ContainsKey($potentialCmd)) {
            $finalCommand = $devices[$tLower].Commands[$potentialCmd]
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

                Write-Host "🚀 Launching Remote Desktop Client (mstsc 127.0.0.1:3390)..." -ForegroundColor Green
                & mstsc.exe /v:127.0.0.1:3390
                Write-Host "⏳ Waiting for RDP session to end..." -ForegroundColor DarkGray
                while (Get-Process -Name mstsc -ErrorAction SilentlyContinue) {
                    Start-Sleep -Milliseconds 500
                }
                Stop-Job $sshJob -ErrorAction SilentlyContinue
                Remove-Job $sshJob -ErrorAction SilentlyContinue
                Write-Host "✅ RDP Tunnel closed successfully." -ForegroundColor Green
                return
            } else {
                Write-Host "⚠️ mstsc.exe not found. Running SSH tunnel only in foreground..." -ForegroundColor Yellow
                & ssh -N -L 3390:localhost:3389 $HostToConnect $actualExtraArgs
                return
            }
        } elseif ($isVnc) {
            Write-Host "🖼️  [VNC Mode] Forwarding local port 5901 to ${HostToConnect}:5900..." -ForegroundColor Cyan
            $vncViewer = Get-Command "vncviewer.exe", "TigerVNC.exe", "RealVNC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($vncViewer) {
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

                Write-Host "🚀 Launching VNC Viewer on 127.0.0.1:5901..." -ForegroundColor Green
                & $vncViewer.Source "127.0.0.1:5901"
                while (Get-Process -Name $vncViewer.Name -ErrorAction SilentlyContinue) {
                    Start-Sleep -Milliseconds 500
                }
                Stop-Job $sshJob -ErrorAction SilentlyContinue
                Remove-Job $sshJob -ErrorAction SilentlyContinue
                Write-Host "✅ VNC Tunnel closed successfully." -ForegroundColor Green
                return
            } else {
                Write-Host "⚠️ VNC viewer not found in PATH. Keeping tunnel open on 127.0.0.1:5901..." -ForegroundColor Yellow
                & ssh -N -L 5901:localhost:5900 $HostToConnect $actualExtraArgs
                return
            }
        } else {
            & ssh $HostToConnect $actualExtraArgs
            return
        }
    }

    $candidates = if ($devices.Contains($tLower)) { $devices[$tLower].Routes } else { @() }

    if ($candidates.Count -eq 0) {
        & $ConnectAction $actualTarget
        return
    }

    Write-Host "🔍 Probing target '$actualTarget': $($candidates -join ', ')" -ForegroundColor Cyan

    $asyncSockets = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($h in $candidates) {
        $ip = $h
        $port = 22
        $sshG = & ssh -G $h 2>$null
        if ($sshG) {
            foreach ($gLine in $sshG) {
                if ($gLine -match '^hostname\s+(.+)$') { $ip = $Matches[1].Trim() }
                if ($gLine -match '^port\s+(\d+)$') { $port = [int]$Matches[1] }
            }
        }
        try {
            $tcp = [System.Net.Sockets.TcpClient]::new()
            $ar = $tcp.BeginConnect($ip, $port, $null, $null)
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
        foreach ($item in $asyncSockets) {
            if ($item.AsyncResult.IsCompleted -and $item.TcpClient.Connected) {
                $bestHost = $item.HostName
                break
            }
        }
        if ($bestHost) { break }
        $completedCount = @($asyncSockets | Where-Object { $_.AsyncResult.IsCompleted }).Count
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

    # Clean sockets
    foreach ($item in $asyncSockets) {
        try {
            $item.TcpClient.Close()
            $item.TcpClient.Dispose()
        } catch {}
    }

    if ($bestHost) {
        Write-Host "⚡ Fastest route: $bestHost" -ForegroundColor Green
        & $ConnectAction $bestHost
    } else {
        $fallback = $candidates[0]
        Write-Host "⚠️ Probing timed out. Fallback to: $fallback" -ForegroundColor Yellow
        & $ConnectAction $fallback
    }
}
