<#
.SYNOPSIS
    Dotsync - Dynamic P2P Git Sync and Mesh Dotfiles Manager for Chezmoi (PowerShell 7+)
.DESCRIPTION
    Bidirectional peer-to-peer git synchronization for Chezmoi dotfiles across all devices
    discovered in ~/.ssh/devices.toml (with multi-route LAN/WAN auto-probing).
.PARAMETER Peer
    Sync specifically with a single peer (e.g. 'home', 'work', 's24') instead of all peers.
.PARAMETER Action
    Subcommand action: 'apply', 'install', 'refresh', 'dry-run'.
.PARAMETER DryRun
    Check connections and commit differences without merging or pushing.
.EXAMPLE
    dotsync
.EXAMPLE
    dotsync work
.EXAMPLE
    dotsync dry-run
.EXAMPLE
    dotsync refresh
#>
function dotsync {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$false)]
        [string]$Target,
        [Parameter(Mandatory=$false)]
        [Alias("n")]
        [switch]$DryRun,
        [Parameter(Mandatory=$false)]
        [Alias("f")]
        [switch]$Force
    )

    $repoDir = Join-Path $HOME ".local\share\chezmoi"
    $devicesToml = Join-Path $HOME ".ssh\devices.toml"
    if (-not (Test-Path $devicesToml)) {
        $chezToml = Join-Path $repoDir "dot_ssh\devices.toml"
        if (Test-Path $chezToml) { $devicesToml = $chezToml }
    }

    # Discover all sync-enabled peers and their repo paths from devices.toml (or fallback to SSH config)
    $allPeers = @()
    $peerRepoPaths = @{}
    $candidateHostsByPeer = @{}
    $hostInfo = @{}

    if (Test-Path $devicesToml) {
        $parsedViaPython = $false
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
                            if ($v.sync -eq $true) {
                                $allPeers += $k
                                if ($v.repo) { $peerRepoPaths[$k] = $v.repo }
                                if ($v.routes) { $candidateHostsByPeer[$k] = @($v.routes) }
                            }
                        }
                        $parsedViaPython = $true
                    }
                }
            } catch {}
        }

        # Fallback if Python is unavailable
        if (-not $parsedViaPython) {
            $curNode = ""
            $isSync = $false
            $curRepo = ""
            $curRoutes = @()

            $lines = Get-Content $devicesToml
            foreach ($line in $lines) {
                $l = $line.Trim()
                if ($l -match '^\[devices\.([^\]\.]+)\]') {
                    if ($curNode -and $isSync) {
                        $allPeers += $curNode
                        if ($curRepo) { $peerRepoPaths[$curNode] = $curRepo }
                        if ($curRoutes.Count -gt 0) { $candidateHostsByPeer[$curNode] = $curRoutes }
                    }
                    $curNode = $Matches[1].ToLower()
                    $isSync = $false
                    $curRepo = ""
                    $curRoutes = @()
                } elseif ($curNode -and ($l -match '^sync\s*=\s*true')) {
                    $isSync = $true
                } elseif ($curNode -and ($l -match '^repo\s*=\s*["'']([^"'']+)["'']')) {
                    $curRepo = $Matches[1]
                } elseif ($curNode -and ($l -match '^routes\s*=\s*\[(.*)\]')) {
                    $rawList = $Matches[1]
                    $curRoutes = ($rawList -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") })
                }
            }
            if ($curNode -and $isSync) {
                $allPeers += $curNode
                if ($curRepo) { $peerRepoPaths[$curNode] = $curRepo }
                if ($curRoutes.Count -gt 0) { $candidateHostsByPeer[$curNode] = $curRoutes }
            }
        }
    }

    # Fallback to SSH config if no devices found
    if ($allPeers.Count -eq 0) {
        $sshConfigFile = Join-Path $HOME ".ssh\config"
        if (-not (Test-Path $sshConfigFile)) {
            $chezConfig = Join-Path $repoDir "dot_ssh\config"
            if (Test-Path $chezConfig) { $sshConfigFile = $chezConfig }
        }
        if (Test-Path $sshConfigFile) {
            $curGrp = ""
            $isSync = $false
            Get-Content $sshConfigFile | ForEach-Object {
                $line = $_.Trim()
                if ($line -match '^#\s*@group\s+(\S+)') {
                    if ($curGrp -and $isSync) { $allPeers += $curGrp }
                    $curGrp = $Matches[1].ToLower()
                    $isSync = $false
                } elseif ($line -match '^#\s*@sync\s+(true|yes|1)') {
                    $isSync = $true
                } elseif ($line -match '^Host\s+([^#*?]+)') {
                    $h = $Matches[1].Trim()
                    if ($curGrp) {
                        if (-not $candidateHostsByPeer.ContainsKey($curGrp)) { $candidateHostsByPeer[$curGrp] = @() }
                        $candidateHostsByPeer[$curGrp] += $h
                    }
                }
            }
            if ($curGrp -and $isSync) { $allPeers += $curGrp }
        }
    }

    # Parse parameters
    $action = "sync"
    $targetPeer = ""
    $isDryRun = $DryRun.IsPresent

    if ($Target) {
        $tLower = $Target.ToLower()
        switch ($tLower) {
            { $_ -in @("-h", "--help", "help") } {
                Write-Host "Usage: dotsync [dry-run | apply | install | refresh | <peer_device>]" -ForegroundColor Yellow
                Write-Host "`nCommands:"
                Write-Host "  (none)         Sync dotfiles repository with all reachable peer devices (auto push/pull)"
                Write-Host "  <peer>         Sync dotfiles repository with a specific peer device"
                Write-Host "  dry-run, -n    Check connections and commit differences without pushing or pulling"
                Write-Host "  apply          Apply dotfiles changes to the live system (chezmoi apply)"
                Write-Host "  install        Run package verification and installer (~/.config/scripts/check-packages.sh)"
                Write-Host "  refresh        Apply chezmoi, reload desktop components, hooks, and fish config"
                Write-Host "  -h, --help     Show this help message"
                Write-Host "`nBehavior:"
                Write-Host "  • Ahead:     Automatically pushes to peer safely."
                Write-Host "  • Behind:    Automatically fast-forward pulls from peer safely."
                Write-Host "  • Diverged:  Prompts interactively for Rebase & Push, Push Force, Pull Force, or Abort."
                Write-Host "`nAvailable Peer Devices (from ~/.ssh/devices.toml):"
                if ($allPeers.Count -gt 0) {
                    Write-Host "  $($allPeers -join ', ')" -ForegroundColor Cyan
                } else {
                    Write-Host "  (No sync peers discovered in $devicesToml)" -ForegroundColor DarkGray
                }
                return
            }
            { $_ -in @("dry-run", "dryrun", "-n", "--dry-run") } {
                $action = "sync"
                $isDryRun = $true
            }
            "apply" { $action = "apply" }
            "install" { $action = "install" }
            "refresh" { $action = "refresh" }
            default {
                if ($tLower -in $allPeers) {
                    $targetPeer = $tLower
                } else {
                    Write-Host "❌ Unknown argument or peer device: '$Target'" -ForegroundColor Red
                    Write-Host "`nAvailable Peer Devices:"
                    Write-Host "  $($allPeers -join ', ')" -ForegroundColor Cyan
                    Write-Host "`n    Run 'dotsync --help' for usage."
                    return
                }
            }
        }
    }

    if ($action -eq "apply") {
        Write-Host "🔄 Applying Chezmoi state to home directory..." -ForegroundColor Cyan
        & chezmoi apply
        return
    } elseif ($action -eq "install") {
        $instScript = Join-Path $HOME ".config\scripts\check-packages.sh"
        if (Test-Path $instScript) {
            Write-Host "📦 Running system package verification..." -ForegroundColor Cyan
            & bash $instScript
        } else {
            Write-Host "❌ Package checker script not found at: $instScript" -ForegroundColor Red
        }
        return
    } elseif ($action -eq "refresh") {
        Write-Host "✨ Refreshing live environment..." -ForegroundColor Cyan
        & chezmoi apply
        Write-Host "✅ Environment refreshed successfully." -ForegroundColor Green
        return
    }

    # Current host detection
    $nameFile = Join-Path $HOME ".config\name"
    $currentHost = if (Test-Path $nameFile) { (Get-Content $nameFile -Raw).Trim() } else { $env:COMPUTERNAME.ToLower() }

    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    if ($isDryRun) {
        Write-Host "║  🔍 Dotsync P2P Mesh (DRY-RUN / INSPECTION MODE)             ║" -ForegroundColor Yellow
    } else {
        Write-Host "║  🔄 Dotsync P2P Mesh Synchronization                         ║" -ForegroundColor Cyan
    }
    Write-Host "║  Host: $(($currentHost).PadRight(12)) | Repo: $(($repoDir).PadRight(35))║" -ForegroundColor DarkGray
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

    if (-not (Test-Path (Join-Path $repoDir ".git"))) {
        Write-Host "❌ Error: $repoDir is not a valid git repository." -ForegroundColor Red
        return
    }

    # 1. Local Status Check (Do not touch uncommitted changes)
    $dirty = & git -C $repoDir status --porcelain 2>$null
    if ($dirty) {
        Write-Host "`n⚠️ Uncommitted local changes detected in ${repoDir}:" -ForegroundColor Yellow
        & git -C $repoDir status --short
        Write-Host "  (Note: Uncommitted changes will be left untouched. Only committed history is synced.)" -ForegroundColor DarkGray
    } else {
        Write-Host "`n✓ Local repository clean (no uncommitted changes)." -ForegroundColor Green
    }

    $syncPeers = if ($targetPeer) { @($targetPeer) } else { $allPeers | Where-Object { $_ -ne $currentHost } }

    if ($syncPeers.Count -eq 0) {
        Write-Host "ℹ️ No other peer devices to sync with." -ForegroundColor Yellow
        return
    }

    $totalPeers = $syncPeers.Count
    $syncedCount = 0
    $newCommitsPulled = $false

    foreach ($peer in $syncPeers) {
        Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
        Write-Host "📡 Syncing with peer: $peer" -ForegroundColor Cyan
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue

        $peerRepo = if ($peerRepoPaths.ContainsKey($peer)) { $peerRepoPaths[$peer] } else { "~/.local/share/chezmoi" }
        $candidates = if ($candidateHostsByPeer.ContainsKey($peer)) { $candidateHostsByPeer[$peer] } else { @($peer) }

        # Parallel TCP Probe for fastest route
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

        $reachableHost = $null
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt 1200) {
            if ($asyncSockets.Count -gt 0 -and $asyncSockets[0].AsyncResult.IsCompleted -and $asyncSockets[0].TcpClient.Connected) {
                $reachableHost = $asyncSockets[0].HostName
                break
            }
            $completedCount = @($asyncSockets | Where-Object { $_.AsyncResult.IsCompleted }).Count
            if ($completedCount -eq $asyncSockets.Count) { break }
            Start-Sleep -Milliseconds 25
        }

        if (-not $reachableHost) {
            foreach ($item in $asyncSockets) {
                if ($item.TcpClient.Connected) {
                    $reachableHost = $item.HostName
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

        if (-not $reachableHost) {
            Write-Host "  ✕ Unreachable: All routes for '$peer' ($($candidates -join ', ')) failed to respond." -ForegroundColor Red
            continue
        }

        Write-Host "  ✓ Connected via: $reachableHost" -ForegroundColor Green

        $remoteName = "$peer"
        $remoteUrl = "${reachableHost}:${peerRepo}"

        $existingUrl = & git -C $repoDir remote get-url $remoteName 2>$null
        if (-not $existingUrl) {
            & git -C $repoDir remote add $remoteName $remoteUrl
        } elseif ($existingUrl -ne $remoteUrl) {
            & git -C $repoDir remote set-url $remoteName $remoteUrl
        }

        $currentBranch = (& git -C $repoDir rev-parse --abbrev-ref HEAD 2>$null)
        if (-not $currentBranch) { $currentBranch = "main" }

        if ($isDryRun) {
            Write-Host "  [Dry-Run] Fetching metadata from $remoteName ($remoteUrl)..." -ForegroundColor Yellow
            & git -C $repoDir fetch $remoteName $currentBranch 2>&1 | ForEach-Object { "    $_" }
            $behind = (& git -C $repoDir rev-list --count "HEAD..$remoteName/$currentBranch" 2>$null)
            $ahead = (& git -C $repoDir rev-list --count "$remoteName/$currentBranch..HEAD" 2>$null)
            Write-Host "  📊 Commits Status: Ahead: $ahead | Behind: $behind" -ForegroundColor Cyan
            $syncedCount++
            continue
        }

        # Configure peer git repo to accept push to checked-out branch (receive.denyCurrentBranch=updateInstead)
        & ssh -o ConnectTimeout=2 -o BatchMode=yes "$reachableHost" "git -C '$peerRepo' config receive.denyCurrentBranch updateInstead" 2>$null

        # 1. Fetch latest metadata from peer
        Write-Host "  📥 Fetching latest metadata from $peer..."
        $fetchOut = & git -C $repoDir fetch $remoteName "+refs/heads/${currentBranch}:refs/remotes/${remoteName}/${currentBranch}" 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($fetchOut) {
                $fetchOut | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            }
            Write-Host "  ✕ Failed to fetch from $peer." -ForegroundColor Red
            continue
        }

        $remoteRef = "$remoteName/$currentBranch"
        $behind = [int](& git -C $repoDir rev-list --count "HEAD..$remoteRef" 2>$null)
        $ahead = [int](& git -C $repoDir rev-list --count "$remoteRef..HEAD" 2>$null)

        # 2. Case A: Both in sync
        if ($ahead -eq 0 -and $behind -eq 0) {
            Write-Host "  ✓ In sync with $peer (no changes)." -ForegroundColor Green
            $syncedCount++
            continue
        }

        # 3. Case B: Local is strictly ahead -> Safe Push
        if ($ahead -gt 0 -and $behind -eq 0) {
            Write-Host "  📤 Local is ahead by $ahead commit(s). Pushing to $peer..." -ForegroundColor Cyan
            & git -C $repoDir push $remoteName $currentBranch
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Successfully pushed to $peer." -ForegroundColor Green
                $syncedCount++
            } else {
                Write-Host "  ✕ Failed to push to $peer." -ForegroundColor Red
                return
            }
            continue
        }

        # 4. Case C: Local is strictly behind -> Safe Pull (Fast-Forward Only)
        if ($behind -gt 0 -and $ahead -eq 0) {
            Write-Host "  📥 Peer $peer has $behind new commit(s). Fast-forward pulling..." -ForegroundColor Cyan
            & git -C $repoDir pull --ff-only $remoteName $currentBranch
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Successfully pulled from $peer (fast-forwarded)." -ForegroundColor Green
                $syncedCount++
            } else {
                Write-Host "  ✕ Failed to fast-forward pull from $peer." -ForegroundColor Red
                return
            }
            continue
        }

        # 5. Case D: History has diverged (ahead > 0 and behind > 0) -> Interactive Prompt
        if ($ahead -gt 0 -and $behind -gt 0) {
            Write-Host "`n  ⚠️ Diverged history detected between local and $peer!" -ForegroundColor Yellow
            Write-Host "  • Local has $ahead unique commit(s):" -ForegroundColor Cyan
            (& git -C $repoDir log --oneline --no-merges -n 3 "$remoteRef..HEAD") | ForEach-Object { "      $_" }
            Write-Host "  • Peer $peer has $behind unique commit(s):" -ForegroundColor Magenta
            (& git -C $repoDir log --oneline --no-merges -n 3 "HEAD..$remoteRef") | ForEach-Object { "      $_" }
            Write-Host ""
            Write-Host "  How would you like to resolve this divergence?" -ForegroundColor White
            Write-Host "    [1] Rebase & Push " -ForegroundColor Green -NoNewline
            Write-Host "(Rebase local on $peer and push back to $peer)" -ForegroundColor DarkGray
            Write-Host "    [2] Push Force   " -ForegroundColor Yellow -NoNewline
            Write-Host "(Overwrite $peer with local state)" -ForegroundColor DarkGray
            Write-Host "    [3] Pull Force   " -ForegroundColor Cyan -NoNewline
            Write-Host "(Overwrite local with $peer state)" -ForegroundColor DarkGray
            Write-Host "    [4] Cancel/Abort " -ForegroundColor Red -NoNewline
            Write-Host "(Default - do nothing)" -ForegroundColor DarkGray
            Write-Host ""

            $choice = Read-Host "  Select action [1/2/3/4] (default 4)"

            switch ($choice.Trim().ToLower()) {
                { $_ -in @("1", "rebase", "rb", "r") } {
                    Write-Host "  🔄 Checking if rebase can apply cleanly without conflicts..." -ForegroundColor Green
                    $mb = (& git -C $repoDir merge-base HEAD $remoteRef 2>$null)
                    $canRebase = $false
                    if ($mb) {
                        & git -C $repoDir merge-tree --write-tree HEAD $remoteRef 2>$null | Out-Null
                        if ($LASTEXITCODE -eq 0) { $canRebase = $true }
                    }

                    if (-not $canRebase) {
                        Write-Host "  ⚠️ Rebase conflict detected! Rebase cannot be applied cleanly without manual resolution." -ForegroundColor Red
                        Write-Host "  Resolve manually with: git -C '$repoDir' rebase $remoteRef" -ForegroundColor DarkGray
                        return
                    }

                    Write-Host "  🔄 Rebasing local branch '$currentBranch' onto $remoteRef..." -ForegroundColor Green
                    & git -C $repoDir rebase $remoteRef
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "  ✓ Local branch successfully rebased onto $peer." -ForegroundColor Green
                        Write-Host "  📤 Pushing rebased commits to $peer..." -ForegroundColor Cyan
                        & git -C $repoDir push $remoteName $currentBranch
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "  ✓ Successfully synced & pushed to $peer." -ForegroundColor Green
                            $syncedCount++
                        } else {
                            Write-Host "  ✕ Failed to push rebased branch to $peer." -ForegroundColor Red
                            return
                        }
                    } else {
                        Write-Host "  ✕ Git rebase failed. Aborting rebase to preserve state..." -ForegroundColor Red
                        & git -C $repoDir rebase --abort 2>$null
                        return
                    }
                }
                { $_ -in @("2", "push", "push-force", "pf") } {
                    Write-Host "  🚀 Force-pushing local branch '$currentBranch' to $peer..." -ForegroundColor Yellow
                    & git -C $repoDir push --force $remoteName $currentBranch
                    if ($LASTEXITCODE -eq 0) {
                        & ssh -o ConnectTimeout=2 -o BatchMode=yes "$reachableHost" "git -C '$peerRepo' reset --hard HEAD" 2>$null
                        Write-Host "  ✓ Successfully force-pushed to $peer (mirrored)." -ForegroundColor Green
                        $syncedCount++
                    } else {
                        Write-Host "  ✕ Failed to force-push to $peer." -ForegroundColor Red
                        return
                    }
                }
                { $_ -in @("3", "pull", "pull-force") } {
                    Write-Host "  📥 Force-pulling $peer state into local branch '$currentBranch'..." -ForegroundColor Cyan
                    & git -C $repoDir reset --hard "$remoteRef"
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "  ✓ Local repository successfully reset to match $peer." -ForegroundColor Green
                        $syncedCount++
                    } else {
                        Write-Host "  ✕ Failed to reset local repository to $remoteRef." -ForegroundColor Red
                        return
                    }
                }
                default {
                    Write-Host "  ⏸️ Aborted by user. No changes made." -ForegroundColor Yellow
                    return
                }
            }
        }
    }

    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
    Write-Host "🏁 Dotsync finished: Synced with $syncedCount/$totalPeers peer(s)." -ForegroundColor Green
}
