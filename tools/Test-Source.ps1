[CmdletBinding()]
param([Parameter(Mandatory)][string]$Godot)
$ErrorActionPreference = 'Stop'
$engine = (Resolve-Path $Godot).Path
$root = Split-Path $PSScriptRoot
$work = New-Item -ItemType Directory (Join-Path ([IO.Path]::GetTempPath()) ("typewriter-qa-" + [guid]::NewGuid()))
$prior = @($env:APPDATA, $env:GODIVA_FIXTURE_DIR, $env:HILDA_QA, $env:HILDA_PROOF)
$originalTemp = $env:TEMP
function Check([string]$marker, [string[]]$extra) {
    $log = Join-Path $work "$marker.log"
    & $engine --headless --path (Join-Path $root GodivaStudio) --quit-after 1800 @extra *> $log
    if ($LASTEXITCODE -or !(Select-String -LiteralPath $log -SimpleMatch $marker) -or (Select-String -LiteralPath $log -Pattern 'ERROR:')) {
        Get-Content -LiteralPath $log -Tail 50 | Write-Host
        throw "Source check failed. See $log"
    }
    Write-Output $marker
}
try {
    $env:APPDATA = $work.FullName
    $env:TEMP = $work.FullName
    New-Item -ItemType Directory -Path (Join-Path $work 'godiva-player-tools') | Out-Null
    $env:GODIVA_FIXTURE_DIR = Join-Path $root 'Baseline/Godiva'
    $env:HILDA_QA = 'isolated'
    $env:HILDA_PROOF = Join-Path $work 'keyboard.png'
    Check 'GODIVA_DESKTOP_TEST_OK' @('--','--self-test')
    Check 'GODIVA_BASELINE_MATCH' @('--script',(Join-Path $root 'Baseline/Godiva/compare.gd'))
    Check 'HILDA_FIRST_ACTION_OK' @('--script',(Join-Path $root 'Baseline/Hilda/first_action.gd'))
    Check 'HILDA_KEYBOARD_OK' @('--script',(Join-Path $root 'Baseline/Hilda/keyboard.gd'))
} finally {
    $env:APPDATA,$env:GODIVA_FIXTURE_DIR,$env:HILDA_QA,$env:HILDA_PROOF = $prior
    $env:TEMP = $originalTemp
}
