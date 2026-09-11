<#
.SYNOPSIS
    Create a new directory and immediately change into it.
.PARAMETER Path
    The target directory path to create and enter.
.EXAMPLE
    mkcd NewProject
#>
function mkcd {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    Set-Location -Path $Path
}
