param([string]$InstanceId = '')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
Import-Module (Join-Path $root 'src\MonitorHud.Core.psm1') -Force
$paths = Get-HudPaths $root
New-Item -ItemType Directory -Force -Path $paths.StateRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $paths.StateRoot 'exit.signal'), [DateTime]::UtcNow.ToString('O'))
$heartbeat = Join-Path $paths.StateRoot 'hud.heartbeat'
for ($attempt = 0; $attempt -lt 80 -and (Test-Path -LiteralPath $heartbeat); $attempt++) {
    Start-Sleep -Milliseconds 100
}
Remove-Item -LiteralPath (Join-Path $paths.StateRoot 'exit.signal') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $paths.StateRoot 'manual-exit.signal') -Force -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($InstanceId)) { Remove-Item Env:CODEX_MONITOR_HUD_INSTANCE_ID -ErrorAction SilentlyContinue }
else { $env:CODEX_MONITOR_HUD_INSTANCE_ID = $InstanceId }
& (Join-Path $PSScriptRoot 'start.ps1')
