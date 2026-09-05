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
    if ($null -eq $command) { throw 'The .NET 10 SDK is required to build v3.4.1. The repository-private SDK was not found and dotnet is not on PATH.' }
    $command.Source
}
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

# Public releases stay small and use the system-wide Microsoft .NET 10 Desktop
# Runtime x64 instead of carrying a duplicate private runtime tree.
$publishStage = Join-Path $env:TEMP ('codex-monitor-hud-publish-' + [Guid]::NewGuid().ToString('N'))
$healthRoot = Join-Path $env:TEMP ('codex-monitor-hud-health-' + [Guid]::NewGuid().ToString('N'))
$appProject = Join-Path $root 'src-dotnet\CodexMonitorHud.App\CodexMonitorHud.App.csproj'
New-Item -ItemType Directory -Force -Path $publishStage,$healthRoot | Out-Null
try {
    & $dotnet publish $appProject -c $Configuration -r win-x64 --self-contained false -o $publishStage `
        -p:UseAppHost=true `
        -p:PublishSingleFile=true `
        -p:DebugType=None `
        -p:DebugSymbols=false
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }
    $publishedExe = Join-Path $publishStage 'CodexMonitorHud.exe'
    if (-not (Test-Path -LiteralPath $publishedExe)) { throw 'Single-file AppHost was not produced.' }
    Copy-Item -LiteralPath $publishedExe -Destination (Join-Path $root 'CodexMonitorHUD.exe') -Force
    $obsoleteSettingsAlias = Join-Path $root 'CodexMonitorHUD-Settings.exe'
    if (Test-Path -LiteralPath $obsoleteSettingsAlias) { Remove-Item -LiteralPath $obsoleteSettingsAlias -Force }
    $obsoleteRuntime = Join-Path $root 'runtime'
    if (Test-Path -LiteralPath $obsoleteRuntime) { Remove-Item -LiteralPath $obsoleteRuntime -Recurse -Force }

    $healthPath = Join-Path $healthRoot 'health-check.json'
    $healthProcess = Start-Process -FilePath (Join-Path $root 'CodexMonitorHUD.exe') -ArgumentList @('--plugin-root',('"' + $root + '"'),'--health-check',('"' + $healthPath + '"')) -PassThru -Wait
    if ($healthProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $healthPath)) { throw 'Framework-dependent executable health check failed. Install Microsoft .NET 10 Desktop Runtime x64.' }
    $health = Get-Content -Raw -Encoding UTF8 -LiteralPath $healthPath | ConvertFrom-Json
    if ([string]$health.version -ne '3.4.1' -or [string]$health.config -ne 'ok' -or [string]$health.xaml -ne 'ok' -or [string]$health.parser -ne 'ok') {
        throw ('Compiled runtime health check returned an invalid result: ' + ($health | ConvertTo-Json -Compress))
    }
} finally {
    if (Test-Path -LiteralPath $publishStage) { Remove-Item -LiteralPath $publishStage -Recurse -Force }
    if (Test-Path -LiteralPath $healthRoot) { Remove-Item -LiteralPath $healthRoot -Recurse -Force }
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
Write-Output "Framework-dependent executable built: $(Join-Path $root 'CodexMonitorHUD.exe')"
