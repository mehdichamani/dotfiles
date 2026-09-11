<#
.SYNOPSIS
    Multi-VLAN Cisco Trunk Switch and vNIC adapter manager.
.DESCRIPTION
    Creates or reconfigures a Hyper-V Virtual Switch on the dedicated Intel OnBoard adapter
    allowing simultaneous access to multiple VLANs (e.g., VLAN 0 Cisco Mgmt, VLAN 100, 400, 500).
.PARAMETER Vlans
    List of VLAN IDs to configure simultaneously (e.g. 0, 100).
.PARAMETER Reset
    Reverts the Hyper-V Trunk Switch and restores adapter to standalone DHCP.
.EXAMPLE
    vlan
.EXAMPLE
    vlan 0, 100
.EXAMPLE
    vlan -Reset
#>
function vlan {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]$Vlans,

        [Parameter()]
        [switch]$Reset
    )

    $switchName = "CiscoTrunkSwitch"
    $mgmtIP = "192.168.30.2"

    # Find the Intel OnBoard adapter dedicated for Cisco Trunk
    $physAdapter = Get-NetAdapter | Where-Object { 
        $_.InterfaceDescription -like "*I219-LM*" -or 
        $_.InterfaceDescription -like "*Intel*Ethernet*" -or
        $_.Name -like "*Cisco Trunk*" -or
        $_.Name -like "*OnBoard*"
    } | Select-Object -First 1

    if (-not $physAdapter) {
        Write-Error "OnBoard Intel network adapter (I219-LM) not found!"
        return
    }

    # Handle Reset / Return to physical standalone adapter
    if ($Reset) {
        Write-Host "Resetting Hyper-V Trunk Switch and reverting OnBoard adapter to standalone..." -ForegroundColor Yellow
        $existingSwitch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
        if ($existingSwitch) {
            Remove-VMSwitch -Name $switchName -Force -ErrorAction SilentlyContinue
            Write-Host "Removed Hyper-V switch: $switchName." -ForegroundColor Green
        }
        $targetName = "OnBoard (Cisco Trunk)"
        Rename-NetAdapter -Name $physAdapter.Name -NewName $targetName -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceAlias $targetName -Dhcp Enabled -ErrorAction SilentlyContinue
        Restart-NetAdapter -Name $targetName -ErrorAction SilentlyContinue
        Write-Host "Adapter '$targetName' restored to standalone DHCP state." -ForegroundColor Green
        return
    }

    # Check existing Hyper-V Switch
    $existingSwitch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue

    # Show current state
    Write-Host "`n=== Multi-VLAN Cisco Trunk Manager (Intel OnBoard) ===" -ForegroundColor Cyan
    if ($existingSwitch) {
        $activeVNics = Get-VMNetworkAdapter -ManagementOS -SwitchName $switchName -ErrorAction SilentlyContinue
        Write-Host "Hyper-V Trunk Switch [$switchName] is ACTIVE on $($physAdapter.InterfaceDescription)." -ForegroundColor Green
        Write-Host "Currently Active Simultaneous VLANs:" -ForegroundColor Yellow
        foreach ($vnic in $activeVNics) {
            $vlanInfo = Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vnic.Name -ErrorAction SilentlyContinue
            $vlanId = if ($vlanInfo.OperationMode -eq "Untagged") { "0 (Untagged / Cisco Mgmt)" } else { "$($vlanInfo.AccessVlanId)" }
            $ip = (Get-NetIPAddress -InterfaceAlias "vEthernet ($($vnic.Name))" -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
            Write-Host "  - $($vnic.Name): VLAN $vlanId | IP: $(if ($ip) { $ip } else { 'DHCP Searching...' })" -ForegroundColor Cyan
        }
    } else {
        Write-Host "Current mode: Standalone Physical Adapter [$($physAdapter.Name)]" -ForegroundColor Yellow
    }

    # Interactive menu if no VLANs provided as parameters
    if (-not $Vlans -or $Vlans.Count -eq 0) {
        Write-Host "`nSelect simultaneous VLAN mode:" -ForegroundColor White
        Write-Host "  [1] Cisco Mgmt + Edari (VLAN 0 & 100 simultaneous) [RECOMMENDED]" -ForegroundColor Cyan
        Write-Host "  [2] Cisco Mgmt + Edari + 400 + 500 (VLAN 0, 100, 400, 500)" -ForegroundColor Cyan
        Write-Host "  [3] Custom VLANs list (comma-separated, e.g. 0,100,600)"
        Write-Host "  [4] Single VLAN (e.g. 100 only)"
        Write-Host "  [r] Reset / Remove Hyper-V Switch (revert to standalone adapter)" -ForegroundColor DarkYellow
        Write-Host "  [q] Quit / Cancel" -ForegroundColor DarkGray

        $choice = Read-Host "`nEnter option [1-4/r/q, Default: 1]"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

        switch ($choice.Trim().ToLower()) {
            "1" { $selectedVlans = @("0", "100") }
            "2" { $selectedVlans = @("0", "100", "400", "500") }
            "3" {
                $rawInput = Read-Host "Enter VLAN IDs separated by comma (e.g. 0, 100, 400, 700)"
                if ([string]::IsNullOrWhiteSpace($rawInput)) {
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                    return
                }
                $selectedVlans = $rawInput.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }
            "4" {
                $singleInput = Read-Host "Enter single VLAN ID (e.g. 0, 100, 400, 500, 600, 700)"
                if ([string]::IsNullOrWhiteSpace($singleInput)) {
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                    return
                }
                $selectedVlans = @($singleInput.Trim())
            }
            "r" {
                vlan -Reset
                return
            }
            "q" {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                return
            }
            default {
                $selectedVlans = $choice.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }
        }
    } else {
        $selectedVlans = $Vlans
    }

    # Clean & validate VLAN IDs
    $validVlans = [System.Collections.Generic.List[string]]::new()
    foreach ($v in $selectedVlans) {
        if ($v -match '^\d+$' -and [int]$v -ge 0 -and [int]$v -le 4094) {
            if (-not $validVlans.Contains($v)) {
                $validVlans.Add($v)
            }
        } else {
            Write-Warning "Ignored invalid VLAN ID: $v"
        }
    }

    if ($validVlans.Count -eq 0) {
        Write-Error "No valid VLAN IDs specified."
        return
    }

    Write-Host "`nConfiguring Intel Hyper-V Trunk Switch for simultaneous VLANs: $($validVlans -join ', ')..." -ForegroundColor Green

    # Create Virtual Switch on Intel adapter if not already created
    if (-not $existingSwitch) {
        Write-Host "Creating Hyper-V Virtual Switch '$switchName' on '$($physAdapter.Name)' ($($physAdapter.InterfaceDescription))..." -ForegroundColor Cyan
        New-VMSwitch -Name $switchName -NetAdapterName $physAdapter.Name -AllowManagementOS $false -ErrorAction Stop | Out-Null
    }

    # Retrieve existing vNICs
    $currentVNics = Get-VMNetworkAdapter -ManagementOS -SwitchName $switchName -ErrorAction SilentlyContinue
    $currentVNicNames = if ($currentVNics) { $currentVNics.Name } else { @() }

    # Desired vNIC names
    $desiredVNicNames = @()

    foreach ($vlan in $validVlans) {
        $vnicName = "VLAN-$vlan"
        $desiredVNicNames += $vnicName
        $interfaceAlias = "vEthernet ($vnicName)"

        if ($vnicName -notin $currentVNicNames) {
            Write-Host "Adding Virtual Adapter: $vnicName..." -ForegroundColor Cyan
            Add-VMNetworkAdapter -ManagementOS -SwitchName $switchName -Name $vnicName -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Milliseconds 800
        }

        # Configure VLAN Tagging
        if ($vlan -eq "0") {
            Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vnicName -Untagged -ErrorAction SilentlyContinue
        } else {
            Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vnicName -Access -VlanId ([int]$vlan) -ErrorAction SilentlyContinue
        }

        # IP & DHCP Configuration
        if ($vlan -eq "0") {
            # VLAN 0 -> Static IP 192.168.30.2
            Set-NetIPInterface -InterfaceAlias $interfaceAlias -Dhcp Disabled -ErrorAction SilentlyContinue
            Remove-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute -InterfaceAlias $interfaceAlias -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
            
            $existingIP = Get-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -IPAddress $mgmtIP -ErrorAction SilentlyContinue
            if (-not $existingIP) {
                New-NetIPAddress -InterfaceAlias $interfaceAlias -IPAddress $mgmtIP -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
            }
            Write-Host "  ✔ $vnicName -> VLAN 0 (Untagged) / Static IP: $mgmtIP/24" -ForegroundColor Green
        } else {
            # All other VLANs -> DHCP
            Remove-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
            Set-NetIPInterface -InterfaceAlias $interfaceAlias -Dhcp Enabled -ErrorAction SilentlyContinue
            Set-DnsClientServerAddress -InterfaceAlias $interfaceAlias -ResetServerAddresses -ErrorAction SilentlyContinue
            Write-Host "  ✔ $vnicName -> VLAN $vlan / DHCP Enabled" -ForegroundColor Green
        }
    }

    # Remove extra vNICs that are no longer requested
    foreach ($oldVNic in $currentVNics) {
        if ($oldVNic.Name -notin $desiredVNicNames) {
            Write-Host "Removing unselected Virtual Adapter: $($oldVNic.Name)..." -ForegroundColor Yellow
            Remove-VMNetworkAdapter -ManagementOS -SwitchName $switchName -Name $oldVNic.Name -ErrorAction SilentlyContinue | Out-Null
        }
    }

    Write-Host "`nAll selected VLANs on Intel Trunk are now ACTIVE simultaneously!" -ForegroundColor Green
}
