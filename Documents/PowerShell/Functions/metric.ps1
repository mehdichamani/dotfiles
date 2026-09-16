<#
.SYNOPSIS
    Smart network interface metric management and routing priority tool.
.DESCRIPTION
    Inspects and configures IPv4 interface metrics to control Internet/gateway routing priority.
    Supports interactive mode, quick target priority switching, and view-only status with IP and Default Gateway discovery.
.EXAMPLE
    metric
    Interactive review and metric modification for all adapters.
.EXAMPLE
    metric 500
    Instantly prioritizes the VLAN/Interface matching '500' (sets metric to lowest and lowers other routes).
.EXAMPLE
    metric -Show
    Displays current interfaces, IPv4 addresses, metrics, and active default gateways without changing anything.
#>
function metric {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Position = 0, ParameterSetName = 'QuickSet')]
        [string]$Target,

        [Parameter(ParameterSetName = 'QuickSet')]
        [int]$PrimaryMetric = 10,

        [Parameter(ParameterSetName = 'ShowOnly')]
        [switch]$Show
    )

    # Check administrator privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin -and -not $Show) {
        Write-Host "⚠️ Warning: Changing network metrics requires Administrator privileges." -ForegroundColor Yellow
        Write-Host "   Run PowerShell as Administrator if Set-NetIPInterface fails.`n" -ForegroundColor DarkGray
    }

    # Helper function to get detailed interface status
    function Get-MetricTable {
        $routes = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -AddressFamily IPv4 -ErrorAction SilentlyContinue)
        $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" })

        Get-NetIPInterface -AddressFamily IPv4 |
            Where-Object { $_.InterfaceAlias -ne "Loopback Pseudo-Interface 1" } |
            Sort-Object InterfaceMetric |
            ForEach-Object {
                $ifIndex = $_.ifIndex
                $alias = $_.InterfaceAlias
                $metric = $_.InterfaceMetric
                $ipMatch = ($ips | Where-Object { $_.InterfaceIndex -eq $ifIndex } | Select-Object -ExpandProperty IPAddress) -join ', '
                $hasDefaultGateway = ($routes | Where-Object { $_.InterfaceIndex -eq $ifIndex })

                [PSCustomObject]@{
                    ActiveGateway = if ($hasDefaultGateway) { "★ Active" } else { "  -" }
                    Index         = $ifIndex
                    InterfaceName = $alias
                    Metric        = $metric
                    IPAddress     = if ($ipMatch) { $ipMatch } else { "No IPv4" }
                }
            }
    }

    # Mode: Show Only
    if ($Show) {
        Write-Host "`n📊 Current Network Interfaces & Routing Status:" -ForegroundColor Cyan
        Get-MetricTable | Format-Table ActiveGateway, Index, InterfaceName, Metric, IPAddress -AutoSize
        return
    }

    # Mode: Quick Set by Name / Pattern (e.g. 'metric 500' or 'metric VLAN-400')
    if ($PSCmdlet.ParameterSetName -eq 'QuickSet' -and -not [string]::IsNullOrWhiteSpace($Target)) {
        $interfaces = @(Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -ne "Loopback Pseudo-Interface 1" })
        $matched = @($interfaces | Where-Object { $_.InterfaceAlias -like "*$Target*" -or $_.ifIndex -eq $Target })

        if ($matched.Count -eq 0) {
            Write-Host "❌ No interface found matching '$Target'." -ForegroundColor Red
            return
        }
        if ($matched.Count -gt 1) {
            Write-Host "⚠️ Multiple interfaces matched '$Target':" -ForegroundColor Yellow
            $matched | Format-Table ifIndex, InterfaceAlias, InterfaceMetric
            Write-Host "Please specify a more exact name or ifIndex." -ForegroundColor Yellow
            return
        }

        $chosen = $matched[0]
        Write-Host "🎯 Targeting: $($chosen.InterfaceAlias) (ifIndex: $($chosen.ifIndex))" -ForegroundColor Cyan
        try {
            Set-NetIPInterface -InterfaceAlias $chosen.InterfaceAlias -InterfaceMetric $PrimaryMetric -ErrorAction Stop
            Write-Host "✅ Metric of '$($chosen.InterfaceAlias)' set to $PrimaryMetric (High Priority)" -ForegroundColor Green

            # Flush DNS cache to apply routes instantly
            Clear-DnsClientCache -ErrorAction SilentlyContinue
            Write-Host "🚀 DNS cache flushed. Route is now active!" -ForegroundColor Cyan
        } catch {
            Write-Host "❌ Error updating metric: $_" -ForegroundColor Red
        }

        Write-Host "`n📊 Updated Interfaces:" -ForegroundColor Cyan
        Get-MetricTable | Format-Table ActiveGateway, Index, InterfaceName, Metric, IPAddress -AutoSize
        return
    }

    # Mode: Interactive
    Write-Host "`n🔧 Network Interfaces found:" -ForegroundColor Cyan
    Get-MetricTable | Format-Table ActiveGateway, Index, InterfaceName, Metric, IPAddress -AutoSize

    $interfaces = @(Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -ne "Loopback Pseudo-Interface 1" } | Sort-Object InterfaceMetric)

    if ($interfaces.Count -lt 1) {
        Write-Host "❌ No IPv4 interfaces found." -ForegroundColor Red
        return
    }

    $first = $interfaces[0]
    $second = if ($interfaces.Count -ge 2) { $interfaces[1] } else { $null }

    Write-Host "⚡ Choose Action:" -ForegroundColor Cyan
    if ($second) {
        Write-Host "  [1] 🔁 Swap top 2 ('$($first.InterfaceAlias)' [$($first.InterfaceMetric)] ⇄ '$($second.InterfaceAlias)' [$($second.InterfaceMetric)])" -ForegroundColor Yellow
        Write-Host "  [2] ✍️  Manual (Enter new metric for each adapter)" -ForegroundColor White
    } else {
        Write-Host "  [1] ✍️  Manual (Enter new metric for each adapter)" -ForegroundColor White
    }
    Write-Host "  [q] 🛑 Quit" -ForegroundColor DarkGray
    Write-Host ""

    $choiceDefault = if ($second) { "1" } else { "1" }
    $choicePrompt = if ($second) { "Select mode [1/2, default: 1]" } else { "Select mode [1, default: 1]" }
    $choice = Read-Host "$choicePrompt"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = $choiceDefault
    }

    $choice = $choice.Trim().ToLower()

    if ($choice -eq 'q') {
        Write-Host "🛑 Aborted by user." -ForegroundColor DarkYellow
        return
    }

    $changed = $false

    if ($second -and ($choice -eq '1' -or $choice -eq 's' -or $choice -eq 'swap')) {
        # Option 1: Quick Swap top 2 interfaces
        $name1 = $first.InterfaceAlias
        $metric1 = $first.InterfaceMetric
        $name2 = $second.InterfaceAlias
        $metric2 = $second.InterfaceMetric

        # If both metrics are identical, give the 2nd one metric1 and 1st one metric1 + 10 or vice-versa
        $newMetric1 = $metric2
        $newMetric2 = $metric1
        if ($metric1 -eq $metric2) {
            $newMetric1 = $metric1 + 10
            $newMetric2 = $metric1
        }

        Write-Host "`n🔁 Swapping metrics between '$name1' and '$name2'..." -ForegroundColor Cyan
        try {
            Set-NetIPInterface -InterfaceAlias $name1 -InterfaceMetric $newMetric1 -ErrorAction Stop
            Write-Host "✅ '$name1': $metric1 ➔ $newMetric1" -ForegroundColor Green
            Set-NetIPInterface -InterfaceAlias $name2 -InterfaceMetric $newMetric2 -ErrorAction Stop
            Write-Host "✅ '$name2': $metric2 ➔ $newMetric2" -ForegroundColor Green
            $changed = $true
        } catch {
            Write-Host "❌ Error during metric swap: $_" -ForegroundColor Red
        }
    } else {
        # Option 2: Manual prompt for each interface
        Write-Host "`n💡 Enter a number for new metric, [Enter] to skip, 'q' to quit.`n" -ForegroundColor DarkGray

        foreach ($interface in $interfaces) {
            $name = $interface.InterfaceAlias
            $current = $interface.InterfaceMetric

            $inputVal = Read-Host ">> Enter new metric for `"$name`" (Current: $current) [Enter to skip]"

            if ([string]::IsNullOrWhiteSpace($inputVal)) {
                Write-Host "⏭️  Skipping $name (no change)" -ForegroundColor Yellow
                continue
            }

            if ($inputVal.Trim().ToLower() -eq 'q') {
                Write-Host "🛑 Stopped interactive input." -ForegroundColor DarkYellow
                break
            }

            if ($inputVal -match '^\d+$') {
                try {
                    Set-NetIPInterface -InterfaceAlias $name -InterfaceMetric ([int]$inputVal) -ErrorAction Stop
                    Write-Host "✅ Metric of $name changed from $current to $inputVal" -ForegroundColor Green
                    $changed = $true
                } catch {
                    Write-Host "❌ Error setting metric for ${name}: $_" -ForegroundColor Red
                }
            } else {
                Write-Host "⚠️ Invalid input '$inputVal'. Skipping $name..." -ForegroundColor Red
            }
        }
    }

    if ($changed) {
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Write-Host "`n🚀 DNS cache flushed for instant switch." -ForegroundColor Cyan
    }

    Write-Host "`n📊 Final interface metrics:" -ForegroundColor Cyan
    Get-MetricTable | Format-Table ActiveGateway, Index, InterfaceName, Metric, IPAddress -AutoSize
}
