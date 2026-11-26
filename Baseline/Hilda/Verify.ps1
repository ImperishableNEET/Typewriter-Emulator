[CmdletBinding()]
param(
    [string]$Executable = (Join-Path $PSScriptRoot '..\..\Typewriter Emulator.exe'),
    [string]$Godot = (Join-Path $env:TEMP 'godiva-player-tools\Godot_v4.4.1-stable_win64_console.exe')
)
$ErrorActionPreference = 'Stop'
$candidate = (Resolve-Path -LiteralPath $Executable).Path
$engine = (Resolve-Path -LiteralPath $Godot).Path
$folder = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ('hilda-check-' + [guid]::NewGuid()))
$originalAppData = $env:APPDATA
$originalGuard = $env:HILDA_QA
try {
    $env:APPDATA = $folder.FullName
    $env:HILDA_QA = 'isolated'
    $log = Join-Path $folder.FullName 'result.log'
    & $engine --headless --main-pack $candidate --quit-after 1200 --script (Join-Path $PSScriptRoot 'first_action.gd') *> $log
    if ($LASTEXITCODE -or !(Select-String -LiteralPath $log -SimpleMatch 'HILDA_FIRST_ACTION_OK') -or (Select-String -LiteralPath $log -Pattern 'ERROR:')) {
        throw "Hilda action check failed. See $log"
    }
    Write-Host "HILDA_FIRST_ACTION_OK ($log)"
    $log = Join-Path $folder.FullName 'keyboard.log'
    & $engine --headless --main-pack $candidate --quit-after 1200 --script (Join-Path $PSScriptRoot 'keyboard.gd') *> $log
    if ($LASTEXITCODE -or !(Select-String -LiteralPath $log -SimpleMatch 'HILDA_KEYBOARD_OK') -or (Select-String -LiteralPath $log -Pattern 'ERROR:')) {
        throw "Hilda keyboard check failed. See $log"
    }
    Write-Host "HILDA_KEYBOARD_OK ($log)"
} finally {
    $env:APPDATA = $originalAppData
    $env:HILDA_QA = $originalGuard
}
