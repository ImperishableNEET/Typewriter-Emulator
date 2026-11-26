[CmdletBinding()]
param(
    [string]$Executable,
    [string]$Godot = (Join-Path $env:TEMP 'godiva-player-tools\Godot_v4.4.1-stable_win64_console.exe'),
    [string]$HildaProof
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..\..\GodivaStudio')).Path
$inputArgs = if ($Executable) { '--main-pack', (Resolve-Path -LiteralPath $Executable).Path } else { '--path', $project }
$qaDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ('typewriter-tab-proof-' + [guid]::NewGuid()))
$envNames = 'APPDATA', 'HILDA_QA', 'TAB_PROOF_MACHINE', 'TAB_PROOF_IMAGE'
$before = @{}
foreach ($name in $envNames) { $before[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
    $env:APPDATA = $qaDir.FullName
    $env:HILDA_QA = 'isolated'
    foreach ($machine in 'godiva', 'hilda') {
        $env:TAB_PROOF_MACHINE = $machine
        $env:TAB_PROOF_IMAGE = if ($HildaProof -and $machine -eq 'hilda') {
            $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HildaProof)
        }
        $log = Join-Path $qaDir.FullName "$machine.log"
        & $Godot --headless @inputArgs --quit-after 1200 --script (Join-Path $PSScriptRoot 'typing.gd') *> $log
        if ($LASTEXITCODE -or !(Select-String -LiteralPath $log -SimpleMatch "TAB_STOPS_OK $machine") -or
            (Select-String -LiteralPath $log -Pattern '^(SCRIPT ERROR|ERROR):')) {
            Get-Content -LiteralPath $log -Tail 24 | Write-Host
            throw "$machine tab-stop test failed. See $log"
        }
        (Select-String -LiteralPath $log -SimpleMatch 'TAB_STOPS_OK').Line
    }
} finally {
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $before[$name]) }
}
