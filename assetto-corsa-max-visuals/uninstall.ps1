<#
.SYNOPSIS
    Removes the Max Visuals graphics pack and restores your previous settings.

.DESCRIPTION
    install.ps1 backs up every file before changing it, to
    Documents\Assetto Corsa\MaxVisuals-Backups\<date-time>\
    This script restores those backups, newest first, so even after several
    installs you end up with the settings you had before the first one.
    Files that did not exist before are deleted. Restored backups are
    renamed to <date-time>.restored and kept.

    Note: CSP/video settings you changed AFTER installing are reverted too
    (for the files the pack touched).

.PARAMETER LatestOnly
    Undo only the most recent install.

.PARAMETER Force
    Don't stop when Assetto Corsa / Content Manager are running.
#>
[CmdletBinding()]
param(
    [switch]$LatestOnly,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$docs = [Environment]::GetFolderPath('MyDocuments')
$backupRoot = Join-Path $docs 'Assetto Corsa\MaxVisuals-Backups'

Write-Host ''
Write-Host 'Max Visuals for Assetto Corsa - uninstall' -ForegroundColor White

if (-not (Test-Path -LiteralPath $backupRoot)) {
    Write-Host "Nothing to restore: '$backupRoot' does not exist." -ForegroundColor Yellow
    exit 0
}

$backups = @(Get-ChildItem -LiteralPath $backupRoot -Directory |
    Where-Object { $_.Name -match '^\d{8}-\d{6}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.tsv')) } |
    Sort-Object Name -Descending)

if ($backups.Count -eq 0) {
    Write-Host 'Nothing to restore: no unrestored backups found.' -ForegroundColor Yellow
    exit 0
}
if ($LatestOnly) { $backups = @($backups[0]) }

$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    @('acs', 'acs_x86', 'Content Manager', 'AssettoCorsa') -contains $_.ProcessName
})
if ($running.Count -gt 0 -and -not $Force) {
    $names = ($running | ForEach-Object { $_.ProcessName + '.exe' } | Select-Object -Unique) -join ', '
    Write-Host "  ! Please close: $names (otherwise they may overwrite the restored settings)." -ForegroundColor Yellow
    $answer = Read-Host '    Press Enter once they are closed, or type Q to quit'
    if ($answer -match '^\s*[qQ]') { exit 1 }
}

$failed = 0
foreach ($backup in $backups) {
    $failedHere = 0
    Write-Host ''
    Write-Host "==> Restoring backup $($backup.Name)" -ForegroundColor Cyan
    $entries = [System.IO.File]::ReadAllLines((Join-Path $backup.FullName 'manifest.tsv'))
    # Undo in reverse order of how the files were changed
    [array]::Reverse($entries)
    foreach ($line in $entries) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t"
        if ($parts.Count -lt 2) { continue }
        $existed = $parts[0] -eq '1'
        $target = $parts[1]
        try {
            if ($existed) {
                $source = Join-Path $backup.FullName $parts[2]
                if (-not (Test-Path -LiteralPath $source)) {
                    Write-Host "    ! backup copy missing for $target" -ForegroundColor Yellow
                    $failedHere++
                    continue
                }
                $dir = Split-Path -Parent $target
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                Copy-Item -LiteralPath $source -Destination $target -Force
                Write-Host "    restored $target" -ForegroundColor Green
            } elseif (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Force
                Write-Host "    removed  $target" -ForegroundColor Green
            }
        } catch {
            Write-Host "    ! $target : $($_.Exception.Message)" -ForegroundColor Red
            $failedHere++
        }
    }
    if ($failedHere -eq 0) {
        try {
            Rename-Item -LiteralPath $backup.FullName -NewName ($backup.Name + '.restored')
        } catch {
            Write-Host "    ! restored, but could not mark the backup as done: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    $failed += $failedHere
}

Write-Host ''
if ($failed -gt 0) {
    Write-Host "Finished with $failed problem(s). Backups with problems were kept (not marked restored): $backupRoot" -ForegroundColor Yellow
    exit 1
}
Write-Host 'Done - your previous settings are back.' -ForegroundColor Green
Write-Host 'If you picked a different PP filter or CSP preset in Content Manager since, re-select it there.'
exit 0
