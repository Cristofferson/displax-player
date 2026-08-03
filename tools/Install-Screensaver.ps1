<#
.SYNOPSIS
    Registers DISPLAX Player as the Windows screen saver.

.DESCRIPTION
    The build ships DISPLAX.scr next to the player: it is the same binary with
    the screen saver bit set in its PE header, so it needs the ~310 files that
    sit beside it — CefSharp's Chromium, the XML serializers, the config. That
    is why it must NOT be copied into System32 the way a self-contained .scr
    would be: away from its folder it cannot start. Windows accepts a full path
    in SCRNSAVE.EXE, and that is what this script writes.

    Screen saver settings are per-user (HKCU\Control Panel\Desktop), so an
    installer running as an administrator would configure the ADMINISTRATOR's
    desktop rather than the account the screen actually runs under — the same
    trap as the player's own settings. -AllUsers walks every real profile,
    loading each NTUSER.DAT that is not already mounted.

    Note that the Windows screen saver dialog may show "(None)" selected even
    when this worked: it lists the .scr files it finds in the system folders,
    and ours is deliberately not one of them. The registry value is what
    Windows actually acts on.

.PARAMETER ScreenSaverPath
    Full path to DISPLAX.scr. Defaults to the copy one level above this script,
    which is where the installer puts both.

.PARAMETER TimeoutSeconds
    Idle time before the screen saver starts. Default 600 (ten minutes).

.PARAMETER AllUsers
    Configure every profile on the machine instead of only the current user.

.PARAMETER Remove
    Undo it: switch the screen saver off and drop the SCRNSAVE.EXE value.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Install-Screensaver.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Install-Screensaver.ps1 -AllUsers -TimeoutSeconds 300

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Install-Screensaver.ps1 -Remove -AllUsers
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ScreenSaverPath,
    [int]$TimeoutSeconds = 600,
    [switch]$AllUsers,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

# Keep in step with the post-build event in XiboClient.csproj, which is what
# produces this file from the player executable.
$ScreenSaverFileName = 'DISPLAX.scr'

if (-not $ScreenSaverPath) {
    $ScreenSaverPath = Join-Path (Split-Path -Parent $PSScriptRoot) $ScreenSaverFileName
}

if (-not $Remove) {
    if (-not (Test-Path -LiteralPath $ScreenSaverPath -PathType Leaf)) {
        throw "Screen saver not found at $ScreenSaverPath. Point -ScreenSaverPath at $ScreenSaverFileName inside the DISPLAX Player folder."
    }
    $ScreenSaverPath = (Resolve-Path -LiteralPath $ScreenSaverPath).Path
}

function Set-ScreenSaverForKey {
    <#
        Writes the three values Windows reads, under an already-open desktop key
        path. Everything here is REG_SZ, including the timeout — Windows stores
        that as a string and ignores a DWORD.
    #>
    param(
        [Parameter(Mandatory)][string]$DesktopKey,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $DesktopKey)) {
        Write-Warning "$Label : no Control Panel\Desktop key, skipped."
        return
    }

    if ($Remove) {
        if (-not $PSCmdlet.ShouldProcess($Label, 'Remove DISPLAX screen saver')) { return }
        Set-ItemProperty -LiteralPath $DesktopKey -Name 'ScreenSaveActive' -Value '0' -Type String
        Remove-ItemProperty -LiteralPath $DesktopKey -Name 'SCRNSAVE.EXE' -ErrorAction SilentlyContinue
        Write-Output "$Label : screen saver switched off."
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Label, "Set screen saver to $ScreenSaverFileName")) { return }
    Set-ItemProperty -LiteralPath $DesktopKey -Name 'SCRNSAVE.EXE'      -Value $ScreenSaverPath        -Type String
    Set-ItemProperty -LiteralPath $DesktopKey -Name 'ScreenSaveActive'  -Value '1'                     -Type String
    Set-ItemProperty -LiteralPath $DesktopKey -Name 'ScreenSaveTimeOut' -Value "$TimeoutSeconds"       -Type String
    Write-Output "$Label : screen saver set, starts after $TimeoutSeconds s idle."
}

function Get-RealUserProfiles {
    <#
        Reads the profile list rather than listing C:\Users, because the SID is
        what HKEY_USERS is keyed by and the folder name does not give it. Service
        accounts (LocalSystem, LocalService, NetworkService) have no desktop to
        configure, and their SIDs are short.
    #>
    $profileList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    Get-ChildItem -LiteralPath $profileList | ForEach-Object {
        $sid = Split-Path -Leaf $_.Name
        if ($sid -notmatch '^S-1-5-21-') { return }
        $path = (Get-ItemProperty -LiteralPath $_.PSPath -Name 'ProfileImagePath' -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $path) { return }
        [pscustomobject]@{ Sid = $sid; Path = $path }
    }
}

if (-not $AllUsers) {
    Set-ScreenSaverForKey -DesktopKey 'HKCU:\Control Panel\Desktop' -Label "$env:USERNAME (current user)"
}
else {
    $profiles = @(Get-RealUserProfiles)
    if (-not $profiles) {
        Write-Warning 'No user profiles found; falling back to the current user.'
        Set-ScreenSaverForKey -DesktopKey 'HKCU:\Control Panel\Desktop' -Label "$env:USERNAME (current user)"
    }

    $hiveIndex = 0
    # Not $profile: that is an automatic PowerShell variable (the shell's own
    # profile script) and shadowing it here would be asking for trouble.
    foreach ($userProfile in $profiles) {
        $label = Split-Path -Leaf $userProfile.Path
        $mounted = "Registry::HKEY_USERS\$($userProfile.Sid)"

        if (Test-Path -LiteralPath $mounted) {
            # The user has a session open, so their hive is already loaded and
            # loading it again would fail.
            Set-ScreenSaverForKey -DesktopKey "$mounted\Control Panel\Desktop" -Label $label
            continue
        }

        $hive = Join-Path $userProfile.Path 'NTUSER.DAT'
        if (-not (Test-Path -LiteralPath $hive -PathType Leaf)) {
            Write-Warning "$label : no NTUSER.DAT, skipped."
            continue
        }

        $hiveIndex++
        $mountPoint = "DISPLAX_$hiveIndex"
        $loaded = $false
        try {
            # reg.exe rather than a .NET call: loading a hive needs the backup
            # privilege, which reg.exe already asks for.
            $output = & reg.exe load "HKU\$mountPoint" "$hive" 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($output | Out-String).Trim() }
            $loaded = $true
            Set-ScreenSaverForKey -DesktopKey "Registry::HKEY_USERS\$mountPoint\Control Panel\Desktop" -Label $label
        }
        catch {
            Write-Warning "$label : could not load the profile hive ($_). Skipped."
        }
        finally {
            if ($loaded) {
                # Without this the profile stays mounted and the user cannot log
                # in cleanly, so it runs even when the write above failed.
                [gc]::Collect()
                & reg.exe unload "HKU\$mountPoint" | Out-Null
            }
        }
    }
}

# Windows caches these per session: without this the change only shows up after
# the next sign-in. It only affects the account running the script, which is why
# it is not inside the loop.
try {
    # The argument has to be one quoted string: an unquoted comma would make
    # PowerShell build an array and rundll32 would get the wrong arguments.
    & rundll32.exe 'user32.dll,UpdatePerUserSystemParameters' '1' 'True'
}
catch {
    Write-Warning 'Settings written, but the running session did not pick them up. They apply after the next sign-in.'
}
