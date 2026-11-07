# Creates "Toss-Up" shortcuts on the Desktop and in the Start menu.
# They open index.html in its own window using Microsoft Edge or Google Chrome app mode,
# with the Toss-Up icon. Run it again if you move the Toss-Up folder.
$ErrorActionPreference = 'Stop'

try {
    $appDir = Split-Path -Parent $PSScriptRoot
    $index  = Join-Path $appDir 'index.html'
    $icon   = Join-Path $appDir 'toss-up.ico'
    if (-not (Test-Path -LiteralPath $index)) {
        throw "index.html was not found in $appDir. Keep the tools folder inside the Toss-Up folder."
    }

    # file:///C:/.../index.html, with spaces and other characters encoded
    $url = ([System.Uri]$index).AbsoluteUri

    # Prefer Edge (installed on every Windows 10/11 PC), then Chrome.
    $roots = @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA) | Where-Object { $_ }
    $browsers = @('Microsoft\Edge\Application\msedge.exe', 'Google\Chrome\Application\chrome.exe')
    $browser = $null
    foreach ($rel in $browsers) {
        foreach ($root in $roots) {
            $candidate = Join-Path $root $rel
            if (Test-Path -LiteralPath $candidate) { $browser = $candidate; break }
        }
        if ($browser) { break }
    }

    $shell = New-Object -ComObject WScript.Shell
    $folders = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs')) | Where-Object { $_ }
    foreach ($dir in $folders) {
        $lnkPath = Join-Path $dir 'Toss-Up.lnk'
        $lnk = $shell.CreateShortcut($lnkPath)
        if ($browser) {
            $lnk.TargetPath = $browser
            $lnk.Arguments  = "--app=`"$url`" --window-size=1300,900"
        } else {
            $lnk.TargetPath = $index
            $lnk.Arguments  = ''
        }
        $lnk.WorkingDirectory = $appDir
        if (Test-Path -LiteralPath $icon) { $lnk.IconLocation = "$icon,0" }
        $lnk.Description = 'Toss-Up: settle a decision in an interesting way'
        $lnk.Save()
        Write-Host "Created $lnkPath"
    }

    Write-Host ''
    if ($browser) {
        Write-Host "The shortcut opens Toss-Up in its own window using $browser"
    } else {
        Write-Host 'Edge or Chrome was not found, so the shortcut opens Toss-Up in your default browser.'
    }
    Write-Host 'If you move the Toss-Up folder, run Add-Shortcuts.bat again.'
} catch {
    Write-Host "Couldn't create the shortcuts: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
