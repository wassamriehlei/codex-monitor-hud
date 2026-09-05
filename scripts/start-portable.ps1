param([switch]$Settings, [string]$HudHome = '')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$env:CODEX_MONITOR_HUD_DATA_HOME = Join-Path $root 'portable-data'
New-Item -ItemType Directory -Force -Path $env:CODEX_MONITOR_HUD_DATA_HOME | Out-Null
$portableState = Join-Path $env:CODEX_MONITOR_HUD_DATA_HOME 'CodexMonitorHUD'
New-Item -ItemType Directory -Force -Path $portableState | Out-Null
$portableConfig = Join-Path $portableState 'settings.json'
if (-not [IO.File]::Exists($portableConfig)) {
    try { [IO.File]::Copy((Join-Path $root 'config.default.json'), $portableConfig, $false) }
    catch [IO.IOException] { if (-not [IO.File]::Exists($portableConfig)) { throw } }
}
if (-not [string]::IsNullOrWhiteSpace($HudHome)) { $env:CODEX_MONITOR_HUD_HOME = $HudHome }
$hash = [Security.Cryptography.SHA256]::Create()
try {
    $digest = ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant())))).Replace('-','').Substring(0,12)
    $env:CODEX_MONITOR_HUD_INSTANCE_ID = 'portable-' + $digest
} finally { $hash.Dispose() }
& (Join-Path $PSScriptRoot 'start.ps1') -Settings:$Settings
