param([Parameter(Mandatory=$true)][string]$ReleaseRoot)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = [string](Get-Content -Raw -LiteralPath (Join-Path $root '.codex-plugin\plugin.json') | ConvertFrom-Json).version
$fixture = Join-Path $root ('.test-output\release-package-' + [Guid]::NewGuid().ToString('N'))
$extract = Join-Path $fixture 'portable extracted'
New-Item -ItemType Directory -Force -Path $fixture | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Get-ReleaseHash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path); $hash = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $hash.Dispose() }
}
$checksums = Get-Content -LiteralPath (Join-Path $ReleaseRoot 'SHA256SUMS.txt')
if ($checksums.Count -ne 3) { throw 'Expected EXE, portable ZIP and repository ZIP checksums.' }
foreach ($line in $checksums) {
    if ($line -notmatch '^([a-f0-9]{64})  ([A-Za-z0-9.-]+)$') { throw 'Invalid checksum entry.' }
    if ((Get-ReleaseHash (Join-Path $ReleaseRoot $Matches[2])) -ne $Matches[1]) { throw 'Release checksum mismatch.' }
}
$repositoryArchive = [IO.Compression.ZipFile]::OpenRead((Join-Path $ReleaseRoot 'CodexMonitorHUD-windows-x64.zip'))
try {
    $repositoryNames = @($repositoryArchive.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
    foreach ($required in @('CodexMonitorHUD.exe','CodexMonitorHUD-Settings.exe','install-manifest.json','scripts/install-windows-from-repository.ps1','scripts/install.ps1')) {
        if ($required -notin $repositoryNames) { throw "Missing repository package entry: $required" }
    }
    if (@($repositoryNames | Where-Object { $_ -match '\.cmd$' }).Count -ne 0) { throw 'Repository package still contains CMD launchers.' }
} finally { $repositoryArchive.Dispose() }
$archive = Join-Path $ReleaseRoot "CodexMonitorHUD-Portable-$version-windows-x64.zip"
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
    foreach ($required in @('.codex-plugin/plugin.json','.mcp.json','CodexMonitorHUD.exe','CodexMonitorHUD-Settings.exe','portable.marker','src/CodexMonitorHUD.ps1','scripts/restart.ps1','runtime/win-x64/dotnet/dotnet.exe','assets/audio/default-completion.mp3')) {
        if ($required -notin $names) { throw "Missing package entry: $required" }
    }
    if (@($names | Where-Object { $_ -match '\.cmd$' }).Count -ne 0) { throw 'Portable package still contains CMD launchers.' }
    foreach ($name in $names) {
        if ($name -match '(^|/)(\.git|private|portable-data|\.test-output[^/]*|node_modules|bin|obj|\.agents)(/|$)|(^|/)settings\.json$|\.(jsonl|db|sqlite3?|log)$|(^|/)\.env') { throw "Private/build data in package: $name" }
        if ($name -match '(^|/)\.\.(/|$)|^[/\\]|^[A-Za-z]:') { throw 'Unsafe archive path.' }
    }
} finally { $zip.Dispose() }
[IO.Compression.ZipFile]::ExtractToDirectory($archive,$extract)
$manifest = Get-Content -Raw -LiteralPath (Join-Path $extract '.codex-plugin\plugin.json') | ConvertFrom-Json
if ($manifest.version -ne $version) { throw 'Archive manifest version mismatch.' }
$exe = Join-Path $ReleaseRoot "CodexMonitorHUD-Setup-$version-windows-x64.exe"
$exeInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
if (-not $exeInfo.ProductVersion.StartsWith($version)) { throw 'EXE product version mismatch.' }
$state = Join-Path $extract 'portable-data\CodexMonitorHUD'
New-Item -ItemType Directory -Force -Path $state | Out-Null
$productionSettings = Join-Path $env:LOCALAPPDATA 'CodexMonitorHUD\settings.json'
$before = if (Test-Path -LiteralPath $productionSettings) { Get-ReleaseHash $productionSettings } else { '' }
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = Join-Path $extract 'CodexMonitorHUD-Settings.exe'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.Arguments = '--plugin-root "' + $extract + '"'
$info.EnvironmentVariables.Remove('CODEX_MONITOR_HUD_TEST_HOME')
$info.EnvironmentVariables.Remove('CODEX_MONITOR_HUD_TEST_LOCALAPPDATA')
$info.EnvironmentVariables['CODEX_MONITOR_HUD_HOME'] = Join-Path $fixture 'synthetic-home'
$process = [Diagnostics.Process]::Start($info)
try {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath (Join-Path $state 'hud.heartbeat')) -and $timer.Elapsed.TotalSeconds -lt 20 -and -not $process.HasExited) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath (Join-Path $state 'hud.heartbeat'))) { throw 'Extracted portable HUD has no heartbeat.' }
    Start-Sleep -Seconds 6
    $hosts = @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like ('*' + $extract + '*') -and $_.CommandLine -notlike '*Get-CimInstance*' })
    $compiled = @($hosts | Where-Object { $_.Name -in @('CodexMonitorHUD.exe','CodexMonitorHUD-Settings.exe') })
    $settings = @($hosts | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*-SettingsHost*' -and $_.CommandLine -like '*-InstanceId*portable-*' })
    if ($compiled.Count -ne 1 -or $settings.Count -ne 1) { throw 'Extracted portable host/settings instance routing failed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $state 'settings.json'))) { throw 'Portable configuration was not created beside the launcher.' }
    $after = if (Test-Path -LiteralPath $productionSettings) { Get-ReleaseHash $productionSettings } else { '' }
    if ($before -ne $after) { throw 'Portable launch changed installed settings.' }
    Write-Output "Release payload: OK ($($names.Count) entries; hashes, root EXEs, no CMD launchers, bundled runtime/audio, portable isolation, live HUD and Settings)"
} finally {
    foreach ($signal in @('manual-exit.signal','exit.signal','settings-host-exit.signal')) { [IO.File]::WriteAllText((Join-Path $state $signal),'test shutdown') }
    $process.Dispose()
    foreach ($entry in @(Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('dotnet.exe','powershell.exe') -and $_.CommandLine -like ('*' + $extract + '*') -and $_.CommandLine -notlike '*Get-CimInstance*' })) {
        $hostProcess = Get-Process -Id $entry.ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $hostProcess) { try { if (-not $hostProcess.WaitForExit(10000)) { $hostProcess.Kill(); throw 'Portable test host ignored shutdown.' } } finally { $hostProcess.Dispose() } }
    }
}
