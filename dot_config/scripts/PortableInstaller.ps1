<#
.SYNOPSIS
    Installs portable applications into %LOCALAPPDATA%\Programs, creates Start Menu shortcuts,
    and optionally adds executables to the User PATH via symlinks or shims.
    Supports listing installed apps, uninstallation, and direct GitHub repo / URL releases.

.DESCRIPTION
    This script handles standalone .exe files or archives (.zip, .7z, .rar, .tar, .tar.gz, etc.):
    - GitHub Release discovery & downloading (e.g. 'owner/repo', 'owner/repo@tag', or GitHub URL)
    - Direct HTTP/HTTPS URL download support
    - 7-Zip as the high-performance core extraction engine (with built-in Windows tar / Expand-Archive fallbacks)
    - Full support for password-protected archives (-Password parameter or interactive prompt)
    - Extracts/copies files to $env:LOCALAPPDATA\Programs\<AppName>
    - Automatically flattens redundant single-root archive folders
    - Interactively prompts for the main executable if multiple are detected
    - Creates a Start Menu shortcut (.lnk)
    - Adds an executable shim/symlink to $env:LOCALAPPDATA\Programs\bin (registered in User PATH)
    - Manages receipt metadata (.pinstall.json) for clean tracking
    - Lists (-List) and cleanly uninstalls (-Uninstall) applications, shortcuts, and PATH shims

.EXAMPLE
    pinstall owner/repo -AddToPath

.EXAMPLE
    pinstall https://github.com/fastfetch-cli/fastfetch/releases/download/2.38.0/fastfetch-windows-amd64.zip -AddToPath

.EXAMPLE
    pinstall -List

.EXAMPLE
    pinstall -Uninstall v2rayN -Yes

.EXAMPLE
    pinstall -Source ".\SecretApp.7z" -Password "12345"
#>

[CmdletBinding(DefaultParameterSetName = "Install")]
param(
    [Parameter(ParameterSetName = "Install", Position = 0, ValueFromPipeline = $true)]
    [string]$Source,

    [Parameter(ParameterSetName = "Install", Position = 1)]
    [string]$Name,

    [Parameter(ParameterSetName = "Install")]
    [Alias("e", "Bin")]
    [string]$ExeName,

    [Parameter(ParameterSetName = "Install")]
    [Alias("p", "Pass")]
    [string]$Password,

    [Parameter(ParameterSetName = "Install")]
    [Alias("Path")]
    [switch]$AddToPath,

    [Parameter(ParameterSetName = "Install")]
    [string]$Group = "",

    [Parameter(ParameterSetName = "Install")]
    [Alias("NoDesktop")]
    [switch]$NoShortcut,

    [Parameter(ParameterSetName = "Install")]
    [Alias("f")]
    [switch]$Force,

    [Parameter(ParameterSetName = "List")]
    [Alias("l")]
    [switch]$List,

    [Parameter(ParameterSetName = "Uninstall")]
    [Alias("u", "Remove")]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = "Uninstall", Position = 0)]
    [string]$UninstallName,

    [Parameter(ParameterSetName = "Uninstall")]
    [Alias("y")]
    [switch]$Yes,

    [Parameter()]
    [Alias("h")]
    [switch]$Help
)

# --- Check Help Request ---
$isHelpRequested = $Help.IsPresent -or 
    ($Source -in @('-h', '--help', '-help', '/?', 'help')) -or 
    ($args -contains "--help") -or ($args -contains "-h") -or ($args -contains "/?")

if ($isHelpRequested) {
    Write-Host @"
===================================================================
        Portable Application Installer for Windows (pinstall)
===================================================================

Usage:
  pinstall [source|url|github_repo] [options]
  pinstall -l | --list | -List
  pinstall -u | --uninstall | -Uninstall [name] [-y | -Yes]

Management Options:
  -List, -l                 List all installed portable applications and their details.
  -Uninstall, -u [name]     Uninstall an application (removes files, Start Menu shortcut, and PATH shim).
                            If no name is provided, prompts with an interactive list.
  -Yes, -y                  Skip confirmation prompts during uninstallation.

Installation Options:
  -Source, -s <src>         Path to archive/executable, direct download URL, or GitHub repo/release.
                            (e.g., 'owner/repo', 'owner/repo@v1.0', 'https://github.com/...', 'https://...').
                            If omitted, scans current directory for installable packages.
  -Name, -n <string>        Custom application name and installation folder name.
                            Defaults to a cleaned-up version of the source file name.
  -ExeName, -e, -Bin <str>  Specific executable inside the package to target.
                            If omitted and multiple .exe files exist, you will be prompted.
  -Password, -p <str>       Password for encrypted/protected archives (.zip, .7z, .rar, etc.).
                            If required and omitted, you will be prompted interactively.
  -AddToPath, -Path         Creates a symlink (or .cmd shim) in %LOCALAPPDATA%\Programs\bin
                            and ensures this bin directory is in your User PATH.
  -Group <string>           Start Menu subfolder group (e.g. 'PortableApps' or 'Tools').
                            Default: Placed directly in Start Menu Programs.
  -NoShortcut, -NoDesktop   Skips creating a Start Menu shortcut.
  -Force, -f                Overwrites existing installation folder if it already exists.
  -Help, -h, --help         Displays this help information.

Supported Formats & Sources:
  GitHub Repos: GitHub repository (e.g. 'fastfetch-cli/fastfetch', 'jgraph/drawio-desktop')
  Direct URLs:  HTTP/HTTPS links to release archives or standalone .exe files
  Archives:     .zip, .7z, .rar, .tar, .tar.gz, .tgz, .tar.xz, .txz, .tar.zst, .tar.bz2, .tbz2, .iso
  Executables:  Standalone .exe files

Examples:
  1) Install from GitHub repository (auto-discovers latest Windows release):
     pinstall fastfetch-cli/fastfetch -AddToPath
     pinstall https://github.com/jgraph/drawio-desktop
     pinstall obsidianmd/obsidian-releases@v1.7.7

  2) Install from direct download URL:
     pinstall https://example.com/software/tool-windows-x64.zip -AddToPath

  3) Install from local archive:
     pinstall .\v2rayN-windows-64-desktop.zip
     pinstall .\sing-box.zip -AddToPath

  4) Scan and select interactively from current directory:
     cd C:\Downloads
     pinstall

  5) List or uninstall installed portable applications:
     pinstall -List
     pinstall -Uninstall "Obsidian" -Yes
===================================================================
"@ -ForegroundColor Cyan
    return
}

# --- Handle forwarded arguments / flag-style invocations ---
# e.g., pinstall --list, pinstall -l, pinstall --uninstall, pinstall -u
if ($PSCmdlet.ParameterSetName -eq "Install") {
    if ($Source -in @('-l', '--list', 'list')) {
        $List = [switch]::new($true)
    }
    elseif ($Source -in @('-u', '--uninstall', '-remove', '--remove', 'uninstall')) {
        $Uninstall = [switch]::new($true)
        $UninstallName = $Name
    }
}

# --- Helper Functions ---

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Clean-AppName {
    param([string]$RawName)
    $clean = [System.IO.Path]::GetFileNameWithoutExtension($RawName)
    $clean = $clean -replace '(?i)\.(tar\.(gz|bz2|xz|zst)|tgz|txz|tbz2|zip|7z|rar|iso|cab|wim|exe)$', ''
    $clean = $clean -replace '(?i)[-_\.](windows|win64|win32|amd64|x86_64|x64|x86|arm64|portable|standalone|desktop|setup|bin|msi|zip)+', ''
    $clean = $clean -replace '(?i)[-_\.]v?\d+(\.\d+)*([-_]?(beta|alpha|rc|patch|preview)\d*)?', ''
    $clean = $clean -replace '[-_.]+', ' '
    $clean = $clean.Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return [System.IO.Path]::GetFileNameWithoutExtension($RawName) }
    return $clean
}

function Get-Slug {
    param([string]$InputText)
    $s = $InputText.ToLower() -replace '[^a-z0-9]+', '-'
    return $s.Trim('-')
}

function Find-7ZipExecutable {
    $cmd = Get-Command 7z.exe, 7za.exe, 7zr.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) {
        return $cmd.Source
    }

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

    foreach ($p in $potentialPaths) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            return (Resolve-Path -LiteralPath $p).Path
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
        Write-Host "PATH updated successfully. (Active in this session and future new terminals)" -ForegroundColor Green
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

    if (Test-Path -LiteralPath $symlinkPath) { Remove-Item -LiteralPath $symlinkPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $cmdShimPath) { Remove-Item -LiteralPath $cmdShimPath -Force -ErrorAction SilentlyContinue }

    $createdPath = $null
    try {
        New-Item -Path $symlinkPath -ItemType SymbolicLink -Value $TargetExePath -Force -ErrorAction Stop | Out-Null
        Write-Host "Created PATH symlink: $symlinkPath -> $TargetExePath" -ForegroundColor Green
        $createdPath = $symlinkPath
    }
    catch {
        $cmdContent = "@echo off`r`n`"$TargetExePath`" %*"
        Set-Content -LiteralPath $cmdShimPath -Value $cmdContent -Encoding ASCII -Force
        Write-Host "Created PATH command shim: $cmdShimPath -> $TargetExePath" -ForegroundColor Green
        $createdPath = $cmdShimPath
    }

    return $createdPath
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
        return $shortcutFile
    }
    catch {
        Write-Warning "Failed to create Start Menu shortcut: $_"
        return $null
    }
}

function Prompt-ArchivePassword {
    param([string]$PromptMessage = "Archive is password protected. Enter password")
    
    $supportsMask = (Get-Command Read-Host).Parameters.ContainsKey('MaskInput')
    if ($supportsMask) {
        $pw = Read-Host $PromptMessage -MaskInput
    } else {
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

# --- Metadata Receipt Management ---
function Read-Receipt {
    param([string]$AppDir)
    $receiptPath = Join-Path $AppDir ".pinstall.json"
    if (Test-Path -LiteralPath $receiptPath) {
        try {
            $content = Get-Content -LiteralPath $receiptPath -Raw -ErrorAction Stop
            return ($content | ConvertFrom-Json)
        } catch {
            return $null
        }
    }
    return $null
}

function Write-Receipt {
    param(
        [string]$AppDir,
        [hashtable]$Data
    )
    $receiptPath = Join-Path $AppDir ".pinstall.json"
    try {
        $json = $Data | ConvertTo-Json -Depth 4
        Set-Content -LiteralPath $receiptPath -Value $json -Encoding UTF8 -Force
        return $receiptPath
    } catch {
        return $null
    }
}

# --- Installed Apps Discovery ---
function Get-InstalledApps {
    $programsBase = Join-Path $env:LOCALAPPDATA "Programs"
    if (-not (Test-Path -LiteralPath $programsBase)) {
        return @()
    }

    $apps = [System.Collections.Generic.List[PSCustomObject]]::new()
    $startMenuBase = [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs")
    $binDir = Join-Path $env:LOCALAPPDATA "Programs\bin"

    $dirs = Get-ChildItem -LiteralPath $programsBase -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notin @('bin', 'Common') }

    foreach ($dir in $dirs) {
        $receipt = Read-Receipt -AppDir $dir.FullName
        $appName = if ($receipt -and $receipt.name) { $receipt.name } else { $dir.Name }

        # Calculate directory size
        $sizeBytes = 0
        try {
            $meas = Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | 
                Measure-Object -Property Length -Sum
            if ($meas -and $meas.Sum) { $sizeBytes = $meas.Sum }
        } catch {}

        # Discover shortcut
        $shortcutPath = $null
        if ($receipt -and $receipt.shortcut_path -and (Test-Path -LiteralPath $receipt.shortcut_path)) {
            $shortcutPath = $receipt.shortcut_path
        } else {
            # Search Start Menu for matching .lnk
            $candidateLnk = Get-ChildItem -LiteralPath $startMenuBase -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue |
                Where-Object { 
                    $_.BaseName -ieq $appName -or $_.BaseName -ieq $dir.Name
                } | Select-Object -First 1
            if ($candidateLnk) { $shortcutPath = $candidateLnk.FullName }
        }

        # Discover PATH shim / symlink
        $shimPath = $null
        if ($receipt -and $receipt.bin_link -and (Test-Path -LiteralPath $receipt.bin_link)) {
            $shimPath = $receipt.bin_link
        } else {
            if (Test-Path -LiteralPath $binDir) {
                $candidateShim = Get-ChildItem -LiteralPath $binDir -File -ErrorAction SilentlyContinue |
                    Where-Object { 
                        $_.BaseName -ieq ($appName -replace '\s+', '') -or 
                        $_.BaseName -ieq $dir.Name -or 
                        $_.BaseName -ieq $appName
                    } | Select-Object -First 1
                if ($candidateShim) { $shimPath = $candidateShim.FullName }
            }
        }

        $installDate = if ($receipt -and $receipt.installed_at) { 
            ($receipt.installed_at -split 'T')[0] 
        } else { 
            $dir.CreationTime.ToString("yyyy-MM-dd") 
        }

        $apps.Add([PSCustomObject]@{
            Name         = $appName
            Directory    = $dir.FullName
            SizeBytes    = $sizeBytes
            SizeDisplay  = Format-FileSize -Bytes $sizeBytes
            Shortcut     = $shortcutPath
            Shim         = $shimPath
            Receipt      = $receipt
            InstallDate  = $installDate
        })
    }

    return $apps.ToArray()
}

# =============================================================================
# ACTION: List Installed Apps
# =============================================================================
if ($List) {
    $apps = Get-InstalledApps
    Write-Host "`n===================================================================" -ForegroundColor Cyan
    Write-Host "         INSTALLED PORTABLE APPLICATIONS ($($apps.Count) found)                 " -ForegroundColor Cyan
    Write-Host "===================================================================" -ForegroundColor Cyan

    if ($apps.Count -eq 0) {
        Write-Host "  No portable applications found in %LOCALAPPDATA%\Programs." -ForegroundColor DarkGray
        Write-Host "===================================================================`n" -ForegroundColor Cyan
        return
    }

    Write-Host ("  {0,-24} {1,-10} {2,-18} {3,-12} {4,-16}" -f "Application Name", "Size", "CLI Command", "Start Menu", "Installed Date") -ForegroundColor White
    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkGray

    foreach ($app in $apps) {
        $cliName = if ($app.Shim) { [System.IO.Path]::GetFileName($app.Shim) } else { "-" }
        $menuStatus = if ($app.Shortcut) { "Yes" } else { "No" }
        $dispName = if ($app.Name.Length -gt 23) { $app.Name.Substring(0, 20) + "..." } else { $app.Name }
        $dispCli = if ($cliName.Length -gt 17) { $cliName.Substring(0, 15) + ".." } else { $cliName }

        Write-Host ("  {0,-24} {1,-10} {2,-18} {3,-12} {4,-16}" -f $dispName, $app.SizeDisplay, $dispCli, $menuStatus, $app.InstallDate)
    }

    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkGray
    Write-Host "  Tip: Run 'pinstall -u <name>' or 'pinstall -u' to remove an application." -ForegroundColor DarkGray
    Write-Host "===================================================================`n" -ForegroundColor Cyan
    return
}

# =============================================================================
# ACTION: Uninstall Application
# =============================================================================
if ($Uninstall) {
    $apps = Get-InstalledApps
    if ($apps.Count -eq 0) {
        Write-Warning "No portable applications found to uninstall in %LOCALAPPDATA%\Programs."
        return
    }

    $selectedApp = $null

    if (-not [string]::IsNullOrWhiteSpace($UninstallName)) {
        # Match by exact name, folder name, or slug
        $targetLower = $UninstallName.ToLower().Trim()
        $targetSlug = Get-Slug -InputText $targetLower

        $selectedApp = $apps | Where-Object {
            $_.Name.ToLower() -eq $targetLower -or 
            ([System.IO.Path]::GetFileName($_.Directory).ToLower() -eq $targetLower) -or
            ((Get-Slug -InputText $_.Name) -eq $targetSlug)
        } | Select-Object -First 1

        # Fallback substring match
        if (-not $selectedApp) {
            $selectedApp = $apps | Where-Object {
                $_.Name.ToLower() -like "*$targetLower*" -or 
                ([System.IO.Path]::GetFileName($_.Directory).ToLower() -like "*$targetLower*")
            } | Select-Object -First 1
        }

        if (-not $selectedApp) {
            Write-Error "Application matching '$UninstallName' not found in installed portable applications."
            Write-Host "Run 'pinstall -List' to see installed applications." -ForegroundColor Cyan
            return
        }
    } else {
        # Interactive selection menu
        Write-Host "`n📦 Select an application to uninstall:" -ForegroundColor Cyan
        Write-Host ("-" * 72) -ForegroundColor DarkGray
        for ($i = 0; $i -lt $apps.Count; $i++) {
            $a = $apps[$i]
            Write-Host ("  [{0}] {1,-40} {2,10}" -f ($i + 1), $a.Name, $a.SizeDisplay) -ForegroundColor White
        }
        Write-Host ("-" * 72) -ForegroundColor DarkGray

        $choice = Read-Host "Enter selection (1-$($apps.Count)) or 'q' to cancel"
        if ($choice -match '^[Qq]' -or [string]::IsNullOrWhiteSpace($choice)) {
            Write-Host "Uninstallation cancelled." -ForegroundColor Yellow
            return
        }

        $idx = [int]$choice - 1
        if ($idx -lt 0 -or $idx -ge $apps.Count) {
            Write-Error "Invalid selection: '$choice'"
            return
        }
        $selectedApp = $apps[$idx]
    }

    Write-Host "`n===================================================================" -ForegroundColor Yellow
    Write-Host "               UNINSTALL CONFIRMATION                              " -ForegroundColor Yellow
    Write-Host "===================================================================" -ForegroundColor Yellow
    Write-Host ("  {0,-20} : {1}" -f "App Name", $selectedApp.Name)
    Write-Host ("  {0,-20} : {1}" -f "Directory to remove", $selectedApp.Directory)

    if ($selectedApp.Shortcut) {
        Write-Host ("  {0,-20} : {1}" -f "Start Menu Shortcut", $selectedApp.Shortcut)
    }
    if ($selectedApp.Shim) {
        Write-Host ("  {0,-20} : {1}" -f "PATH Shim/Link", $selectedApp.Shim)
    }
    Write-Host "===================================================================" -ForegroundColor Yellow

    if (-not $Yes) {
        $confirm = Read-Host "Are you sure you want to completely remove '$($selectedApp.Name)'? [y/N]"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "Uninstallation cancelled by user." -ForegroundColor Yellow
            return
        }
    }

    Write-Host "`nRemoving application '$($selectedApp.Name)'..." -ForegroundColor Cyan

    # 1. Remove PATH shim/symlink
    if ($selectedApp.Shim -and (Test-Path -LiteralPath $selectedApp.Shim)) {
        Remove-Item -LiteralPath $selectedApp.Shim -Force -ErrorAction SilentlyContinue
        Write-Host "✓ Removed PATH shim/link: $($selectedApp.Shim)" -ForegroundColor Green
    }

    # 2. Remove Start Menu shortcut
    if ($selectedApp.Shortcut -and (Test-Path -LiteralPath $selectedApp.Shortcut)) {
        Remove-Item -LiteralPath $selectedApp.Shortcut -Force -ErrorAction SilentlyContinue
        Write-Host "✓ Removed Start Menu shortcut: $($selectedApp.Shortcut)" -ForegroundColor Green
    }

    # 3. Remove application folder
    if (Test-Path -LiteralPath $selectedApp.Directory) {
        Remove-Item -LiteralPath $selectedApp.Directory -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "✓ Removed directory: $($selectedApp.Directory)" -ForegroundColor Green
    }

    Write-Host "`n✓ Successfully uninstalled '$($selectedApp.Name)'.`n" -ForegroundColor Green
    return
}

# =============================================================================
# ACTION: Install Application
# =============================================================================

# Temporary directory tracker
$tempDownloadDir = $null
$originalSourceUrl = ""
$originalGitHubRepo = ""

function Cleanup-TempDownload {
    if ($tempDownloadDir -and (Test-Path -LiteralPath $tempDownloadDir)) {
        Remove-Item -LiteralPath $tempDownloadDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- GitHub & URL Resolution Functions ---

function Test-IsHttpUrl {
    param([string]$UriString)
    return ($UriString -match '^https?://')
}

function Get-GitHubRepoFromInput {
    param([string]$InputText)
    if ($InputText -match '^https?://github\.com/([^/]+)/([^/#?]+)') {
        $owner = $Matches[1]
        $repo = ($Matches[2] -replace '\.git$', '') -replace '/releases.*$', ''
        return "$owner/$repo"
    }
    if ($InputText -match '^gh:([^/]+)/([^/@#]+)') {
        return "$($Matches[1])/$($Matches[2])"
    }
    # owner/repo or owner/repo@tag (must not be an existing local file/dir)
    if (-not (Test-Path -LiteralPath $InputText) -and ($InputText -match '^([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)(@[^/]+)?$')) {
        return "$($Matches[1])/$($Matches[2])"
    }
    return $null
}

function Get-GitHubTagFromInput {
    param([string]$InputText)
    if ($InputText -match '@([^/]+)$') {
        return $Matches[1]
    }
    if ($InputText -match '/releases/tag/([^/#?]+)') {
        return $Matches[1]
    }
    return $null
}

function Resolve-GitHubReleaseAsset {
    param(
        [string]$Repo,
        [string]$Tag
    )

    $apiUrl = if ($Tag) {
        "https://api.github.com/repos/$Repo/releases/tags/$Tag"
    } else {
        "https://api.github.com/repos/$Repo/releases/latest"
    }

    Write-Host ">>> Querying GitHub API for '$Repo'..." -ForegroundColor Cyan

    $headers = @{
        "User-Agent" = "pinstall-windows"
        "Accept"     = "application/vnd.github.v3+json"
    }

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -ErrorAction Stop
    }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        Write-Error "GitHub API query failed for '$Repo' (Status: $status). $($_.Exception.Message)"
        return $null
    }

    $releaseTag = $response.tag_name
    Write-Host "Found release: $releaseTag" -ForegroundColor Green

    $rawAssets = @($response.assets)
    if ($rawAssets.Count -eq 0) {
        Write-Error "No release assets found in GitHub release for '$Repo'."
        return $null
    }

    # Filter Windows assets
    # Exclude Linux/Mac/Android/iOS and non-archive/installer types
    $excludeRegex = '(?i)(\.deb|\.rpm|\.appimage|\.dmg|\.pkg|\.apk|\.ipa|linux|darwin|macos|osx|android|\.sha256|\.sig|\.asc|\.txt|\.md|\.json)$'
    $archiveOrExeRegex = '(?i)(\.zip|\.7z|\.rar|\.tar|\.tar\.gz|\.tgz|\.tar\.xz|\.exe)$'

    $candidates = @($rawAssets | Where-Object {
        $name = $_.name
        ($name -notmatch $excludeRegex) -and ($name -match $archiveOrExeRegex)
    })

    # Further prioritize Windows-specific builds if available
    $winCandidates = @($candidates | Where-Object { $_.name -match '(?i)(windows|win64|win32|win|\.exe$)' })
    if ($winCandidates.Count -gt 0) {
        $candidates = $winCandidates
    }

    # Architecture matching: prefer x64/amd64/x86_64
    $is64 = [Environment]::Is64BitOperatingSystem
    if ($is64) {
        $x64Candidates = @($candidates | Where-Object { 
            ($_.name -match '(?i)(x64|amd64|x86_64|64bit|win64)') -and ($_.name -notmatch '(?i)(arm64|aarch64|armv7|i386|x86\b)')
        })
        if ($x64Candidates.Count -gt 0) {
            $candidates = $x64Candidates
        }
    }

    if ($candidates.Count -eq 0) {
        # Fallback to any non-excluded assets
        $candidates = @($rawAssets | Where-Object { $_.name -notmatch $excludeRegex })
    }

    if ($candidates.Count -eq 0) {
        Write-Error "No compatible Windows assets found in release for '$Repo'."
        return $null
    }

    $chosenAsset = $null
    if ($candidates.Count -eq 1) {
        $chosenAsset = $candidates[0]
        Write-Host "✓ Auto-selected release asset: $($chosenAsset.name)" -ForegroundColor Green
    } else {
        Write-Host "`n📦 Multiple release assets found for '$Repo':" -ForegroundColor Cyan
        Write-Host ("-" * 72) -ForegroundColor DarkGray
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            $item = $candidates[$i]
            $sStr = Format-FileSize -Bytes $item.size
            Write-Host ("  [{0}] {1,-46} {2,10}" -f ($i + 1), $item.name, $sStr) -ForegroundColor White
        }
        Write-Host ("-" * 72) -ForegroundColor DarkGray

        $sel = Read-Host "Enter selection (1-$($candidates.Count)) [Default: 1]"
        if ([string]::IsNullOrWhiteSpace($sel)) { $sel = "1" }
        $idx = [int]$sel - 1
        if ($idx -lt 0 -or $idx -ge $candidates.Count) {
            Write-Error "Invalid selection '$sel'."
            return $null
        }
        $chosenAsset = $candidates[$idx]
    }

    return [PSCustomObject]@{
        Name    = $chosenAsset.name
        Url     = $chosenAsset.browser_download_url
        Size    = $chosenAsset.size
        AppName = ($Repo -split '/')[1]
    }
}

function Download-AssetFile {
    param(
        [string]$Url,
        [string]$FileName
    )

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pinstall-" + [System.IO.Path]::GetRandomFileName())
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    $destPath = Join-Path $tempDir $FileName

    Write-Host ">>> Downloading '$FileName'..." -ForegroundColor Cyan
    Write-Host ">>> From: $Url" -ForegroundColor Gray

    try {
        # Use curl.exe if present for nice progress display, else Invoke-WebRequest
        $curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curlCmd) {
            & curl.exe -fL --progress-bar -H "User-Agent: pinstall-windows" -o $destPath $Url
            if ($LASTEXITCODE -ne 0 -or (-not (Test-Path -LiteralPath $destPath))) {
                throw "curl returned exit code $LASTEXITCODE"
            }
        } else {
            Invoke-WebRequest -Uri $Url -OutFile $destPath -UserAgent "pinstall-windows" -ErrorAction Stop
        }

        $size = (Get-Item -LiteralPath $destPath).Length
        Write-Host "✓ Download completed: $(Format-FileSize -Bytes $size)" -ForegroundColor Green
        return @{ Path = $destPath; TempDir = $tempDir }
    }
    catch {
        Write-Error "Download failed: $_"
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        return $null
    }
}

try {
    # --- Check if Source is GitHub or URL ---
    if ($Source) {
        $parsedRepo = Get-GitHubRepoFromInput -InputText $Source
        if ($parsedRepo) {
            $originalGitHubRepo = $parsedRepo
            $tag = Get-GitHubTagFromInput -InputText $Source
            $assetInfo = Resolve-GitHubReleaseAsset -Repo $parsedRepo -Tag $tag
            if (-not $assetInfo) { return }

            $originalSourceUrl = $assetInfo.Url
            if (-not $Name) { $Name = $assetInfo.AppName }

            $dl = Download-AssetFile -Url $assetInfo.Url -FileName $assetInfo.Name
            if (-not $dl) { return }
            $Source = $dl.Path
            $tempDownloadDir = $dl.TempDir
        }
        elseif (Test-IsHttpUrl -UriString $Source) {
            $originalSourceUrl = $Source
            $uri = [System.Uri]$Source
            $urlFile = [System.IO.Path]::GetFileName($uri.AbsolutePath)
            if ([string]::IsNullOrWhiteSpace($urlFile)) { $urlFile = "downloaded-app.bin" }

            $dl = Download-AssetFile -Url $Source -FileName $urlFile
            if (-not $dl) { return }
            $Source = $dl.Path
            $tempDownloadDir = $dl.TempDir
        }
    }

    # --- Archive Extensions Definition ---
    $supportedArchiveExts = @('.zip', '.7z', '.rar', '.tar', '.gz', '.bz2', '.xz', '.tgz', '.txz', '.tbz2', '.iso', '.cab', '.wim', '.zst')
    $allSupportedExts = $supportedArchiveExts + @('.exe')

    # Resolve relative path if -Source was provided
    if ($Source -and -not (Test-IsHttpUrl -UriString $Source)) {
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
            Write-Host "Usage: pinstall [source_file|github_repo|url] [-AddToPath] [-Name <name>]" -ForegroundColor Cyan
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
        $suggestedName = Clean-AppName -RawName $sourceItem.Name
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
    $createdShortcut = $null
    if (-not $NoShortcut -and $targetExePath) {
        $createdShortcut = Create-StartMenuShortcut -DisplayName $Name -TargetExePath $targetExePath -SubGroup $Group
    }

    # --- Add to User PATH if requested ---
    $createdShim = $null
    if ($AddToPath -and $targetExePath) {
        $binDir = Ensure-UserBinInPath
        $createdShim = Create-AppShimOrSymlink -BinDir $binDir -TargetExePath $targetExePath -AliasName ($Name -replace '\s+', '')
    }

    # --- Write Metadata Receipt (.pinstall.json) ---
    $receiptData = @{
        name          = $Name
        slug          = Get-Slug -InputText $Name
        source_file   = $sourceItem.Name
        source_url    = $originalSourceUrl
        github_repo   = $originalGitHubRepo
        install_dir   = $appDestDir
        exec_path     = $targetExePath
        shortcut_path = $createdShortcut
        bin_link      = $createdShim
        installed_at  = (Get-Date).ToString("o")
    }
    Write-Receipt -AppDir $appDestDir -Data $receiptData | Out-Null

    Write-Host "`n===================================================================" -ForegroundColor Green
    Write-Host " Installation of '$Name' completed successfully!" -ForegroundColor Green
    Write-Host " Installed at: $appDestDir" -ForegroundColor Gray
    if ($targetExePath) {
        Write-Host " Target Executable: $targetExePath" -ForegroundColor Gray
    }
    if ($AddToPath -and $createdShim) {
        Write-Host " Available in PATH as: $([System.IO.Path]::GetFileNameWithoutExtension($createdShim))" -ForegroundColor Cyan
    }
    Write-Host "===================================================================`n" -ForegroundColor Green
}
finally {
    Cleanup-TempDownload
}
