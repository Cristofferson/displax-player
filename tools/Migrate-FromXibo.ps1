<#
.SYNOPSIS
    Carries an existing Xibo for Windows install over to DISPLAX Player.

.DESCRIPTION
    Two things in the player are named after the branding, and both move when
    the brand changes. Neither is cosmetic:

    1. Settings live in %APPDATA%\<executable name>.xml — the file is named
       after the running .exe (ApplicationSettings.cs uses
       Path.GetFileNameWithoutExtension of the executable path). Renaming
       XiboClient.exe to DisplaxPlayer.exe therefore ORPHANS the settings: the
       CMS address, the CMS key and the display identity all go with them, and
       the player comes up unregistered and has to be authorised again in the
       CMS.

    2. The media library defaults to My Documents\<Product> Library, and the
       shipped LibraryPath is the literal "DEFAULT", so it is recomputed rather
       than stored. Without this migration every screen re-downloads its whole
       library and shows nothing until it finishes — with a fifteen-video
       layout that is a long blank wall.

    Run this BEFORE the first launch of the rebranded player. It is safe to run
    twice: anything already migrated is reported and left alone.

.PARAMETER AllUsers
    Migrate every profile under C:\Users instead of only the current user.
    Useful when the installer runs as an administrator that is not the account
    the player runs under.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Migrate-FromXibo.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Migrate-FromXibo.ps1 -AllUsers -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

# Old name -> new name. Keep these in step with AssemblyName in
# XiboClient.csproj and AssemblyProduct in Properties/AssemblyInfo.cs.
$OldExecutableName = 'XiboClient'
$NewExecutableName = 'DisplaxPlayer'
$OldProductName    = 'Xibo'
$NewProductName    = 'DISPLAX'

function Move-IfSafe {
    <#
        Moves Source to Destination only when that cannot lose data: the source
        must exist and the destination must not. If both exist we stop and say
        so rather than merging or overwriting — a half-merged library is worse
        than an un-migrated one, because it looks fine until a file is missing.
    #>
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$What
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Host "  - $What : nothing to migrate ($Source not found)"
        return
    }

    if (Test-Path -LiteralPath $Destination) {
        Write-Warning "  ! $What : BOTH exist. Left untouched so nothing is lost."
        Write-Warning "      old: $Source"
        Write-Warning "      new: $Destination"
        Write-Warning "      Decide which one is current, remove the other, and re-run."
        return
    }

    if ($PSCmdlet.ShouldProcess($Source, "Move to $Destination")) {
        Move-Item -LiteralPath $Source -Destination $Destination
        Write-Host "  + $What : migrated"
        Write-Host "      $Source"
        Write-Host "   -> $Destination"
    }
}

function Migrate-Profile {
    param(
        [Parameter(Mandatory)][string]$AppData,   # ...\AppData\Roaming
        [Parameter(Mandatory)][string]$Documents,
        [Parameter(Mandatory)][string]$Label
    )

    Write-Host ""
    Write-Host "Profile: $Label"

    # 1. Settings — CMS address, CMS key, display identity.
    Move-IfSafe -What 'Settings' `
        -Source      (Join-Path $AppData "$OldExecutableName.xml") `
        -Destination (Join-Path $AppData "$NewExecutableName.xml")

    # The legacy .config.xml is read once and converted on first run. Carry it
    # across too, otherwise that one-time conversion silently never happens.
    Move-IfSafe -What 'Legacy settings' `
        -Source      (Join-Path $AppData "$OldExecutableName.config.xml") `
        -Destination (Join-Path $AppData "$NewExecutableName.config.xml")

    # 2. Media library — also holds config.xml with the hardware key, so moving
    #    it keeps the display registered as the SAME display in the CMS.
    Move-IfSafe -What 'Media library' `
        -Source      (Join-Path $Documents "$OldProductName Library") `
        -Destination (Join-Path $Documents "$NewProductName Library")
}

Write-Host "DISPLAX Player — migration from Xibo for Windows"
Write-Host "================================================"

if ($AllUsers) {
    $profiles = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }

    if (-not $profiles) {
        Write-Warning 'No user profiles found under C:\Users.'
        return
    }

    foreach ($p in $profiles) {
        $appData   = Join-Path $p.FullName 'AppData\Roaming'
        $documents = Join-Path $p.FullName 'Documents'
        if (-not (Test-Path -LiteralPath $appData)) { continue }
        Migrate-Profile -AppData $appData -Documents $documents -Label $p.Name
    }
} else {
    Migrate-Profile `
        -AppData   ([Environment]::GetFolderPath('ApplicationData')) `
        -Documents ([Environment]::GetFolderPath('MyDocuments')) `
        -Label     $env:USERNAME
}

Write-Host ""
Write-Host "Done. Launch DISPLAX Player and confirm in the CMS that the display"
Write-Host "reports in as the same display it was before, with its library intact."
