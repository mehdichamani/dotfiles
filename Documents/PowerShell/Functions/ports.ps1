<#
.SYNOPSIS
    Interactive open ports explorer and process socket inspector with fzf.
.DESCRIPTION
    Scans active listening TCP ports and UDP endpoints, resolves owning process
    details (PID, Name, Path), and presents them in an interactive
    fzf menu with live preview and quick search.
.PARAMETER All
    Show all connection states instead of just listening sockets.
.PARAMETER TcpOnly
    Inspect only TCP sockets.
.PARAMETER UdpOnly
    Inspect only UDP sockets.
.PARAMETER NoFzf
    Bypass interactive fzf menu and output formatted table directly.
.PARAMETER Help
    Show this help documentation.
.PARAMETER Filter
    Initial search query to pass into fzf or filter keyword.
.EXAMPLE
    ports
.EXAMPLE
    ports -All
.EXAMPLE
    ports 8080
.EXAMPLE
    ports -NoFzf
.EXAMPLE
    ports --help
#>
function ports {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$All,

        [Parameter()]
        [switch]$TcpOnly,

        [Parameter()]
        [switch]$UdpOnly,

        [Parameter()]
        [switch]$NoFzf,

        [Alias('h', '-h', '--help', '-help')]
        [Parameter()]
        [switch]$Help,

        [Parameter(Position = 0)]
        [string]$Filter
    )

    process {
        if ($Help -or $Filter -in @('help', '--help', '-h', '-help')) {
            Get-Help ports
            return
        }

        # Bulk cache running processes for instant name and path resolution
        $procMap = @{}
        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            $procMap[$_.Id] = $_
        }

        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        # 1. Collect TCP listening connections
        if (-not $UdpOnly) {
            $tcpConnections = if ($All) {
                Get-NetTCPConnection -ErrorAction SilentlyContinue
            } else {
                Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
            }

            foreach ($conn in $tcpConnections) {
                $pidVal = [int]$conn.OwningProcess
                $proc = if ($procMap.ContainsKey($pidVal)) { $procMap[$pidVal] } else { $null }
                $procName = if ($proc) { $proc.ProcessName } elseif ($pidVal -eq 4) { 'System' } elseif ($pidVal -eq 0) { 'Idle' } else { 'Unknown' }

                $results.Add([PSCustomObject]@{
                    Proto       = 'TCP'
                    Port        = [int]$conn.LocalPort
                    Address     = $conn.LocalAddress
                    State       = $conn.State.ToString()
                    PID         = $pidVal
                    ProcessName = $procName
                    Path        = if ($proc -and $proc.Path) { $proc.Path } else { '-' }
                })
            }
        }

        # 2. Collect UDP endpoints
        if (-not $TcpOnly) {
            $udpEndpoints = Get-NetUDPEndpoint -ErrorAction SilentlyContinue
            foreach ($endp in $udpEndpoints) {
                $pidVal = [int]$endp.OwningProcess
                $proc = if ($procMap.ContainsKey($pidVal)) { $procMap[$pidVal] } else { $null }
                $procName = if ($proc) { $proc.ProcessName } elseif ($pidVal -eq 4) { 'System' } elseif ($pidVal -eq 0) { 'Idle' } else { 'Unknown' }

                $results.Add([PSCustomObject]@{
                    Proto       = 'UDP'
                    Port        = [int]$endp.LocalPort
                    Address     = $endp.LocalAddress
                    State       = 'Listen'
                    PID         = $pidVal
                    ProcessName = $procName
                    Path        = if ($proc -and $proc.Path) { $proc.Path } else { '-' }
                })
            }
        }

        # Sort cleanly by Port ascending, then Proto
        $sorted = $results | Sort-Object Port, Proto

        # Output table when -NoFzf, fzf missing, or stdout redirected
        $hasFzf = [bool](Get-Command fzf -ErrorAction SilentlyContinue)
        if ($NoFzf -or (-not $hasFzf) -or [Console]::IsOutputRedirected) {
            if (-not $hasFzf -and -not $NoFzf -and -not [Console]::IsOutputRedirected) {
                Write-Host "ℹ️  'fzf' not found. Displaying standard table output." -ForegroundColor DarkGray
            }
            return ($sorted | Format-Table -AutoSize)
        }

        # Format rows with fixed-width columns for fzf
        $header = "{0,-6} {1,-7} {2,-18} {3,-8} {4,-20} {5}" -f "PROTO", "PORT", "ADDRESS", "PID", "PROCESS", "PATH"
        $rows = [System.Collections.Generic.List[string]]::new()

        foreach ($item in $sorted) {
            $line = "{0,-6} {1,-7} {2,-18} {3,-8} {4,-20} {5}" -f $item.Proto, $item.Port, $item.Address, $item.PID, $item.ProcessName, $item.Path
            $rows.Add($line)
        }

        $previewText = "echo [Port Details] & echo Protocol : {1} & echo Port     : {2} & echo Address  : {3} & echo State    : Listen & echo. & echo [Process Details] & echo PID      : {4} & echo Name     : {5} & echo Path     : {6}"

        $fzfArgs = @(
            '--header-lines=1',
            '--reverse',
            '--height=55%',
            '--prompt=🔌 Open Ports > ',
            '--header=Enter: Select | Esc: Exit',
            '--preview-window=right:45%:wrap',
            "--preview=$previewText"
        )

        if (-not [string]::IsNullOrWhiteSpace($Filter)) {
            $fzfArgs += @('--query', $Filter)
        }

        $inputLines = @($header) + $rows
        $selected = $inputLines | & fzf $fzfArgs

        if ([string]::IsNullOrWhiteSpace($selected)) {
            return
        }

        # Return the matching structured object
        $tokens = ($selected.Trim() -split '\s+', 6)
        if ($tokens.Count -ge 4) {
            $selectedProto = $tokens[0]
            $selectedPort  = [int]$tokens[1]
            $selectedPid   = [int]$tokens[3]

            $matched = $sorted | Where-Object { $_.Proto -eq $selectedProto -and $_.Port -eq $selectedPort -and $_.PID -eq $selectedPid } | Select-Object -First 1
            if ($matched) {
                return $matched
            }
        }

        return $selected
    }
}
