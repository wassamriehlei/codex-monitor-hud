param([string]$HudHome = '', [switch]$Portable)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($Portable) { $env:CODEX_MONITOR_HUD_DATA_HOME = Join-Path $root 'portable-data' }
Import-Module (Join-Path $root 'src\MonitorHud.Core.psm1') -Force
$paths = Get-HudPaths $root
$config = Get-HudConfig $paths
# A stale shortcut must not defeat a disabled setting.
if (-not [bool]$config.startWithWindows) { return }
if (-not [string]::IsNullOrWhiteSpace($HudHome)) { $env:CODEX_MONITOR_HUD_HOME = $HudHome }
# A fresh Windows login is an explicit opt-in launch, not an MCP restart.
foreach ($name in @('manual-exit.signal','exit.signal')) {
    Remove-Item -LiteralPath (Join-Path $paths.StateRoot $name) -Force -ErrorAction SilentlyContinue
}
if ($Portable) { & (Join-Path $PSScriptRoot 'start-portable.ps1') -HudHome $HudHome }
else { & (Join-Path $PSScriptRoot 'start.ps1') }
