$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexMonitorHUD'
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
$transcriptStarted = $false
try {
    Start-Transcript -Path (Join-Path $stateRoot 'installer.log') -Append | Out-Null
    $transcriptStarted = $true
    # An installation never inherits a portable instance's state overrides.
    Remove-Item Env:CODEX_MONITOR_HUD_DATA_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:CODEX_MONITOR_HUD_INSTANCE_ID -ErrorAction SilentlyContinue
    & (Join-Path $PSScriptRoot 'install.ps1') -UseBundledRuntime -SkipLaunch
} catch {
    Write-Output $_
    exit 1
} finally {
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
}
