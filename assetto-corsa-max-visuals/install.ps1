<#
.SYNOPSIS
    Installs the Max Visuals graphics pack for Assetto Corsa.

.DESCRIPTION
    1. Copies the MaxVisuals post-processing filters into
       <assettocorsa>\system\cfg\ppfilters
    2. Merges the quality settings into Documents\Assetto Corsa\cfg\video.ini
       (resolution, window mode, refresh rate, V-sync and FPS limit are kept)
    3. Merges the Custom Shaders Patch preset into
       Documents\Assetto Corsa\cfg\extension\*.ini (only the listed keys;
       your weather style, controls, UI, audio and VR settings are untouched)
    4. Copies both CSP presets into Content Manager's preset folder

    Every file is backed up before it is changed, to
    Documents\Assetto Corsa\MaxVisuals-Backups\<date-time>\
    Run uninstall.ps1 (or Uninstall.bat) to restore.

.PARAMETER Preset
    Ultra (default) or High.

.PARAMETER Filter
    Post-processing filter to activate: MaxVisuals (default) or MaxVisuals_AgX
    (AgX tonemapping, needs CSP 0.2.1+). Both are installed either way.

.PARAMETER AcRoot
    Assetto Corsa folder (the one containing acs.exe). Found through Steam
    when omitted.

.PARAMETER SkipVideo
    Don't change video.ini.

.PARAMETER SkipCsp
    Don't change Custom Shaders Patch settings.

.PARAMETER DryRun
    Show what would change without writing anything.

.PARAMETER Force
    Don't stop when Assetto Corsa / Content Manager are running or CSP is
    missing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1 -Preset High -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('Ultra', 'High')]
    [string]$Preset = 'Ultra',

    [ValidateSet('MaxVisuals', 'MaxVisuals_AgX')]
    [string]$Filter = 'MaxVisuals',

    [string]$AcRoot,

    [switch]$SkipVideo,
    [switch]$SkipCsp,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# CSP build numbers (from the official changelogs)
$CspBuildAgX = 2654   # 0.2.1-preview2: AgX tonemapping
$CspBuild030 = 4293   # 0.3.0

$PackDir   = $PSScriptRoot
$FilesDir  = Join-Path $PackDir 'files'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------
#  Output helpers
# ---------------------------------------------------------------------------
function Write-Step([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "    $Text" -ForegroundColor Green }
function Write-Info([string]$Text) { Write-Host "    $Text" }
function Write-Warn([string]$Text) { Write-Host "    ! $Text" -ForegroundColor Yellow }
function Stop-WithError([string]$Text) {
    Write-Host ''
    Write-Host "ERROR: $Text" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
#  INI helpers (operate in place on a List[string] of lines, keep comments
#  and everything that is not being changed)
# ---------------------------------------------------------------------------
function Find-IniSection($Lines, [string]$Section) {
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*\[\s*([^\]]+?)\s*\]') {
            if ($Matches[1] -ieq $Section) { return $i }
        }
    }
    return -1
}

function Get-IniSectionEnd($Lines, [int]$Start) {
    for ($i = $Start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*\[') { return $i }
    }
    return $Lines.Count
}

function Get-IniValue($Lines, [string]$Section, [string]$Key) {
    $start = Find-IniSection $Lines $Section
    if ($start -lt 0) { return $null }
    $end = Get-IniSectionEnd $Lines $start
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*=\s*(.*?)\s*$'
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($Lines[$i] -match $pattern) { return $Matches[1] }
    }
    return $null
}

function Set-IniValue($Lines, [string]$Section, [string]$Key, [string]$Value) {
    $newLine = "$Key=$Value"
    $start = Find-IniSection $Lines $Section
    if ($start -lt 0) {
        if ($Lines.Count -gt 0 -and $Lines[$Lines.Count - 1].Trim() -ne '') { $Lines.Add('') }
        $Lines.Add("[$Section]")
        $Lines.Add($newLine)
        return
    }
    $end = Get-IniSectionEnd $Lines $start
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($Lines[$i] -match $pattern) { $Lines[$i] = $newLine; return }
    }
    $insertAt = $end
    while ($insertAt -gt ($start + 1) -and $Lines[$insertAt - 1].Trim() -eq '') { $insertAt-- }
    $Lines.Insert($insertAt, $newLine)
}

function Remove-IniKey($Lines, [string]$Section, [string]$Key) {
    $start = Find-IniSection $Lines $Section
    if ($start -lt 0) { return }
    $end = Get-IniSectionEnd $Lines $start
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    for ($i = $end - 1; $i -gt $start; $i--) {
        if ($Lines[$i] -match $pattern) { $Lines.RemoveAt($i) }
    }
}

# Reads one of the pack's own INI files into a list of Section/Key/Value
# entries. Full-line comments (; or #) and blank lines are ignored.
function Read-PackIni([string]$Path) {
    $result = New-Object 'System.Collections.Generic.List[object]'
    $section = ''
    foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[([^\]]+)\]$') { $section = $Matches[1].Trim(); continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1 -or $section -eq '') { continue }
        $result.Add([pscustomobject]@{
            Section = $section
            Key     = $line.Substring(0, $eq).Trim()
            Value   = $line.Substring($eq + 1).Trim()
        })
    }
    return $result
}

# Merges $Settings into the INI file at $Path (creating it if needed),
# removes $RemoveKeys ("SECTION/KEY"), and prints what changed.
function Update-IniFile([string]$Path, $Settings, [string[]]$RemoveKeys = @()) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $existed = Test-Path -LiteralPath $Path
    if ($existed) {
        foreach ($l in [System.IO.File]::ReadAllLines($Path)) { $lines.Add($l) }
    }
    $before = ($lines.ToArray()) -join "`n"
    $changes = New-Object 'System.Collections.Generic.List[string]'

    foreach ($s in $Settings) {
        $old = Get-IniValue $lines $s.Section $s.Key
        if ($null -eq $old -or $old -ne $s.Value) {
            $shownOld = $old
            if ($null -eq $old) { $shownOld = '(unset)' }
            $changes.Add(('[{0}] {1}: {2} -> {3}' -f $s.Section, $s.Key, $shownOld, $s.Value))
        }
        Set-IniValue $lines $s.Section $s.Key $s.Value
    }
    foreach ($r in $RemoveKeys) {
        $parts = $r -split '/', 2
        if ($null -ne (Get-IniValue $lines $parts[0] $parts[1])) {
            $changes.Add(('[{0}] {1}: removed' -f $parts[0], $parts[1]))
            Remove-IniKey $lines $parts[0] $parts[1]
        }
    }

    $after = ($lines.ToArray()) -join "`n"
    $name = Split-Path -Leaf $Path
    if ($existed -and $before -eq $after) {
        Write-Info "$name - already up to date"
        return
    }
    if ($changes.Count -eq 0) { $changes.Add('(formatting only)') }

    if ($DryRun) {
        Write-Info ("{0} - would change {1} value(s):" -f $name, $changes.Count)
        foreach ($c in $changes) { Write-Info "      $c" }
        return
    }

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllLines($Path, $lines.ToArray(), $Utf8NoBom)
    $verb = 'updated'
    if (-not $existed) { $verb = 'created' }
    Write-Ok ("{0} - {1} ({2} value(s))" -f $name, $verb, $changes.Count)
    if ($VerbosePreference -ne 'SilentlyContinue') {
        foreach ($c in $changes) { Write-Info "      $c" }
    }
}

# ---------------------------------------------------------------------------
#  Backups
# ---------------------------------------------------------------------------
$script:BackupDir   = $null
$script:BackupIndex = 0
$script:BackedUp    = @{}
$script:Manifest    = New-Object 'System.Collections.Generic.List[string]'

function Backup-File([string]$Path) {
    if ($DryRun) { return }
    $id = $Path.ToLowerInvariant()
    if ($script:BackedUp.ContainsKey($id)) { return }
    $script:BackedUp[$id] = $true
    if (-not (Test-Path -LiteralPath $script:BackupDir)) {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    }
    if (Test-Path -LiteralPath $Path) {
        $script:BackupIndex++
        $name = '{0:D3}_{1}' -f $script:BackupIndex, (Split-Path -Leaf $Path)
        Copy-Item -LiteralPath $Path -Destination (Join-Path $script:BackupDir $name) -Force
        $script:Manifest.Add("1`t$Path`t$name")
    } else {
        $script:Manifest.Add("0`t$Path`t")
    }
    [System.IO.File]::WriteAllLines((Join-Path $script:BackupDir 'manifest.tsv'), $script:Manifest.ToArray(), $Utf8NoBom)
}

# ---------------------------------------------------------------------------
#  Locating Assetto Corsa
# ---------------------------------------------------------------------------
function Test-AcRoot([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { return (Test-Path -LiteralPath (Join-Path $Path 'acs.exe')) } catch { return $false }
}

function Find-AcRoot {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $steamDirs  = New-Object 'System.Collections.Generic.List[string]'
    foreach ($reg in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $props = Get-ItemProperty -Path $reg -ErrorAction Stop
            foreach ($name in @('SteamPath', 'InstallPath')) {
                $p = $props.PSObject.Properties[$name]
                if ($p -and $p.Value) { $steamDirs.Add(($p.Value -replace '/', '\')) }
            }
        } catch { }
    }
    foreach ($steam in ($steamDirs | Select-Object -Unique)) {
        $candidates.Add((Join-Path $steam 'steamapps\common\assettocorsa'))
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $text = [System.IO.File]::ReadAllText($vdf)
            foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                $lib = $m.Groups[1].Value -replace '\\\\', '\'
                $candidates.Add((Join-Path $lib 'steamapps\common\assettocorsa'))
            }
        }
    }
    $candidates.Add('C:\Program Files (x86)\Steam\steamapps\common\assettocorsa')
    $candidates.Add('C:\Program Files\Steam\steamapps\common\assettocorsa')
    foreach ($c in $candidates) {
        if (Test-AcRoot $c) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "Max Visuals for Assetto Corsa - preset: $Preset, filter: $Filter" -ForegroundColor White
if ($DryRun) { Write-Host '(dry run: nothing will be written)' -ForegroundColor Yellow }

# Pack integrity
foreach ($rel in @('ppfilters\MaxVisuals.ini', 'ppfilters\MaxVisuals_AgX.ini',
                   "video\$($Preset.ToLowerInvariant()).ini", "csp-presets\Max Visuals - $Preset.ini")) {
    if (-not (Test-Path -LiteralPath (Join-Path $FilesDir $rel))) {
        Stop-WithError "Missing pack file 'files\$rel'. Extract the whole pack before running the installer."
    }
}

Write-Step 'Locating Assetto Corsa'
$docs   = [Environment]::GetFolderPath('MyDocuments')
$DocsAc = Join-Path $docs 'Assetto Corsa'
$DocsCfg = Join-Path $DocsAc 'cfg'
if (-not (Test-Path -LiteralPath $DocsCfg)) {
    Stop-WithError "'$DocsCfg' not found. Start Assetto Corsa (or Content Manager) once so it creates its settings, then run this again."
}
Write-Ok "Settings folder: $DocsCfg"

if ($AcRoot) {
    if (-not (Test-AcRoot $AcRoot)) { Stop-WithError "acs.exe not found in '$AcRoot'." }
    $AcRoot = (Resolve-Path -LiteralPath $AcRoot).Path
} else {
    $AcRoot = Find-AcRoot
    while (-not $AcRoot) {
        Write-Warn 'Could not find Assetto Corsa through Steam.'
        $answer = Read-Host '    Paste your assettocorsa folder (the one with acs.exe), or press Enter to quit'
        if ([string]::IsNullOrWhiteSpace($answer)) { exit 1 }
        $answer = $answer.Trim().Trim('"')
        if (Test-AcRoot $answer) { $AcRoot = (Resolve-Path -LiteralPath $answer).Path }
    }
}
Write-Ok "Game folder: $AcRoot"

# Running processes would overwrite or ignore the new settings
$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    @('acs', 'acs_x86', 'Content Manager', 'AssettoCorsa') -contains $_.ProcessName
})
if ($running.Count -gt 0 -and -not $Force -and -not $DryRun) {
    $names = ($running | ForEach-Object { $_.ProcessName + '.exe' } | Select-Object -Unique) -join ', '
    Write-Warn "Please close: $names (otherwise they may overwrite the new settings)."
    $answer = Read-Host '    Press Enter once they are closed, or type Q to quit'
    if ($answer -match '^\s*[qQ]') { exit 1 }
}

# Custom Shaders Patch
$cspVersion = $null
$cspBuild = 0
$manifestIni = Join-Path $AcRoot 'extension\config\data_manifest.ini'
if (Test-Path -LiteralPath $manifestIni) {
    foreach ($l in [System.IO.File]::ReadAllLines($manifestIni)) {
        if ($l -match '^\s*SHADERS_PATCH\s*=\s*(.+?)\s*$') { $cspVersion = $Matches[1] }
        elseif ($l -match '^\s*SHADERS_PATCH_BUILD\s*=\s*(\d+)') { $cspBuild = [int]$Matches[1] }
    }
}
$hasCsp = (Test-Path -LiteralPath (Join-Path $AcRoot 'dwrite.dll')) -and ($cspBuild -gt 0)
if ($hasCsp) {
    Write-Ok "Custom Shaders Patch $cspVersion (build $cspBuild)"
    if ($cspBuild -lt $CspBuild030) {
        Write-Warn 'CSP 0.3.x (free, Content Manager > Settings > Custom Shaders Patch) is recommended.'
    }
    if ($Filter -eq 'MaxVisuals_AgX' -and $cspBuild -lt $CspBuildAgX) {
        Write-Warn 'This CSP build has no AgX tonemapping - activating MaxVisuals instead.'
        $Filter = 'MaxVisuals'
    }
} else {
    Write-Warn 'Custom Shaders Patch was not found. Most of this pack needs it:'
    Write-Warn 'install it from Content Manager > Settings > Custom Shaders Patch, then run this again.'
    if ($Filter -eq 'MaxVisuals_AgX') { $Filter = 'MaxVisuals' }
    if (-not $SkipCsp -and -not $Force) {
        Write-Warn 'CSP settings will be skipped this time (use -Force to write them anyway).'
        $SkipCsp = $true
    }
}

$script:BackupDir = Join-Path (Join-Path $DocsAc 'MaxVisuals-Backups') (Get-Date -Format 'yyyyMMdd-HHmmss')

try {
    # 1. Post-processing filters ------------------------------------------------
    Write-Step 'Installing post-processing filters'
    $ppDir = Join-Path $AcRoot 'system\cfg\ppfilters'
    if (-not (Test-Path -LiteralPath $ppDir)) { Stop-WithError "'$ppDir' not found - is this a complete Assetto Corsa install?" }
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $FilesDir 'ppfilters') -Filter '*.ini') {
        $dest = Join-Path $ppDir $f.Name
        if ($DryRun) { Write-Info "would copy $($f.Name) -> $ppDir"; continue }
        Backup-File $dest
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        Write-Ok "$($f.Name) -> $ppDir"
    }

    # 2. video.ini --------------------------------------------------------------
    if ($SkipVideo) {
        Write-Step 'Video settings skipped (-SkipVideo)'
    } else {
        Write-Step "Applying $Preset video settings"
        $videoIni = Join-Path $DocsCfg 'video.ini'
        if (-not (Test-Path -LiteralPath $videoIni)) {
            Write-Warn "video.ini not found. Open Content Manager > Settings > Assetto Corsa > Video once (or start AC), then run this again."
        } else {
            $video = Read-PackIni (Join-Path $FilesDir "video\$($Preset.ToLowerInvariant()).ini")
            foreach ($v in $video) {
                if ($v.Section -eq 'POST_PROCESS' -and $v.Key -eq 'FILTER') { $v.Value = $Filter }
            }
            Backup-File $videoIni
            # Content Manager keeps "original" copies of some values while it
            # temporarily overrides them; drop those so the new values stick.
            Update-IniFile $videoIni $video @('VIDEO/__CM_ORIGINAL_SHADOW_MAP_SIZE', 'CUBEMAP/__ORIG_FACES_PER_FRAME', 'CUBEMAP/__ORIG_FARPLANE')
        }
    }

    # 3. Custom Shaders Patch settings ----------------------------------------
    if ($SkipCsp) {
        Write-Step 'Custom Shaders Patch settings skipped'
    } else {
        Write-Step "Applying Custom Shaders Patch preset 'Max Visuals - $Preset'"
        $extDir = Join-Path $DocsCfg 'extension'
        $entries = Read-PackIni (Join-Path $FilesDir "csp-presets\Max Visuals - $Preset.ini")
        $modules = $entries | Where-Object { $_.Section -like '*:*' } | Group-Object { ($_.Section -split ':', 2)[0] }
        foreach ($module in $modules) {
            $settings = New-Object 'System.Collections.Generic.List[object]'
            foreach ($e in $module.Group) {
                $settings.Add([pscustomobject]@{
                    Section = ($e.Section -split ':', 2)[1]
                    Key     = $e.Key
                    Value   = $e.Value
                })
            }
            $file = Join-Path $extDir ($module.Name.ToLowerInvariant() + '.ini')
            Backup-File $file
            Update-IniFile $file $settings
        }
    }

    # 4. Content Manager presets ------------------------------------------------
    $cmDir = Join-Path $env:LOCALAPPDATA 'AcTools Content Manager'
    if (Test-Path -LiteralPath $cmDir) {
        Write-Step 'Adding presets to Content Manager'
        $cmPresets = Join-Path $cmDir 'Presets\Custom Shaders Patch Presets'
        if (-not $DryRun -and -not (Test-Path -LiteralPath $cmPresets)) {
            New-Item -ItemType Directory -Path $cmPresets -Force | Out-Null
        }
        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $FilesDir 'csp-presets') -Filter '*.ini') {
            $dest = Join-Path $cmPresets $f.Name
            if ($DryRun) { Write-Info "would copy '$($f.Name)' -> $cmPresets"; continue }
            Backup-File $dest
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
            Write-Ok "'$($f.Name)'"
        }
    }
} catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception -is [System.UnauthorizedAccessException] -or
        $_.Exception.InnerException -is [System.UnauthorizedAccessException]) {
        Write-Host 'Access denied - try running the installer as administrator.' -ForegroundColor Red
    }
    if ($script:Manifest.Count -gt 0) {
        Write-Host 'Some files were already changed; run Uninstall.bat to restore them.' -ForegroundColor Yellow
    }
    exit 1
}

# ---------------------------------------------------------------------------
Write-Host ''
if ($DryRun) {
    Write-Host 'Dry run finished - nothing was changed.' -ForegroundColor Yellow
    exit 0
}
Write-Host 'Done!' -ForegroundColor Green
if ($script:Manifest.Count -gt 0) {
    Write-Host "Backup of the previous files: $($script:BackupDir)"
}
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor White
Write-Host '  1. Weather: in Content Manager > Settings > Custom Shaders Patch > Weather FX,'
Write-Host '     use Pure (best) or Sol. With CSP''s default style, enable its linear color'
Write-Host '     space option in the style settings.'
Write-Host "  2. Start a session: the '$Filter' filter is already selected."
Write-Host '  3. Too heavy? Re-run with the High preset (Install-High.bat).'
Write-Host '  4. Undo everything: Uninstall.bat'
exit 0
