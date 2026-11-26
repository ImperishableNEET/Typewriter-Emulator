[CmdletBinding()]
param(
    [string]$Executable = (Join-Path $PSScriptRoot '..\..\Typewriter Emulator.exe'),
    [string]$Godot = (Join-Path $env:TEMP 'godiva-player-tools\Godot_v4.4.1-stable_win64_console.exe')
)
$ErrorActionPreference = 'Stop'
$package = (Resolve-Path -LiteralPath $Executable).Path
$engine = (Resolve-Path -LiteralPath $Godot).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('godiva-baseline-' + [guid]::NewGuid())
$null = New-Item -ItemType Directory -Path $work
$oldAppData = $env:APPDATA
$oldTemp = $env:TEMP
$oldFixture = $env:GODIVA_FIXTURE_DIR
try {
    $env:APPDATA = $work
    $env:TEMP = $work
    New-Item -ItemType Directory -Path (Join-Path $work 'godiva-player-tools') | Out-Null
    $env:GODIVA_FIXTURE_DIR = $PSScriptRoot
    function Assert-Run([string[]]$Arguments, [string]$LogName, [string]$Marker) {
        $path = Join-Path $work $LogName
        & $engine @Arguments *> $path
        if ($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $path -SimpleMatch -Pattern $Marker) -or (Select-String -LiteralPath $path -Pattern 'ERROR:')) {
            Get-Content -LiteralPath $path -Tail 50 | Write-Host
            throw "Godiva baseline check failed. See $path"
        }
        Write-Host $Marker
    }
    Assert-Run @('--headless','--main-pack',$package,'--quit-after','1800','--','--self-test') 'self-test.log' 'GODIVA_DESKTOP_TEST_OK'
    Assert-Run @('--headless','--main-pack',$package,'--quit-after','600','--script',(Join-Path $PSScriptRoot 'compare.gd')) 'comparison.log' 'GODIVA_BASELINE_MATCH'
    Write-Host "Isolated profile and logs: $work"
} finally {
    $env:APPDATA = $oldAppData
    $env:TEMP = $oldTemp
    $env:GODIVA_FIXTURE_DIR = $oldFixture
}
