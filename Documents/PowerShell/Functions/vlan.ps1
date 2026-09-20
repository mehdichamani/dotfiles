<#
.SYNOPSIS
    Multi-VLAN Cisco Trunk Switch and vNIC adapter manager.
.DESCRIPTION
    Creates or reconfigures a Hyper-V Virtual Switch on the dedicated Intel OnBoard adapter
    allowing simultaneous access to multiple VLANs (VLAN 1 Cisco Mgmt, VLAN 100, 400, 500, 700).
    Non-destructive by default: preserves existing active vNICs during reconfiguration to prevent
    remote RDP session drops.
.PARAMETER Vlans
    List of VLAN IDs to configure simultaneously (e.g. 1, 100, 400, 500, 700).
.PARAMETER Reset
    Reverts the Hyper-V Trunk Switch and restores adapter to standalone DHCP.
.EXAMPLE
    vlan
.EXAMPLE
    vlan 1, 100, 400, 500, 700
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
    $vlan700IP = "192.168.50.100"

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

    # Handle Reset / Return to physical standalone adapter (ONLY reset deletes all vNICs)
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
            $vlanId = if ($vlanInfo.OperationMode -eq "Untagged") { "1 (Native / Cisco Mgmt)" } else { "$($vlanInfo.AccessVlanId)" }
            $ip = (Get-NetIPAddress -InterfaceAlias "vEthernet ($($vnic.Name))" -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
            Write-Host "  - $($vnic.Name): VLAN $vlanId | IP: $(if ($ip) { ($ip -join ', ') } else { 'DHCP Searching...' })" -ForegroundColor Cyan
        }
    } else {
        Write-Host "Current mode: Standalone Physical Adapter [$($physAdapter.Name)]" -ForegroundColor Yellow
    }

    # Interactive menu if no VLANs provided as parameters
    if (-not $Vlans -or $Vlans.Count -eq 0) {
        Write-Host "`nSelect simultaneous VLAN mode:" -ForegroundColor White
        Write-Host "  [1] All Standard VLANs (1, 100, 400, 500, 700) [RECOMMENDED]" -ForegroundColor Green
        Write-Host "  [2] Cisco Mgmt + Edari (VLAN 1 & 100 simultaneous)" -ForegroundColor Cyan
        Write-Host "  [3] Custom VLANs list (comma-separated, e.g. 1, 100, 600)"
        Write-Host "  [4] Single VLAN (e.g. 1 only or 100 only)"
        Write-Host "  [r] Reset / Remove Hyper-V Switch (revert to standalone adapter)" -ForegroundColor DarkYellow
        Write-Host "  [q] Quit / Cancel" -ForegroundColor DarkGray

        $choice = Read-Host "`nEnter option [1-4/r/q, Default: 1]"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

        switch ($choice.Trim().ToLower()) {
            "1" { $selectedVlans = @("1", "100", "400", "500", "700") }
            "2" { $selectedVlans = @("1", "100") }
            "3" {
                $rawInput = Read-Host "Enter VLAN IDs separated by comma (e.g. 1, 100, 400, 700)"
                if ([string]::IsNullOrWhiteSpace($rawInput)) {
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                    return
                }
                $selectedVlans = $rawInput.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }
            "4" {
                $singleInput = Read-Host "Enter single VLAN ID (e.g. 1, 100, 400, 500, 600, 700)"
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

    # Clean & validate VLAN IDs (Map 0 to 1 if entered by habit)
    $validVlans = [System.Collections.Generic.List[string]]::new()
    foreach ($v in $selectedVlans) {
        $cleanV = if ($v -eq "0") { "1" } else { $v }
        if ($cleanV -match '^\d+$' -and [int]$cleanV -ge 1 -and [int]$cleanV -le 4094) {
            if (-not $validVlans.Contains($cleanV)) {
                $validVlans.Add($cleanV)
            }
        } else {
            Write-Warning "Ignored invalid VLAN ID: $v"
        }
    }

    if ($validVlans.Count -eq 0) {
        Write-Error "No valid VLAN IDs specified."
        return
    }

    Write-Host "`nEnsuring requested VLANs are active: $($validVlans -join ', ')..." -ForegroundColor Green

    # Create Virtual Switch on Intel adapter if not already created
    if (-not $existingSwitch) {
        Write-Host "Creating Hyper-V Virtual Switch '$switchName' on '$($physAdapter.Name)' ($($physAdapter.InterfaceDescription))..." -ForegroundColor Cyan
        New-VMSwitch -Name $switchName -NetAdapterName $physAdapter.Name -AllowManagementOS $false -ErrorAction Stop | Out-Null
    }

    # Clean up legacy/deprecated adapter names that could cause Untagged conflicts
    $deprecatedHostVnics = Get-VMNetworkAdapter -ManagementOS -SwitchName $switchName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Host Vnic*" -or $_.Name -eq "VLAN-0" }
    foreach ($oldHostVnic in $deprecatedHostVnics) {
        Write-Host "Removing legacy deprecated adapter: $($oldHostVnic.Name)..." -ForegroundColor Yellow
        Remove-VMNetworkAdapter -ManagementOS -SwitchName $switchName -Name $oldHostVnic.Name -ErrorAction SilentlyContinue | Out-Null
    }

    # Retrieve existing vNICs
    $currentVNics = Get-VMNetworkAdapter -ManagementOS -SwitchName $switchName -ErrorAction SilentlyContinue
    $currentVNicNames = if ($currentVNics) { $currentVNics.Name } else { @() }

    # Predefined persistent MAC addresses
    $staticMacAddresses = @{
        "1"   = "00155D01C80E"
        "100" = "00155D01C80F"
        "400" = "00155D01C805" # Bound to 172.20.0.100 (DHCP Reservation)
        "500" = "00155D01C806" # Bound to 192.168.1.100 (DHCP Reservation)
        "700" = "00155D01C807" # Static 192.168.50.100 (No Gateway)
    }

    foreach ($vlan in $validVlans) {
        $vnicName = "VLAN-$vlan"
        $interfaceAlias = "vEthernet ($vnicName)"

        # Check if vNIC already exists
        $adapterExists = $vnicName -in $currentVNicNames

        if (-not $adapterExists) {
            Write-Host "Adding Virtual Adapter: $vnicName..." -ForegroundColor Cyan
            Add-VMNetworkAdapter -ManagementOS -SwitchName $switchName -Name $vnicName -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Milliseconds 800

            # Configure MAC Address
            if ($staticMacAddresses.ContainsKey($vlan)) {
                $rawMac = $staticMacAddresses[$vlan]
                Set-NetAdapterAdvancedProperty -Name $interfaceAlias -RegistryKeyword "NetworkAddress" -RegistryValue $rawMac -ErrorAction SilentlyContinue
            }

            # Configure VLAN Tagging
            if ($vlan -eq "1") {
                Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vnicName -Untagged -ErrorAction SilentlyContinue
            } else {
                Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vnicName -Access -VlanId ([int]$vlan) -ErrorAction SilentlyContinue
            }
        }

        # IP Configuration (Only configure if not already configured, or fix missing/broken IP to avoid dropping active RDP)
        if ($vlan -eq "1") {
            # VLAN 1 -> Static IP 192.168.30.2/24 (Untagged Native, No Default Gateway)
            $existingIPs = (Get-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
            
            # If 192.168.30.2 already exists alone, do NOT touch interface to preserve sessions
            if ($existingIPs -notcontains $mgmtIP -or ($existingIPs | Where-Object { $_ -ne $mgmtIP })) {
                Set-NetIPInterface -InterfaceAlias $interfaceAlias -Dhcp Disabled -ErrorAction SilentlyContinue
                Get-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                Remove-NetRoute -InterfaceAlias $interfaceAlias -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
                
                Start-Sleep -Milliseconds 400
                New-NetIPAddress -InterfaceAlias $interfaceAlias -IPAddress $mgmtIP -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
                Write-Host "  ✔ $vnicName -> VLAN 1 (Native) | Configured Static IP: $mgmtIP/24 (No Gateway)" -ForegroundColor Green
            } else {
                # Ensure no default route exists on VLAN 1
                Remove-NetRoute -InterfaceAlias $interfaceAlias -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
                Write-Host "  ✔ $vnicName -> VLAN 1 (Native) already active ($mgmtIP) [Preserved]" -ForegroundColor Green
            }

        } elseif ($vlan -eq "700") {
            # VLAN 700 -> Static IP 192.168.50.100/24 (Strictly NO Default Gateway)
            $existingIPs = (Get-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress

            if ($existingIPs -notcontains $vlan700IP -or ($existingIPs | Where-Object { $_ -ne $vlan700IP })) {
                Set-NetIPInterface -InterfaceAlias $interfaceAlias -Dhcp Disabled -ErrorAction SilentlyContinue
                Get-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                Remove-NetRoute -InterfaceAlias $interfaceAlias -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
                
                Start-Sleep -Milliseconds 400
                New-NetIPAddress -InterfaceAlias $interfaceAlias -IPAddress $vlan700IP -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
                Write-Host "  ✔ $vnicName -> VLAN 700 | Configured Static IP: $vlan700IP/24 (Strictly No Gateway)" -ForegroundColor Green
            } else {
                # Ensure default gateway route is strictly removed
                Remove-NetRoute -InterfaceAlias $interfaceAlias -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
                Write-Host "  ✔ $vnicName -> VLAN 700 already active ($vlan700IP) (No Gateway) [Preserved]" -ForegroundColor Green
            }

        } else {
            # VLANs 100, 400, 500 (DHCP)
            if (-not $adapterExists) {
                Set-NetIPInterface -InterfaceAlias $interfaceAlias -Dhcp Enabled -ErrorAction SilentlyContinue
                Set-DnsClientServerAddress -InterfaceAlias $interfaceAlias -ResetServerAddresses -ErrorAction SilentlyContinue
                Write-Host "  ✔ $vnicName -> VLAN $vlan / DHCP Enabled" -ForegroundColor Green
            } else {
                Write-Host "  ✔ $vnicName -> VLAN $vlan already active [Preserved]" -ForegroundColor Green
            }
        }
    }

    # NOTE: Other active VLANs are NOT deleted here to preserve RDP/remote connections!
    # Only 'vlan -Reset' (or option 'r') will tear down the environment.

    Write-Host "`nRequested VLAN configuration applied safely without dropping active connections!" -ForegroundColor Green
}
