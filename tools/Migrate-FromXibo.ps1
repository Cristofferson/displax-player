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

    3. The XMR key pair lives INSIDE the library, as id_rsa / id_rsa.pub
       (HardwareKey.getXmrKey). A library the player finds without one is not an
       error it reports: it quietly generates a fresh pair and registers the new
       public key. Everything keeps looking healthy — the display reports in, its
       files download, scheduled content plays — but every real-time command the
       CMS pushes (change layout, collect now, screenshot, SoftRestart) arrives
       encrypted for a key the player no longer holds and is dropped. The only
       trace is in the CMS log, filed under the display itself:

           [XmrSubscriber] XmrSubscriber - processMessage
           Unopenable Message: block incorrect

       Carrying the library across covers this on its own, but the library move
       is refused whenever the destination already exists (see Move-IfSafe), and
       that is the common case on a machine where the player has been installed
       or launched before. So the key is carried separately as well: it is small,
       it is the one file whose absence fails silently, and it is the difference
       between a screen that obeys the CMS and one that only ever catches up on
       its next poll.

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

function Copy-XmrKey {
    <#
        Ensures the new library carries the XMR key pair from the old one.

        This runs after the library move, not instead of it: when the move
        succeeded the key travelled with it and there is nothing left to do. It
        earns its place in the case the move refuses — destination already
        present — because that leaves a library with no id_rsa, and the player
        answers that by generating a new pair and silently losing every push
        command from the CMS.

        Copies rather than moves, and never overwrites. A key already in the new
        library is the one the CMS most likely knows: replacing it would break
        exactly what this is meant to repair. Two installs sharing one key pair
        is harmless — both can open the same message — whereas two keys where the
        CMS stores only one means the loser goes deaf.

        Only id_rsa matters. It is a private-key PEM, so PemReader hands back the
        whole pair and getXmrPublicKey derives the public half in memory; the
        player writes id_rsa.pub once at generation and never reads it again.
        LibraryAgent's _persistentFiles protects id_rsa from the two-minute
        library sweep but NOT id_rsa.pub, so on any library with some age the
        .pub is already gone. That is normal, and saying "not found" about it
        would send whoever runs this looking for a problem that isn't there.
    #>
    param(
        [Parameter(Mandatory)][string]$OldLibrary,
        [Parameter(Mandatory)][string]$NewLibrary
    )

    if (-not (Test-Path -LiteralPath $NewLibrary)) {
        # No new library yet: either the move carried everything across, or
        # there was nothing to migrate. Either way there is nowhere to copy to.
        return
    }

    $source      = Join-Path $OldLibrary 'id_rsa'
    $destination = Join-Path $NewLibrary 'id_rsa'

    if (Test-Path -LiteralPath $destination) {
        Write-Host "  = XMR key : already present, left alone"
    }
    elseif (-not (Test-Path -LiteralPath $source)) {
        # An old library with no key is normal on a player that never had XMR
        # reach it. The new one will generate a pair on first run.
        Write-Host "  - XMR key : nothing to migrate ($source not found)"
    }
    elseif ($PSCmdlet.ShouldProcess($source, "Copy to $destination")) {
        Copy-Item -LiteralPath $source -Destination $destination
        Write-Host "  + XMR key : carried over"
        Write-Host "      $source"
        Write-Host "   -> $destination"
    }

    # Cosmetic only, and quietly: if the .pub happens to have survived the sweep
    # it is nice to keep the pair together for anyone inspecting the folder.
    $sourcePub      = Join-Path $OldLibrary 'id_rsa.pub'
    $destinationPub = Join-Path $NewLibrary 'id_rsa.pub'

    if ((Test-Path -LiteralPath $sourcePub) -and
        -not (Test-Path -LiteralPath $destinationPub) -and
        $PSCmdlet.ShouldProcess($sourcePub, "Copy to $destinationPub")) {
        Copy-Item -LiteralPath $sourcePub -Destination $destinationPub
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
    $oldLibrary = Join-Path $Documents "$OldProductName Library"
    $newLibrary = Join-Path $Documents "$NewProductName Library"

    Move-IfSafe -What 'Media library' -Source $oldLibrary -Destination $newLibrary

    # 3. XMR key pair — normally rides along inside the library above. Checked
    #    separately because when the move is refused its absence is the one
    #    failure the player never reports: it just stops obeying the CMS.
    Copy-XmrKey -OldLibrary $oldLibrary -NewLibrary $newLibrary
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
