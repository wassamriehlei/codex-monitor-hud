param([switch]$RemoveSettings)

$ErrorActionPreference = 'Stop'
$pluginName = 'codex-monitor-hud'
$targetRoot = Join-Path $HOME ('plugins\' + $pluginName)
$marketplacePath = Join-Path $HOME '.agents\plugins\marketplace.json'
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexMonitorHUD'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Monitor HUD Settings.lnk'
$startMenuFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex Monitor HUD'

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
Import-Module (Join-Path $PSScriptRoot '..\src\MonitorHud.Startup.psm1') -Force
Set-HudStartupRegistration -Enabled $false -PluginRoot $targetRoot -Portable $false
[IO.File]::WriteAllText((Join-Path $stateRoot 'settings-host-exit.signal'), [DateTime]::UtcNow.ToString('O'))
[IO.File]::WriteAllText((Join-Path $stateRoot 'manual-exit.signal'), [DateTime]::UtcNow.ToString('O'))
[IO.File]::WriteAllText((Join-Path $stateRoot 'exit.signal'), [DateTime]::UtcNow.ToString('O'))
foreach ($entry in @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -in @('dotnet.exe','powershell.exe','CodexMonitorHud.exe') -and
    $_.ProcessId -ne $PID -and $_.CommandLine -like ('*' + $targetRoot + '\*') -and
    $_.CommandLine -notlike '*Get-CimInstance*'
})) {
    $process = Get-Process -Id $entry.ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) { continue }
    try {
        if (-not $process.WaitForExit(10000)) { throw 'Close the HUD and its Settings window before uninstalling.' }
    } finally { $process.Dispose() }
}

if (Test-Path -LiteralPath $marketplacePath) {
    $marketplace = Get-Content -Raw -Encoding UTF8 -LiteralPath $marketplacePath | ConvertFrom-Json
    $marketplace.plugins = @($marketplace.plugins | Where-Object { $_.name -ne $pluginName })
    $marketplace | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $marketplacePath
}

if ((Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path -ne $targetRoot -and (Test-Path -LiteralPath $targetRoot)) {
    Remove-Item -LiteralPath $targetRoot -Recurse -Force
} else {
    Write-Output "Plugin files remain at $targetRoot because the uninstaller is running from that directory. Remove it after Codex closes."
}

if ($RemoveSettings -and (Test-Path -LiteralPath $stateRoot)) {
    Start-Sleep -Milliseconds 900
    Remove-Item -LiteralPath $stateRoot -Recurse -Force
}

if (Test-Path -LiteralPath $desktopShortcut) { Remove-Item -LiteralPath $desktopShortcut -Force }
if (Test-Path -LiteralPath $startMenuFolder) { Remove-Item -LiteralPath $startMenuFolder -Recurse -Force }

Write-Output 'Codex Monitor HUD was removed from the personal marketplace.'
