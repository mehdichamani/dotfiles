<#
.SYNOPSIS
    Windows Portable Application Installer script runner.
.DESCRIPTION
    Launches PortableInstaller.ps1 with forwarded arguments to download,
    extract, and create shortcuts for portable tools.
.EXAMPLE
    pinstall
#>
function pinstall {
    $script = "$HOME\.config\scripts\PortableInstaller.ps1"
    if (-not (Test-Path -LiteralPath $script)) {
        $script = "$HOME\.local\share\chezmoi\dot_config\scripts\PortableInstaller.ps1"
    }
    & $script @args
}
