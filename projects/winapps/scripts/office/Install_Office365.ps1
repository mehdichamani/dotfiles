# Office 365 Offline Installer (Word, Excel, PowerPoint)
# Requires Administrator privileges

$ErrorActionPreference = "Stop"

# Check Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[*] Restarting as Administrator..." -ForegroundColor Cyan
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "========================================================" -ForegroundColor Green
Write-Host "    Office 365 Offline Installer (Word, Excel, PPT)    " -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""

$workDir = $null

# 1. Check if files are directly in the script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ((Test-Path "$scriptDir\ODT.exe") -and (Test-Path "$scriptDir\Office\Data")) {
    $workDir = "$scriptDir\"
    Write-Host "[*] Found Office media in current directory: $workDir" -ForegroundColor Cyan
}

# 2. Search mounted drives D: through Z:
if (-not $workDir) {
    Write-Host "[*] Scanning drives for mounted Office ISO..." -ForegroundColor Yellow
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -match '^[D-Z]$' }
    foreach ($drive in $drives) {
        $root = "$($drive.Name):\"
        if ((Test-Path "$root\ODT.exe") -and (Test-Path "$root\Office\Data")) {
            $workDir = $root
            Write-Host "[*] Detected mounted Office media at drive: $workDir" -ForegroundColor Green
            break
        }
    }
}

if (-not $workDir) {
    Write-Host "[!] ERROR: Could not find mounted Office drive with ODT.exe and Office\Data!" -ForegroundColor Red
    Write-Host "[!] Please make sure the ISO is mounted to a drive letter." -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit 1
}

# 3. Create offline configuration XML
$xmlPath = "$env:TEMP\office365_offline.xml"
$xmlContent = @"
<Configuration>
  <Add SourcePath="$workDir" OfficeClientEdition="64" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-us" />
      <ExcludeApp ID="Outlook" />
      <ExcludeApp ID="OneNote" />
      <ExcludeApp ID="Access" />
      <ExcludeApp ID="Publisher" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="OneDrive" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="Teams" />
      <ExcludeApp ID="Bing" />
    </Product>
  </Add>
  <Property Name="SharedComputerLicensing" Value="0" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Property Name="DeviceBasedLicensing" Value="0" />
  <Property Name="SCLCacheOverride" Value="0" />
  <Property Name="AUTOACTIVATE" Value="0" />
  <Display Level="Full" AcceptEULA="TRUE" />
  <Updates Enabled="FALSE" />
  <RemoveMSI />
</Configuration>
"@

Set-Content -Path $xmlPath -Value $xmlContent -Encoding UTF8
Write-Host "[*] Generated config at: $xmlPath" -ForegroundColor Cyan
Write-Host "[*] Launching ODT Installer from $workDir\ODT.exe ..." -ForegroundColor Cyan
Write-Host ""

$odtExe = "$workDir\ODT.exe"
$process = Start-Process -FilePath $odtExe -ArgumentList "/configure `"$xmlPath`"" -Wait -PassThru

if ($process.ExitCode -eq 0) {
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "  [+] Office 365 installed successfully!" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    
    $activator = "$workDir\Activator.cmd"
    if (Test-Path $activator) {
        $ans = Read-Host "Do you want to activate Office now using Ohook? (Y/N)"
        if ($ans -match '^[yY]') {
            Write-Host "[*] Running Ohook activation..." -ForegroundColor Cyan
            Start-Process -FilePath $activator -ArgumentList "/Ohook" -Wait
        }
    }
} else {
    Write-Host ""
    Write-Host "[!] Installation finished with exit code: $($process.ExitCode)" -ForegroundColor Red
}

Remove-Item $xmlPath -ErrorAction SilentlyContinue
Read-Host "Press Enter to exit..."
