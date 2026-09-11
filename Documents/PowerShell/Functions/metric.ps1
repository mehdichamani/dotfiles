<#
.SYNOPSIS
    Interactive network interface metric configuration tool.
.DESCRIPTION
    Lists all IPv4 network adapters sorted by InterfaceMetric and interactively
    prompts to update metrics to prioritize Internet/network routing order.
.EXAMPLE
    metric
#>
function metric {
    Write-Host "`n🔧 Interfaces found:" -ForegroundColor Cyan

    # Get interfaces and store them in an array to avoid pipeline binding issues
    $interfaces = @(Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -ne "Loopback Pseudo-Interface 1" })

    # Display current metrics
    $interfaces | Sort-Object InterfaceMetric | Format-Table ifIndex, InterfaceAlias, InterfaceMetric

    foreach ($interface in $interfaces) {
        $name = $interface.InterfaceAlias
        $current = $interface.InterfaceMetric

        # Prompt user for new metric
        $input = Read-Host ">> Enter new metric for `"$name`" (Current: $current) [Enter to skip]"

        if ([string]::IsNullOrWhiteSpace($input)) {
            Write-Host "⏭️ Skipping $name (no change)" -ForegroundColor Yellow
            continue
        }

        if ($input -match '^\d+$') {
            try {
                Set-NetIPInterface -InterfaceAlias $name -InterfaceMetric $input -ErrorAction Stop
                Write-Host "✅ Metric of $name changed from $current to $input" -ForegroundColor Green
            } catch {
                Write-Host "❌ Error setting metric for ${name}: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "⚠️ Invalid input. Skipping $name..." -ForegroundColor Red
        }
    }

    Write-Host "`n📊 Final interface metrics:" -ForegroundColor Cyan
    Get-NetIPInterface -AddressFamily IPv4 | Sort-Object InterfaceMetric | Format-Table ifIndex, InterfaceAlias, InterfaceMetric
}
