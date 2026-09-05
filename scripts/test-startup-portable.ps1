param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $root ('.test-output\startup-portable-' + [Guid]::NewGuid().ToString('N'))
$startup = Join-Path $fixture 'startup'
$copyRoot = Join-Path $fixture 'portable copy'
New-Item -ItemType Directory -Force -Path $startup,(Join-Path $copyRoot 'scripts'),(Join-Path $copyRoot 'src') | Out-Null
Import-Module (Join-Path $root 'src\MonitorHud.Startup.psm1') -Force
Import-Module (Join-Path $root 'src\MonitorHud.Core.psm1') -Force
$link = Join-Path $startup 'Codex Monitor HUD.lnk'
$shell = New-Object -ComObject WScript.Shell
$oldData = $env:CODEX_MONITOR_HUD_DATA_HOME
$oldId = $env:CODEX_MONITOR_HUD_INSTANCE_ID
$oldBridge = $env:CODEX_MONITOR_HUD_HOME
$shortcut = $null
function Assert-Portable([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
try {
    $bridge = '\\wsl.localhost\Ubuntu\home\synthetic-user'
    Set-HudStartupRegistration -Enabled $true -PluginRoot $root -HudHome $bridge -Portable $false -StartupDirectory $startup
    Set-HudStartupRegistration -Enabled $true -PluginRoot $root -Portable $false -StartupDirectory $startup
    $shortcut = $shell.CreateShortcut($link)
    Assert-Portable ($shortcut.Arguments.Contains($bridge)) 'Repair lost the WSL bridge.'
    Assert-Portable (-not $shortcut.Arguments.Contains(' -Portable')) 'Installed shortcut became portable.'
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut); $shortcut = $null
    Set-HudStartupRegistration -Enabled $false -PluginRoot $copyRoot -StartupDirectory $startup
    Assert-Portable (Test-Path -LiteralPath $link) 'Disabling another copy removed this shortcut.'
    Set-HudStartupRegistration -Enabled $false -PluginRoot $root -StartupDirectory $startup
    Assert-Portable (-not (Test-Path -LiteralPath $link)) 'Owned startup shortcut remained.'
    $shortcut = $shell.CreateShortcut($link)
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'notepad.exe'
    $shortcut.Description = 'unrelated fixture'
    $shortcut.Save()
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut); $shortcut = $null
    $refused = $false
    try { Set-HudStartupRegistration -Enabled $true -PluginRoot $root -StartupDirectory $startup } catch { $refused = $true }
    Assert-Portable $refused 'An unrelated shortcut was overwritten.'
    Set-HudStartupRegistration -Enabled $false -PluginRoot $root -StartupDirectory $startup
    Assert-Portable (Test-Path -LiteralPath $link) 'An unrelated shortcut was removed.'
    Remove-Item -LiteralPath $link
    foreach ($file in @('start-portable.ps1','start-at-login.ps1')) {
        Copy-Item -LiteralPath (Join-Path $root ('scripts\' + $file)) -Destination (Join-Path $copyRoot 'scripts')
    }
    Copy-Item -LiteralPath (Join-Path $root 'src\MonitorHud.Core.psm1') -Destination (Join-Path $copyRoot 'src')
    Copy-Item -LiteralPath (Join-Path $root 'config.default.json') -Destination $copyRoot
    Copy-Item -LiteralPath (Join-Path $root 'locales') -Destination $copyRoot -Recurse
    # A synthetic start records routing only; no real HUD or Codex session access.
    [IO.File]::WriteAllText((Join-Path $copyRoot 'scripts\start.ps1'), @'
param([switch]$Settings)
[pscustomobject]@{data=$env:CODEX_MONITOR_HUD_DATA_HOME;instance=$env:CODEX_MONITOR_HUD_INSTANCE_ID;bridge=$env:CODEX_MONITOR_HUD_HOME;settings=[bool]$Settings}
'@)
    $first = & (Join-Path $copyRoot 'scripts\start-portable.ps1') -Settings -HudHome $bridge
    $second = & (Join-Path $copyRoot 'scripts\start-portable.ps1') -HudHome $bridge
    Assert-Portable ($first.data -eq (Join-Path $copyRoot 'portable-data')) 'Portable data escaped its folder.'
    Assert-Portable ($first.instance -match '^portable-[A-F0-9]{12}$' -and $first.instance -eq $second.instance) 'Portable instance identity is not stable.'
    Assert-Portable ($first.settings -and -not $second.settings) 'Portable settings routing failed.'
    $paths = Get-HudPaths $copyRoot
    Assert-Portable ($paths.ConfigPath -eq (Join-Path $copyRoot 'portable-data\CodexMonitorHUD\settings.json')) 'PowerShell portable config path mismatch.'
    New-Item -ItemType Directory -Force -Path $paths.StateRoot | Out-Null
    [IO.File]::WriteAllText((Join-Path $paths.StateRoot 'exit.signal'),'fixture')
    $disabled = @(& (Join-Path $copyRoot 'scripts\start-at-login.ps1') -Portable)
    Assert-Portable ($disabled.Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $paths.StateRoot 'exit.signal'))) 'Disabled login launcher changed state or launched.'
    $config = Get-HudConfig $paths
    $config.startWithWindows = $true
    Save-HudConfig $paths $config
    $login = & (Join-Path $copyRoot 'scripts\start-at-login.ps1') -Portable -HudHome $bridge
    Assert-Portable ($login.instance -eq $first.instance -and -not $login.settings -and $login.bridge -eq $bridge) 'Portable login route differs from manual launch.'
    Assert-Portable (-not (Test-Path -LiteralPath (Join-Path $paths.StateRoot 'exit.signal'))) 'Opt-in login left its stop signal.'
    Set-HudStartupRegistration -Enabled $true -PluginRoot $copyRoot -HudHome $bridge -Portable $true -StartupDirectory $startup
    $shortcut = $shell.CreateShortcut($link)
    Assert-Portable ($shortcut.Arguments.Contains(' -Portable') -and $shortcut.Arguments.Contains($copyRoot)) 'Portable shortcut parameters missing.'
    Write-Output 'Startup and portable routing: OK (synthetic shortcuts, ownership, WSL, disabled login, local state, stable instance)'
} finally {
    $env:CODEX_MONITOR_HUD_DATA_HOME = $oldData
    $env:CODEX_MONITOR_HUD_INSTANCE_ID = $oldId
    $env:CODEX_MONITOR_HUD_HOME = $oldBridge
    if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
}
