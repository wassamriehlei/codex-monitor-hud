param(
    [switch]$Settings,
    [switch]$Managed,
    [switch]$DebugLog,
    [switch]$Legacy
)
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'CodexMonitorHUD.exe'
$compiledStarted = $false
if (-not $Legacy -and (Test-Path -LiteralPath $app)) {
    $compiledArguments = @(
        '--plugin-root',
        ('"{0}"' -f $root)
    )
    if ($Settings) { $compiledArguments += '--open-settings' }
    if ($Managed) { $compiledArguments += '--managed' }
    if ($DebugLog) { $compiledArguments += '--debug-log' }
    if ($env:CODEX_MONITOR_HUD_INSTANCE_ID) { $compiledArguments += @('--instance-id',('"{0}"' -f $env:CODEX_MONITOR_HUD_INSTANCE_ID)) }
    try {
        $process = Start-Process -FilePath $app -WindowStyle Hidden -ArgumentList $compiledArguments -PassThru
        if ($process.WaitForExit(1200)) {
            $compiledStarted = $process.ExitCode -eq 0
        } else {
            $compiledStarted = $true
        }
    } catch {
        $compiledStarted = $false
    }
}
if ($compiledStarted) { return }

$scriptPath = Join-Path $root 'src\CodexMonitorHUD.ps1'
$arguments = @('-NoProfile', '-Sta', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $scriptPath))
if ($Settings) { $arguments += '-OpenSettings' }
if ($Managed) { $arguments += '-Managed' }
if ($DebugLog) { $arguments += '-DebugLog' }
if ($env:CODEX_MONITOR_HUD_INSTANCE_ID) { $arguments += @('-InstanceId',('"{0}"' -f $env:CODEX_MONITOR_HUD_INSTANCE_ID)) }
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $arguments
