param(
    [ValidateSet('Debug','Release')][string]$Configuration = 'Release',
    [switch]$SkipTests,
    [switch]$RunRuntimeTests
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$privateDotnet = Join-Path $root 'private\toolchain\dotnet\dotnet.exe'
$dotnet = if (Test-Path -LiteralPath $privateDotnet) {
    $privateDotnet
} else {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw 'The .NET 10 SDK is required to build v3.4.0. The repository-private SDK was not found and dotnet is not on PATH.' }
    $command.Source
}
$dotnetRoot = Split-Path -Parent $dotnet
$toolHome = Join-Path $root 'private\toolchain'
if (-not (Test-Path -LiteralPath $toolHome)) { $toolHome = Join-Path $env:TEMP 'CodexMonitorHudDotnetHome' }
New-Item -ItemType Directory -Force -Path $toolHome | Out-Null
$env:DOTNET_CLI_HOME = $toolHome
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:AVALONIA_TELEMETRY_OPTOUT = '1'
$env:NUGET_PACKAGES = Join-Path $toolHome 'nuget'

& $dotnet build (Join-Path $root 'CodexMonitorHud.slnx') -c $Configuration
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed with exit code $LASTEXITCODE" }
if (-not $SkipTests) {
    & $dotnet run --project (Join-Path $root 'tests-dotnet\CodexMonitorHud.Core.Tests\CodexMonitorHud.Core.Tests.csproj') -c $Configuration --no-build -- $root
    if ($LASTEXITCODE -ne 0) { throw "Core tests failed with exit code $LASTEXITCODE" }
}

$stage = Join-Path $root 'runtime\win-x64'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
$runtimeStage = Join-Path $stage 'dotnet'
New-Item -ItemType Directory -Force -Path $runtimeStage | Out-Null
$publishStage = Join-Path $env:TEMP ('codex-monitor-hud-publish-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $publishStage | Out-Null
$appProject = Join-Path $root 'src-dotnet\CodexMonitorHud.App\CodexMonitorHud.App.csproj'
try {
    & $dotnet restore $appProject -r win-x64
    if ($LASTEXITCODE -ne 0) { throw "dotnet restore for win-x64 failed with exit code $LASTEXITCODE" }
    & $dotnet publish $appProject -c $Configuration --no-restore -r win-x64 --self-contained false -o $publishStage `
        -p:UseAppHost=true `
        -p:PublishSingleFile=true `
        -p:DebugType=None `
        -p:DebugSymbols=false `
        -p:AppHostDotNetSearch=AppRelative `
        -p:AppHostRelativeDotNet=runtime/win-x64/dotnet
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }
    $publishedExe = Join-Path $publishStage 'CodexMonitorHud.exe'
    if (-not (Test-Path -LiteralPath $publishedExe)) { throw 'Single-file AppHost was not produced.' }
    Copy-Item -LiteralPath $publishedExe -Destination (Join-Path $root 'CodexMonitorHUD.exe') -Force
    Copy-Item -LiteralPath $publishedExe -Destination (Join-Path $root 'CodexMonitorHUD-Settings.exe') -Force
} finally {
    if (Test-Path -LiteralPath $publishStage) { Remove-Item -LiteralPath $publishStage -Recurse -Force }
}

$coreRuntime = Get-ChildItem -LiteralPath (Join-Path $dotnetRoot 'shared\Microsoft.NETCore.App') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
$desktopRuntime = Get-ChildItem -LiteralPath (Join-Path $dotnetRoot 'shared\Microsoft.WindowsDesktop.App') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
$hostFxr = Get-ChildItem -LiteralPath (Join-Path $dotnetRoot 'host\fxr') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if ($null -eq $coreRuntime -or $null -eq $desktopRuntime -or $null -eq $hostFxr) { throw 'The selected SDK does not contain the required Windows Desktop runtime.' }
Copy-Item -LiteralPath $dotnet -Destination (Join-Path $runtimeStage 'dotnet.exe') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $runtimeStage 'host\fxr'),(Join-Path $runtimeStage 'shared\Microsoft.NETCore.App'),(Join-Path $runtimeStage 'shared\Microsoft.WindowsDesktop.App') | Out-Null
Copy-Item -LiteralPath $hostFxr.FullName -Destination (Join-Path $runtimeStage 'host\fxr') -Recurse -Force
Copy-Item -LiteralPath $coreRuntime.FullName -Destination (Join-Path $runtimeStage 'shared\Microsoft.NETCore.App') -Recurse -Force
Copy-Item -LiteralPath $desktopRuntime.FullName -Destination (Join-Path $runtimeStage 'shared\Microsoft.WindowsDesktop.App') -Recurse -Force

# These diagnostics binaries are not used by the HUD. Keeping host/runtime DLLs
# intact preserves supported WPF behavior while reducing every release package.
Get-ChildItem -LiteralPath $runtimeStage -File -Recurse | Where-Object {
    $_.Name -eq 'createdump.exe' -or $_.Name -eq 'mscordbi.dll' -or $_.Name -like 'mscordaccore*.dll'
} | Remove-Item -Force

$metadata = [ordered]@{
    product = 'Codex Monitor HUD'
    version = '3.4.0'
    configuration = $Configuration
    framework = 'net10.0-windows'
    runtime = $coreRuntime.Name
    windows_desktop_runtime = $desktopRuntime.Name
}
[IO.File]::WriteAllText((Join-Path $stage 'runtime.json'), ($metadata | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
$healthPath = Join-Path $stage 'health-check.json'
$healthProcess = Start-Process -FilePath (Join-Path $root 'CodexMonitorHUD.exe') -ArgumentList @('--plugin-root',('"' + $root + '"'),'--health-check',('"' + $healthPath + '"')) -PassThru -Wait
if ($healthProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $healthPath)) { throw 'Staged compiled runtime health check failed.' }
$health = Get-Content -Raw -Encoding UTF8 -LiteralPath $healthPath | ConvertFrom-Json
if ([string]$health.version -ne '3.4.0' -or [string]$health.config -ne 'ok' -or [string]$health.xaml -ne 'ok' -or [string]$health.parser -ne 'ok') {
    throw ('Staged compiled runtime health check returned an invalid result: ' + ($health | ConvertTo-Json -Compress))
}
if ($RunRuntimeTests) {
    $runtimeGateRoot = Join-Path $env:TEMP ('codex-monitor-hud-staged-gate-' + [Guid]::NewGuid().ToString('N'))
    try {
        & (Join-Path $root 'scripts\test-runtime-isolated.ps1') -HostMode compiled -Mode list -TaskCount 5 -ChurnCycles 0 -TestOutputRoot $runtimeGateRoot
        & (Join-Path $root 'scripts\test-runtime-isolated.ps1') -HostMode compiled -Mode split -TaskCount 5 -ChurnCycles 0 -TestOutputRoot $runtimeGateRoot
    } finally {
        if (Test-Path -LiteralPath $runtimeGateRoot) { Remove-Item -LiteralPath $runtimeGateRoot -Recurse -Force }
    }
}
Write-Output "Compiled runtime staged: $stage"
