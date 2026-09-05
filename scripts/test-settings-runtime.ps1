param([switch]$Portable, [switch]$DetectWsl)
# Synthetic settings only; never opens production settings or session roots.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('.test-output\settings-latency-' + [Guid]::NewGuid().ToString('N'))
$localRoot = Join-Path $testRoot 'localapp'
$stateRoot = Join-Path $localRoot 'CodexMonitorHUD'
$instanceId = 'settings-test-' + [Guid]::NewGuid().ToString('N')
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
$start.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'src\CodexMonitorHUD.ps1') + '" -SettingsHost -DebugLog -InstanceId ' + $instanceId
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
    $expectedVersion = [string](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root '.codex-plugin\plugin.json') | ConvertFrom-Json).version
    if ($null -eq $version -or -not $version.Current.Name.Contains($expectedVersion)) { throw 'About version is not synchronized.' }
    $sources = $window.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'SourcesTab')))
    $sources.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 100
    $wslToggle = $window.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'SourceWslCheck')))
    $wslHome = $window.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'WslHomeText')))
    $wslDistribution = $window.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'WslDistributionCombo')))
    $wslDetect = $window.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'WslDetectButton')))
    if ($null -eq $wslToggle -or $null -eq $wslHome -or $null -eq $wslDistribution -or $null -eq $wslDetect) { throw 'WSL source configuration controls are incomplete.' }
    if ($wslToggle.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -ne [Windows.Automation.ToggleState]::On) { throw 'WSL source did not inherit its enabled default.' }
    $wslHomeValue = $wslHome.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value
    if ($wslHomeValue -ne (Join-Path $testRoot 'profile')) { throw 'Existing WSL bridge was not migrated into the Settings UI.' }
    if ($DetectWsl) {
        $wslDetect.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
        $detectTimer = [Diagnostics.Stopwatch]::StartNew()
        $detectedConfig = $null
        while ($detectTimer.Elapsed.TotalSeconds -lt 10) {
            $detectedConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $stateRoot 'settings.json') | ConvertFrom-Json
            if ([string]$detectedConfig.wsl.home -match '^\\\\wsl\.localhost\\' -and -not [string]::IsNullOrWhiteSpace([string]$detectedConfig.wsl.distribution)) { break }
            Start-Sleep -Milliseconds 100
        }
        if ($null -eq $detectedConfig -or [string]$detectedConfig.wsl.home -notmatch '^\\\\wsl\.localhost\\' -or -not [bool]$detectedConfig.sessionSources.wsl) { throw 'WSL detection did not persist an enabled independent source.' }
    }
    $general = $window.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'GeneralTab')))
    $general.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
    $warm = @()
    foreach ($iteration in 1..3) {
        [void][SettingsTestNative]::PostMessage($handle,0x10,[IntPtr]::Zero,[IntPtr]::Zero)
        $timer.Restart()
        while ([SettingsTestNative]::IsWindowVisible($handle) -and $timer.Elapsed.TotalSeconds -lt 5) { Start-Sleep -Milliseconds 25 }
        if ($process.HasExited -or [SettingsTestNative]::IsWindowVisible($handle)) { throw 'Settings close did not retain a hidden host.' }
        $changedConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $stateRoot 'settings.json') | ConvertFrom-Json
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
    [IO.File]::WriteAllText((Join-Path $stateRoot 'exit.signal'),'test shutdown')
    if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
    # WSL detection deliberately exercises the asynchronous restart path. The
    # restart helper can outlive the settings host briefly, so stop only this
    # synthetic instance and wait until it can no longer lock repository DLLs.
    $cleanupTimer = [Diagnostics.Stopwatch]::StartNew()
    $quietSince = [DateTime]::MinValue
    while ($cleanupTimer.Elapsed.TotalSeconds -lt 12) {
        [IO.File]::WriteAllText((Join-Path $stateRoot 'exit.signal'),'test shutdown')
        $matches = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains($instanceId)
        })
        foreach ($match in $matches) {
            Stop-Process -Id $match.ProcessId -Force -ErrorAction SilentlyContinue
        }
        if ($matches.Count -eq 0) {
            if ($quietSince -eq [DateTime]::MinValue) { $quietSince = [DateTime]::UtcNow }
            if (([DateTime]::UtcNow - $quietSince).TotalMilliseconds -ge 750) { break }
        } else {
            $quietSince = [DateTime]::MinValue
        }
        Start-Sleep -Milliseconds 100
    }
}
