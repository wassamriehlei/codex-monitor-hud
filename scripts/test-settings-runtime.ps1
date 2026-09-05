param([switch]$Portable)
# Synthetic settings only; never opens production settings or session roots.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('.test-output\settings-latency-' + [Guid]::NewGuid().ToString('N'))
$localRoot = Join-Path $testRoot 'localapp'
$stateRoot = Join-Path $localRoot 'CodexMonitorHUD'
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'config.default.json') -Destination (Join-Path $stateRoot 'settings.json')
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SettingsTestNative {
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr handle);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr handle, uint message, IntPtr w, IntPtr l);
}
'@
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = 'powershell.exe'
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'src\CodexMonitorHUD.ps1') + '" -SettingsHost -DebugLog -InstanceId settings-test-' + [Guid]::NewGuid().ToString('N')
$start.EnvironmentVariables['LOCALAPPDATA'] = $localRoot
$start.EnvironmentVariables.Remove('CODEX_MONITOR_HUD_DATA_HOME')
if ($Portable) {
    $start.EnvironmentVariables['CODEX_MONITOR_HUD_DATA_HOME'] = $localRoot
    $start.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $testRoot 'unrelated-localapp'
}
$start.EnvironmentVariables['CODEX_MONITOR_HUD_HOME'] = Join-Path $testRoot 'profile'
$start.EnvironmentVariables['CODEX_MONITOR_HUD_DEBUG_PATH'] = Join-Path $testRoot 'startup.log'
$start.RedirectStandardError = $true
$start.RedirectStandardOutput = $true
$timer = [Diagnostics.Stopwatch]::StartNew()
$process = [Diagnostics.Process]::Start($start)
$errors = $process.StandardError.ReadToEndAsync()
$output = $process.StandardOutput.ReadToEndAsync()
try {
    $handle = [IntPtr]::Zero
    while ($timer.Elapsed.TotalSeconds -lt 20) {
        $process.Refresh()
        if ($process.HasExited) { throw ('Settings startup failed: ' + $errors.Result) }
        $handle = $process.MainWindowHandle
        if ($handle -ne [IntPtr]::Zero -and [SettingsTestNative]::IsWindowVisible($handle)) { break }
        Start-Sleep -Milliseconds 40
    }
    if ($handle -eq [IntPtr]::Zero) { throw 'Settings did not become visible.' }
    $coldMs = $timer.ElapsedMilliseconds
    $window = [Windows.Automation.AutomationElement]::FromHandle($handle)
    $about = $window.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'AboutTab')))
    if ($null -eq $about) { throw 'About tab is missing.' }
    $about.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 100
    $version = $window.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'AboutVersion')))
    $expectedVersion = [string](Get-Content -Raw -LiteralPath (Join-Path $root '.codex-plugin\plugin.json') | ConvertFrom-Json).version
    if ($null -eq $version -or -not $version.Current.Name.Contains($expectedVersion)) { throw 'About version is not synchronized.' }
    $general = $window.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'GeneralTab')))
    $general.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
    $warm = @()
    foreach ($iteration in 1..3) {
        [void][SettingsTestNative]::PostMessage($handle,0x10,[IntPtr]::Zero,[IntPtr]::Zero)
        $timer.Restart()
        while ([SettingsTestNative]::IsWindowVisible($handle) -and $timer.Elapsed.TotalSeconds -lt 5) { Start-Sleep -Milliseconds 25 }
        if ($process.HasExited -or [SettingsTestNative]::IsWindowVisible($handle)) { throw 'Settings close did not retain a hidden host.' }
        $changedConfig = Get-Content -Raw -LiteralPath (Join-Path $stateRoot 'settings.json') | ConvertFrom-Json
        $changedConfig.floatingBallSize = 64 + $iteration
        [IO.File]::WriteAllText((Join-Path $stateRoot 'settings.json'),($changedConfig | ConvertTo-Json -Depth 12))
        $timer.Restart()
        [IO.File]::WriteAllText((Join-Path $stateRoot 'settings-host-open.signal'),[DateTime]::UtcNow.ToString('O'))
        while (-not [SettingsTestNative]::IsWindowVisible($handle) -and $timer.Elapsed.TotalSeconds -lt 5) { Start-Sleep -Milliseconds 20 }
        if (-not [SettingsTestNative]::IsWindowVisible($handle)) { throw ('Cached settings failed to reopen: ' + $(if ($process.HasExited) { $errors.Result } else { 'timeout' })) }
        $warm += $timer.ElapsedMilliseconds
        $window = [Windows.Automation.AutomationElement]::FromHandle($handle)
        $sizeControl = $window.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'FloatingBallSizeSlider')))
        if ($null -eq $sizeControl) { throw 'Reopened settings did not expose its ball size control.' }
        $sizeValue = $sizeControl.GetCurrentPattern([Windows.Automation.RangeValuePattern]::Pattern)
        if ($sizeValue.Current.Value -ne 64 + $iteration) { throw 'Cached settings did not reload external configuration changes.' }
    }
    if (($warm | Measure-Object -Maximum).Maximum -gt 1500) { throw 'Warm settings latency exceeded 1.5 seconds.' }
    if ($Portable -and (Test-Path -LiteralPath (Join-Path $testRoot 'unrelated-localapp\CodexMonitorHUD'))) { throw 'Portable Settings wrote installed state.' }
    [IO.File]::WriteAllText((Join-Path $stateRoot 'settings-host-exit.signal'),'test shutdown')
    if (-not $process.WaitForExit(5000)) { throw 'Cached settings host ignored graceful shutdown.' }
    if ($process.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($errors.Result)) { throw ('Settings runtime failed: ' + $errors.Result) }
    $metrics = [pscustomobject]@{cold_visible_ms=$coldMs;warm_visible_ms=$warm;reused_hwnd=$handle.ToInt64();graceful_exit=$true}
    $metrics | ConvertTo-Json | Tee-Object -FilePath (Join-Path $testRoot 'latency.json')
} finally {
    if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
}
