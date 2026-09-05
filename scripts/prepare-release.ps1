param(
    [string]$Version = '3.4.0',
    [string]$OutputRoot = '',
    [string]$InnoCompiler = '',
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}

function Copy-ReleaseItem {
    param([string]$RelativePath,[string]$DestinationRoot)
    $source = Join-Path $sourceRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing release payload: $RelativePath" }
    $destination = Join-Path $DestinationRoot $RelativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
}

function New-ZipArchive {
    param([string]$Source,[string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $levelNames = [Enum]::GetNames([IO.Compression.CompressionLevel])
    $compressionLevel = if ($levelNames -contains 'SmallestSize') {
        [IO.Compression.CompressionLevel]::SmallestSize
    } else {
        # Windows PowerShell 5.1 runs on .NET Framework, whose strongest ZIP
        # setting is named Optimal. PowerShell 7/.NET uses SmallestSize.
        [IO.Compression.CompressionLevel]::Optimal
    }
    [IO.Compression.ZipFile]::CreateFromDirectory($Source,$Destination,$compressionLevel,$false)
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $sourceRoot ("artifacts\release-v{0}-{1}" -f $Version,(Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$outputRoot = [IO.Path]::GetFullPath($OutputRoot)
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $sourceRoot 'artifacts'))
if (-not $outputRoot.StartsWith($artifactRoot.TrimEnd([char]92) + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must stay under the repository artifacts directory.'
}

$repositoryStage = Join-Path $outputRoot 'stage-repository'
$portableStage = Join-Path $outputRoot 'stage-portable'
if (Test-Path -LiteralPath $outputRoot) { throw 'Use a fresh OutputRoot to avoid stale release files.' }
New-Item -ItemType Directory -Force -Path $repositoryStage,$portableStage | Out-Null

$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $sourceRoot '.codex-plugin\plugin.json') | ConvertFrom-Json
if ([string]$manifest.version -ne $Version) { throw 'Release version differs from plugin manifest.' }

# The repository/installer payload contains only runtime and installation files.
# Source projects, tests, screenshots, build toolchains and generated artifacts
# remain available from GitHub and no longer inflate end-user downloads.
$repositoryItems = @(
    '.codex-plugin','.mcp.json','CodexMonitorHUD.exe','CodexMonitorHUD-Settings.exe',
    'config.default.json','pricing.default.json','install-manifest.json',
    'LICENSE','README.md','README.zh-CN.md','CHANGELOG.md','PRIVACY.md','SECURITY.md','THIRD_PARTY_NOTICES.md',
    'runtime','src','locales','themes','assets\audio','assets\screenshots','assets\codex-monitor-hud.ico','assets\codex-monitor-hud-256.png','assets\icon.svg',
    'scripts\create-shortcuts.ps1','scripts\install-exe.ps1','scripts\install.ps1','scripts\install-windows-from-repository.ps1','scripts\open-settings.ps1',
    'scripts\restart.ps1','scripts\start.ps1','scripts\start-at-login.ps1','scripts\uninstall.ps1','scripts\update-marketplace.mjs'
)
foreach ($item in $repositoryItems) { Copy-ReleaseItem $item $repositoryStage }

# Portable mode is identified by a marker, keeps state beside the executable,
# and uses the same EXE for normal and Settings aliases. There are no CMD files.
$portableItems = @(
    '.codex-plugin','.mcp.json','CodexMonitorHUD.exe','CodexMonitorHUD-Settings.exe',
    'config.default.json','pricing.default.json','LICENSE','README.md','README.zh-CN.md','THIRD_PARTY_NOTICES.md',
    'runtime','src','locales','themes','assets\audio','assets\screenshots','assets\codex-monitor-hud.ico','assets\codex-monitor-hud-256.png','assets\icon.svg',
    'scripts\restart.ps1','scripts\start.ps1'
)
foreach ($item in $portableItems) { Copy-ReleaseItem $item $portableStage }
[IO.File]::WriteAllText((Join-Path $portableStage 'portable.marker'),"Codex Monitor HUD portable v$Version`r`n",(New-Object Text.UTF8Encoding($false)))

foreach ($stage in @($repositoryStage,$portableStage)) {
    foreach ($forbidden in Get-ChildItem -LiteralPath $stage -File -Recurse -Force | Where-Object {
        $_.Extension -in @('.cmd','.pdb','.log','.db','.sqlite','.sqlite3','.jsonl') -or $_.Name -like '.env*'
    }) { throw "Forbidden release file: $($forbidden.FullName)" }
}

$archiveName = 'CodexMonitorHUD-windows-x64.zip'
$portableName = "CodexMonitorHUD-Portable-$Version-windows-x64.zip"
$archivePath = Join-Path $outputRoot $archiveName
$portablePath = Join-Path $outputRoot $portableName
New-ZipArchive $repositoryStage $archivePath
New-ZipArchive $portableStage $portablePath

$packageFiles = Get-ChildItem -LiteralPath $repositoryStage -File -Recurse -Force | ForEach-Object {
    $_.FullName.Substring($repositoryStage.Length).TrimStart([char[]]@([char]92,[char]47)) -replace '\\','/'
} | Sort-Object
$portableFiles = Get-ChildItem -LiteralPath $portableStage -File -Recurse -Force | ForEach-Object {
    $_.FullName.Substring($portableStage.Length).TrimStart([char[]]@([char]92,[char]47)) -replace '\\','/'
} | Sort-Object
$packageFiles | Set-Content -LiteralPath (Join-Path $outputRoot 'PACKAGE_FILES.txt') -Encoding utf8
$portableFiles | Set-Content -LiteralPath (Join-Path $outputRoot 'PORTABLE_FILES.txt') -Encoding utf8

if (-not $SkipInstaller) {
    if ([string]::IsNullOrWhiteSpace($InnoCompiler)) { $InnoCompiler = Join-Path $sourceRoot 'private\toolchain\innosetup\ISCC.exe' }
    if (-not (Test-Path -LiteralPath $InnoCompiler)) { throw 'Inno Setup 6 compiler is required for the EXE. Use -InnoCompiler or explicitly choose -SkipInstaller.' }
    & $InnoCompiler '/Qp' "/DPackageVersion=$Version" "/DStageRoot=$repositoryStage" "/DReleaseRoot=$outputRoot" (Join-Path $sourceRoot 'scripts\installer.iss')
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed: $LASTEXITCODE" }
}

$assetNames = @($archiveName,$portableName)
if (-not $SkipInstaller) { $assetNames += "CodexMonitorHUD-Setup-$Version-windows-x64.exe" }
$assetNames | ForEach-Object { "$(Get-Sha256Hex (Join-Path $outputRoot $_))  $_" } | Set-Content -LiteralPath (Join-Path $outputRoot 'SHA256SUMS.txt') -Encoding ascii

$summary = [ordered]@{
    version = $Version
    repository_files = $packageFiles.Count
    portable_files = $portableFiles.Count
    repository_bytes = (Get-Item -LiteralPath $archivePath).Length
    portable_bytes = (Get-Item -LiteralPath $portablePath).Length
}
[IO.File]::WriteAllText((Join-Path $outputRoot 'release-summary.json'),($summary | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
Write-Output "Repository package: $archivePath"
Write-Output "Portable package: $portablePath"
Write-Output ("Compressed sizes: repository {0:N1} MiB; portable {1:N1} MiB" -f ($summary.repository_bytes / 1MB),($summary.portable_bytes / 1MB))
Write-Output "Checksums: $(Join-Path $outputRoot 'SHA256SUMS.txt')"
