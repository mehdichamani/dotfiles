<#
.SYNOPSIS
    Installs portable applications into %LOCALAPPDATA%\Programs, creates Start Menu shortcuts,
    and optionally adds executables to the User PATH via symlinks or shims.

.DESCRIPTION
    This script handles standalone .exe files or archives (.zip, .7z, .rar, .tar, .tar.gz, etc.):
    - Uses 7-Zip as the high-performance core extraction engine (with built-in Windows fallbacks)
    - Full support for password-protected archives (-Password parameter or interactive prompt)
    - Extracts/copies files to $env:LOCALAPPDATA\Programs\<AppName>
    - Automatically flattens redundant single-root archive folders
    - Interactively prompts for the main executable if multiple are detected
    - Creates a Start Menu shortcut (.lnk)
    - Adds an executable shim/symlink to $env:LOCALAPPDATA\Programs\bin (registered in User PATH)

.EXAMPLE
    .\Install-PortableApp.ps1 -Source ".\v2rayN-windows-64-desktop.zip" -AddToPath

.EXAMPLE
    .\Install-PortableApp.ps1 -Source ".\SecretApp.7z" -Password "12345"

.EXAMPLE
    .\Install-PortableApp.ps1 -Source ".\WinRAR_Archive.rar" -Name "MyWinRARApp"

.EXAMPLE
    .\Install-PortableApp.ps1 --help
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromPipeline = $true)]
    [string]$Source,

    [Parameter(Position = 1)]
    [string]$Name,

    [Parameter()]
    [string]$ExeName,

    [Parameter()]
    [Alias("p", "Pass")]
    [string]$Password,

    [Parameter()]
    [switch]$AddToPath,

    [Parameter()]
    [string]$Group = "",

    [Parameter()]
    [switch]$NoShortcut,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [Alias("h")]
    [switch]$Help
)

# Show help if requested
$isHelpRequested = $Help.IsPresent -or ($Source -in @('-h', '--help', '-help', '/?', 'help')) -or ($args -contains "--help") -or ($args -contains "-h") -or ($args -contains "/?")

if ($isHelpRequested) {
    Write-Host @"
===================================================================
        Portable Application Installer (v2.0 - 7-Zip Core)
===================================================================

Usage:
  pinstall [[-Source] <path>] [-Name <string>] [-ExeName <string>]
           [-Password <string>] [-AddToPath] [-Group <string>]
           [-NoShortcut] [-Force] [-Help]

Parameters:
  -Source <path>        Path to archive (.zip, .7z, .rar, .tar.*, etc.) or standalone .exe.
                        If omitted, interactive scanner shows all packages in current directory.
  -Name <string>        Custom installation folder and shortcut name.
                        Defaults to a cleaned-up version of the source file name.
  -ExeName <string>     Specific executable inside the package to target.
                        If omitted and multiple .exe files exist, you will be prompted.
  -Password, -p <str>   Password for encrypted/protected archives (.zip, .7z, .rar, etc.).
                        If required and omitted, you will be prompted interactively.
  -AddToPath            Creates a symlink (or .cmd shim) in %LOCALAPPDATA%\Programs\bin
                        and ensures this bin directory is in your User PATH.
  -Group <string>       Start Menu subfolder group (e.g. 'PortableApps' or 'Tools').
                        Default: Placed directly in Start Menu Programs.
  -NoShortcut           Skips creating a Start Menu shortcut.
  -Force                Overwrites existing installation folder if it already exists.
  -Help, -h, --help     Displays this help information.

Supported Formats:
  Archives:    .zip, .7z, .rar, .tar, .gz, .bz2, .xz, .tgz, .txz, .tbz2, .iso, .cab, .wim, .zst
  Executables: .exe

Examples:
  1) Scan and select from current directory:
     cd C:\Downloads
     pinstall

  2) Install from zip/7z/rar archive:
     pinstall .\v2rayN-windows-64-desktop.zip
     pinstall .\MyPackage.7z
     pinstall .\ToolBundle.rar

  3) Install password-protected archive:
     pinstall .\ProtectedApp.7z -Password "SecretPass123"

  4) Install and expose in PATH (e.g. sing-box, aeroftp, cli tools):
     pinstall .\sing-box.zip -AddToPath

  5) Install standalone executable with custom name and Start Menu folder:
     pinstall .\NovaWizard.exe -Name "Nova Wizard" -Group "PortableApps"

===================================================================
"@ -ForegroundColor Cyan
    return
}

# --- Helpers ---

function Find-7ZipExecutable {
    # 1. Check in PATH
    $cmd = Get-Command 7z.exe, 7za.exe, 7zr.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) {
        return $cmd.Source
    }

    # 2. Check standard installation paths
    $potentialPaths = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe",
        "$env:ProgramW6432\7-Zip\7z.exe",
        "$env:USERPROFILE\scoop\apps\7zip\current\7z.exe",
        "$env:USERPROFILE\scoop\shims\7z.exe",
        "$env:ChocolateyInstall\bin\7z.exe",
        "$PSScriptRoot\7-Zip\7z.exe",
        "$PSScriptRoot\7z.exe"
    )

    foreach ($path in $potentialPaths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    return $null
}

function Ensure-UserBinInPath {
    $binDir = Join-Path $env:LOCALAPPDATA "Programs\bin"
    if (-not (Test-Path -LiteralPath $binDir)) {
        New-Item -Path $binDir -ItemType Directory -Force | Out-Null
    }

    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $pathParts = if ($userPath) { $userPath -split ';' } else { @() }
    
    $normalizedBin = (Resolve-Path -LiteralPath $binDir).Path
    $exists = $pathParts | Where-Object { 
        $_ -and (Test-Path -LiteralPath $_) -and ((Resolve-Path -LiteralPath $_ -ErrorAction SilentlyContinue).Path -eq $normalizedBin)
    }

    if (-not $exists) {
        Write-Host "Adding '$binDir' to User PATH environment variable..." -ForegroundColor Yellow
        $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $binDir } else { "$userPath;$binDir" }
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        $env:PATH = "$binDir;$env:PATH"
        Write-Host "PATH updated successfully. (Active in this session and all future new terminals)" -ForegroundColor Green
    }

    return $binDir
}

function Create-AppShimOrSymlink {
    param(
        [string]$BinDir,
        [string]$TargetExePath,
        [string]$AliasName
    )

    $exeBaseName = [System.IO.Path]::GetFileNameWithoutExtension($TargetExePath)
    $shimBase = if ($AliasName) { $AliasName } else { $exeBaseName }
    $symlinkPath = Join-Path $BinDir "$shimBase.exe"
    $cmdShimPath = Join-Path $BinDir "$shimBase.cmd"

    # Remove existing symlink or cmd shim if present
    if (Test-Path -LiteralPath $symlinkPath) { Remove-Item -LiteralPath $symlinkPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $cmdShimPath) { Remove-Item -LiteralPath $cmdShimPath -Force -ErrorAction SilentlyContinue }

    # Try creating symbolic link first
    $symlinkSuccess = $false
    try {
        New-Item -Path $symlinkPath -ItemType SymbolicLink -Value $TargetExePath -Force -ErrorAction Stop | Out-Null
        $symlinkSuccess = $true
        Write-Host "Created PATH symlink: $symlinkPath -> $TargetExePath" -ForegroundColor Green
    }
    catch {
        $symlinkSuccess = $false
    }

    # Fallback to .cmd shim if symlink is not permitted (e.g. Developer mode disabled)
    if (-not $symlinkSuccess) {
        $cmdContent = "@echo off`r`n`"$TargetExePath`" %*"
        Set-Content -LiteralPath $cmdShimPath -Value $cmdContent -Encoding ASCII -Force
        Write-Host "Created PATH command shim: $cmdShimPath -> $TargetExePath" -ForegroundColor Green
    }
}

function Create-StartMenuShortcut {
    param(
        [string]$DisplayName,
        [string]$TargetExePath,
        [string]$SubGroup = ""
    )

    $startMenuBase = [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs")
    $shortcutDir = if ($SubGroup) { Join-Path $startMenuBase $SubGroup } else { $startMenuBase }

    if (-not (Test-Path -LiteralPath $shortcutDir)) {
        New-Item -Path $shortcutDir -ItemType Directory -Force | Out-Null
    }

    $shortcutFile = Join-Path $shortcutDir "$DisplayName.lnk"
    $workDir = [System.IO.Path]::GetDirectoryName($TargetExePath)

    try {
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutFile)
        $shortcut.TargetPath = $TargetExePath
        $shortcut.WorkingDirectory = $workDir
        $shortcut.IconLocation = "$TargetExePath,0"
        $shortcut.Save()
        Write-Host "Created Start Menu Shortcut: $shortcutFile" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create Start Menu shortcut: $_"
    }
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Clean-AppName {
    param([string]$RawName)
    # Strip compound archive extensions if any
    $clean = $RawName -replace '(?i)\.(tar\.(gz|bz2|xz|zst)|tgz|txz|tbz2|zip|7z|rar|iso|cab|wim|exe)$', ''
    $clean = $clean -replace '[-_\.](portable|windows|win64|win32|amd64|x64|x86|desktop|setup|v?\d+(\.\d+)*)+', ''
    $clean = $clean -replace '[-_.]+', ' '
    $clean = $clean.Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return $RawName }
    return $clean
}

function Prompt-ArchivePassword {
    param([string]$PromptMessage = "Archive is password protected. Enter password")
    
    # Check if Read-Host supports -MaskInput (PowerShell 7+)
    $supportsMask = (Get-Command Read-Host).Parameters.ContainsKey('MaskInput')
    if ($supportsMask) {
        $pw = Read-Host $PromptMessage -MaskInput
    } else {
        # PowerShell 5.1 fallback: read as SecureString and convert to plain text
        $secPw = Read-Host $PromptMessage -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPw)
        try {
            $pw = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    return $pw
}

# --- Archive Extensions Definition ---
$supportedArchiveExts = @('.zip', '.7z', '.rar', '.tar', '.gz', '.bz2', '.xz', '.tgz', '.txz', '.tbz2', '.iso', '.cab', '.wim', '.zst')
$allSupportedExts = $supportedArchiveExts + @('.exe')

# Resolve relative path if -Source was provided
if ($Source) {
    if (-not [System.IO.Path]::IsPathRooted($Source)) {
        $resolvedSource = Join-Path (Get-Location).Path $Source
        if (Test-Path -LiteralPath $resolvedSource) {
            $Source = (Resolve-Path -LiteralPath $resolvedSource).Path
        }
    }
}

$isInteractiveMode = $false

# --- Interactive Source Selection if not provided ---
if (-not $Source) {
    $isInteractiveMode = $true
    $currentDir = (Get-Location).Path
    $candidates = @(Get-ChildItem -LiteralPath $currentDir -File -ErrorAction SilentlyContinue | Where-Object { 
        $ext = $_.Extension.ToLower()
        ($ext -in $allSupportedExts -or $_.Name -match '(?i)\.tar\.(gz|bz2|xz|zst)$') -and 
        $ext -ne '.ps1' -and $ext -ne '.cmd' -and $ext -ne '.bat' -and $ext -ne '.sh' -and
        $_.Name -notmatch '(?i)(PortableInstaller|Install-PortableApp)'
    } | Sort-Object Name)

    if ($candidates.Count -eq 0) {
        Write-Host "`n⚠️  No supported archives or .exe files found in: $currentDir" -ForegroundColor Yellow
        Write-Host "Supported: $($allSupportedExts -join ', ')" -ForegroundColor Gray
        Write-Host "Usage: pinstall [source_file] [-AddToPath] [-Name <name>]" -ForegroundColor Cyan
        return
    }

    Write-Host "`n📦 Found $($candidates.Count) installable package(s) in: $currentDir" -ForegroundColor Cyan
    Write-Host ("-" * 72) -ForegroundColor DarkGray
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $item = $candidates[$i]
        $sizeStr = Format-FileSize -Bytes $item.Length
        $typeLabel = if ($item.Extension.ToLower() -eq '.exe') { "Executable" } else { "Archive" }
        Write-Host ("  [{0}] {1,-44} {2,9}  [{3}]" -f ($i + 1), $item.Name, $sizeStr, $typeLabel) -ForegroundColor White
    }
    Write-Host ("-" * 72) -ForegroundColor DarkGray

    if ($candidates.Count -eq 1) {
        $choice = Read-Host "`nEnter selection [Default: 1] or Q to quit"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
    } else {
        $choice = Read-Host "`nEnter selection (1-$($candidates.Count)) or Q to quit"
    }

    if ($choice -match '^[Qq]') {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
        return
    }

    $index = [int]$choice - 1
    if ($index -ge 0 -and $index -lt $candidates.Count) {
        $Source = $candidates[$index].FullName
    } else {
        Write-Error "Invalid selection '$choice'."
        return
    }
}

if (-not (Test-Path -LiteralPath $Source)) {
    Write-Error "Source file not found: '$Source'"
    return
}

$sourceItem = Get-Item -LiteralPath $Source
$sourceExt = $sourceItem.Extension.ToLower()
$isArchive = ($sourceExt -in $supportedArchiveExts) -or ($sourceItem.Name -match '(?i)\.tar\.(gz|bz2|xz|zst)$')

if (-not $isArchive -and $sourceExt -ne '.exe') {
    Write-Error "Unsupported file format '$sourceExt'. Supported: $($allSupportedExts -join ', ')"
    return
}

# Determine App Name
if (-not $Name) {
    $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($sourceItem.Name)
    $suggestedName = Clean-AppName -RawName $baseFileName
    
    if ($isInteractiveMode) {
        $inputName = Read-Host "`nEnter application name [Default: '$suggestedName']"
        $Name = if ([string]::IsNullOrWhiteSpace($inputName)) { $suggestedName } else { $inputName.Trim() }
    } else {
        $Name = $suggestedName
    }
}

# Prompt for AddToPath if run interactively and not specified via parameter
if ($isInteractiveMode -and -not $PSBoundParameters.ContainsKey('AddToPath')) {
    $askPath = Read-Host "`nAdd application to User PATH (%LOCALAPPDATA%\Programs\bin)? (y/N)"
    if ($askPath -eq 'y' -or $askPath -eq 'Y') {
        $AddToPath = [switch]::new($true)
    }
}

Write-Host "`n>>> Processing '$Name' from '$($sourceItem.Name)'..." -ForegroundColor Cyan

# Installation Destination
$programsBase = Join-Path $env:LOCALAPPDATA "Programs"
$appDestDir = Join-Path $programsBase $Name

if (Test-Path -LiteralPath $appDestDir) {
    if ($Force) {
        Write-Host "Removing existing installation at '$appDestDir' (-Force specified)..." -ForegroundColor Yellow
        Remove-Item -LiteralPath $appDestDir -Recurse -Force
    } else {
        $overwrite = Read-Host "Directory '$appDestDir' already exists. Overwrite? (y/N)"
        if ($overwrite -eq 'y' -or $overwrite -eq 'Y') {
            Remove-Item -LiteralPath $appDestDir -Recurse -Force
        } else {
            Write-Host "Installation cancelled by user." -ForegroundColor Yellow
            return
        }
    }
}

New-Item -Path $appDestDir -ItemType Directory -Force | Out-Null

# --- Extract or Copy ---
if ($isArchive) {
    Write-Host "Extracting archive to '$appDestDir'..." -ForegroundColor Cyan
    
    $extracted = $false
    $sevenZipExe = Find-7ZipExecutable

    if ($sevenZipExe) {
        Write-Host "Using 7-Zip engine: $sevenZipExe" -ForegroundColor Gray
        
        $currentPassword = $Password
        $maxPasswordAttempts = 3
        $attempt = 0

        while (-not $extracted -and $attempt -lt $maxPasswordAttempts) {
            $attempt++
            $pSwitch = if (-not [string]::IsNullOrEmpty($currentPassword)) { "-p$currentPassword" } else { "-p" }
            
            # Execute 7-Zip
            $processOutput = & $sevenZipExe x -y -aoa -o"$appDestDir" $pSwitch $sourceItem.FullName 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                $extracted = $true
                Write-Host "Extraction completed successfully via 7-Zip." -ForegroundColor Green
                break
            }

            # Check if failure is password-related
            $outputText = ($processOutput | Out-String)
            $isPasswordIssue = ($outputText -match '(?i)(wrong password|enter password|encrypted|data error in encrypted|can not open encrypted)') -or ($exitCode -eq 2)

            if ($isPasswordIssue) {
                if (-not [string]::IsNullOrEmpty($currentPassword)) {
                    Write-Warning "Incorrect password provided (Attempt $attempt of $maxPasswordAttempts)."
                }
                
                if ($attempt -lt $maxPasswordAttempts) {
                    $promptText = if ([string]::IsNullOrEmpty($currentPassword)) {
                        "Archive is password protected. Enter password (or 'q' to cancel): "
                    } else {
                        "Enter password again (or 'q' to cancel): "
                    }
                    $entered = Prompt-ArchivePassword -PromptMessage $promptText
                    if ($entered -match '^[Qq]$' -or [string]::IsNullOrEmpty($entered)) {
                        Write-Host "Extraction cancelled by user." -ForegroundColor Yellow
                        break
                    }
                    $currentPassword = $entered
                }
            } else {
                # Non-password error with 7-Zip
                Write-Warning "7-Zip extraction encountered an error (Exit code $exitCode):`n$outputText"
                break
            }
        }
    } else {
        Write-Warning "7-Zip was not found on your system."
    }

    # Fallback attempt 1: Windows built-in tar.exe (if 7-Zip not available and format is supported)
    if (-not $extracted -and ($sourceExt -in @('.zip', '.tar', '.gz', '.tgz'))) {
        $tarCmd = Get-Command tar.exe -ErrorAction SilentlyContinue
        if ($tarCmd) {
            Write-Host "Attempting fallback extraction with Windows tar.exe..." -ForegroundColor Gray
            try {
                $prevEAP = $ErrorActionPreference
                $ErrorActionPreference = 'SilentlyContinue'
                & tar.exe -xf $sourceItem.FullName -C $appDestDir *>$null
                $ErrorActionPreference = $prevEAP

                if ((Get-ChildItem -LiteralPath $appDestDir).Count -gt 0) {
                    $extracted = $true
                    Write-Host "Extraction completed via tar.exe." -ForegroundColor Green
                }
            } catch {
                $extracted = $false
            }
        }
    }

    # Fallback attempt 2: Standard PowerShell Expand-Archive (for .zip only)
    if (-not $extracted -and $sourceExt -eq '.zip') {
        Write-Host "Attempting fallback extraction with Expand-Archive..." -ForegroundColor Gray
        try {
            Expand-Archive -LiteralPath $sourceItem.FullName -DestinationPath $appDestDir -Force
            $extracted = $true
            Write-Host "Extraction completed via Expand-Archive." -ForegroundColor Green
        } catch {
            $extracted = $false
        }
    }

    if (-not $extracted) {
        if (-not $sevenZipExe -and ($sourceExt -in @('.7z', '.rar') -or $Password)) {
            Write-Error "Failed to extract '$($sourceItem.Name)'. 7-Zip is required for $($sourceExt) and password-protected archives.`nPlease install 7-Zip (e.g. 'winget install 7zip.7zip' or download from 7-zip.org)."
        } else {
            Write-Error "Failed to extract archive '$($sourceItem.Name)'."
        }
        # Clean up empty destination folder
        if (Test-Path -LiteralPath $appDestDir) {
            $remaining = Get-ChildItem -LiteralPath $appDestDir
            if ($remaining.Count -eq 0) {
                Remove-Item -LiteralPath $appDestDir -Force -ErrorAction SilentlyContinue
            }
        }
        return
    }

    # Check for single nested folder flattening
    $childItems = Get-ChildItem -LiteralPath $appDestDir
    if ($childItems.Count -eq 1 -and $childItems[0].PSIsContainer) {
        $nestedFolder = $childItems[0].FullName
        Write-Host "Flattening single root folder '$($childItems[0].Name)'..." -ForegroundColor Gray
        $nestedItems = Get-ChildItem -LiteralPath $nestedFolder
        foreach ($item in $nestedItems) {
            Move-Item -LiteralPath $item.FullName -Destination $appDestDir -Force
        }
        if (Test-Path -LiteralPath $nestedFolder) {
            Remove-Item -LiteralPath $nestedFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
elseif ($sourceExt -eq '.exe') {
    Write-Host "Copying executable to '$appDestDir'..." -ForegroundColor Cyan
    Copy-Item -LiteralPath $sourceItem.FullName -Destination (Join-Path $appDestDir $sourceItem.Name) -Force
}

# --- Detect Target Executable ---
$allExes = Get-ChildItem -LiteralPath $appDestDir -Filter "*.exe" -Recurse | Where-Object {
    $_.Name -notmatch '(?i)(uninstall|unins\d+|vc_redist|helper|crashpad|elevate)'
}

if ($allExes.Count -eq 0) {
    # Fallback to any exe if filtered list is empty
    $allExes = Get-ChildItem -LiteralPath $appDestDir -Filter "*.exe" -Recurse
}

$targetExePath = $null

if ($ExeName) {
    $matched = $allExes | Where-Object { $_.Name -like "*$ExeName*" } | Select-Object -First 1
    if ($matched) {
        $targetExePath = $matched.FullName
    } else {
        Write-Warning "Specified -ExeName '$ExeName' was not found in package."
    }
}

if (-not $targetExePath) {
    if ($allExes.Count -eq 0) {
        Write-Warning "No executable (.exe) found in '$appDestDir'."
    }
    elseif ($allExes.Count -eq 1) {
        $targetExePath = $allExes[0].FullName
        Write-Host "Selected main executable: $($allExes[0].Name)" -ForegroundColor Green
    }
    else {
        # Multiple executables found: prompt user
        Write-Host "`nMultiple executables found. Please select the primary application executable:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $allExes.Count; $i++) {
            $relPath = $allExes[$i].FullName.Substring($appDestDir.Length).TrimStart('\', '/')
            Write-Host "  [$($i + 1)] $relPath"
        }
        
        $sel = Read-Host "`nEnter number (1-$($allExes.Count)) [Default: 1]"
        if ([string]::IsNullOrWhiteSpace($sel)) { $sel = "1" }
        $idx = [int]$sel - 1
        if ($idx -ge 0 -and $idx -lt $allExes.Count) {
            $targetExePath = $allExes[$idx].FullName
        } else {
            $targetExePath = $allExes[0].FullName
        }
        Write-Host "Selected: $targetExePath" -ForegroundColor Green
    }
}

# --- Create Start Menu Shortcut ---
if (-not $NoShortcut -and $targetExePath) {
    Create-StartMenuShortcut -DisplayName $Name -TargetExePath $targetExePath -SubGroup $Group
}

# --- Add to User PATH if requested ---
if ($AddToPath -and $targetExePath) {
    $binDir = Ensure-UserBinInPath
    Create-AppShimOrSymlink -BinDir $binDir -TargetExePath $targetExePath -AliasName ($Name -replace '\s+', '')
}

Write-Host "`n===================================================================" -ForegroundColor Green
Write-Host " Installation of '$Name' completed successfully!" -ForegroundColor Green
Write-Host " Installed at: $appDestDir" -ForegroundColor Gray
if ($targetExePath) {
    Write-Host " Target Executable: $targetExePath" -ForegroundColor Gray
}
if ($AddToPath) {
    Write-Host " Available in PATH as: $([System.IO.Path]::GetFileNameWithoutExtension($targetExePath))" -ForegroundColor Cyan
}
Write-Host "===================================================================`n" -ForegroundColor Green
