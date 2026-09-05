param(
    [string]$Version = '3.3.1',
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
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputRoot = Join-Path $sourceRoot ("artifacts\\release-v{0}-{1}" -f $Version,$stamp)
}
$outputRoot = [IO.Path]::GetFullPath($OutputRoot)
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $sourceRoot 'artifacts'))
if (-not $outputRoot.StartsWith($artifactRoot.TrimEnd([char]92) + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must stay under the repository artifacts directory.'
}

$stageRoot = Join-Path $outputRoot 'stage'
$archiveName = 'CodexMonitorHUD-windows-x64.zip'
$archivePath = Join-Path $outputRoot $archiveName
$excludedRootNames = @('.git','.agents','.codex','artifacts','.test-output','private','portable-data','node_modules','sessions','logs','archive','Microsoft')
$excludedDirectoryNames = @('bin','obj')
$excludedFileNames = @('.DS_Store','Thumbs.db','settings.json','AGENTS.md','WORKSPACE_STATE.md')
$excludedExtensions = @('.log','.zip','.db','.sqlite','.sqlite3','.jsonl')
$excludedRelativePaths = @('docs/MAINTENANCE_WORKFLOW.md','docs/MACOS_PREVIEW_TESTING.md','scripts/prepare-delivery.ps1')

if (Test-Path -LiteralPath $stageRoot) { throw 'Use a fresh OutputRoot to avoid stale release files.' }
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $sourceRoot '.codex-plugin\plugin.json') | ConvertFrom-Json
if ([string]$manifest.version -ne $Version) { throw 'Release version differs from plugin manifest.' }
foreach ($required in @('runtime\win-x64\dotnet\dotnet.exe','runtime\win-x64\app\CodexMonitorHud.dll','assets\audio\default-completion.mp3','Start-Portable.cmd','Settings-Portable.cmd')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $required))) { throw "Missing release payload: $required" }
}
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
$files = Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | Where-Object {
    $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@([char]92,[char]47))
    $parts = $relative -split '[\\/]'
    $rootName = $parts[0]
    $rootName -notin $excludedRootNames -and
    $rootName -notlike '.test-output*' -and
    @($parts | Where-Object { $_ -in $excludedDirectoryNames }).Count -eq 0 -and
    ($relative -replace '\\','/') -notin $excludedRelativePaths -and
    $_.Name -notin $excludedFileNames -and
    $_.Extension.ToLowerInvariant() -notin $excludedExtensions -and
    $_.Name -notlike '.env*' -and
    $_.Name -notlike '*.user.json'
} | Sort-Object FullName

if ($files.Count -eq 0) { throw 'No public package files were found.' }
foreach ($file in $files) {
    $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@([char]92,[char]47))
    $destination = Join-Path $stageRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
}

$packageFiles = Get-ChildItem -LiteralPath $stageRoot -File -Recurse -Force | ForEach-Object {
    $_.FullName.Substring($stageRoot.Length).TrimStart([char[]]@([char]92,[char]47)) -replace '\\','/'
} | Sort-Object
$packageFiles | Set-Content -LiteralPath (Join-Path $outputRoot 'PACKAGE_FILES.txt') -Encoding utf8
Add-Type -AssemblyName System.IO.Compression.FileSystem
# ZipFile includes dotfiles required by Codex (.codex-plugin and .mcp.json).
[IO.Compression.ZipFile]::CreateFromDirectory($stageRoot, $archivePath, [IO.Compression.CompressionLevel]::Optimal, $false)
$portableName = "CodexMonitorHUD-Portable-$Version-windows-x64.zip"
Copy-Item -LiteralPath $archivePath -Destination (Join-Path $outputRoot $portableName)
if (-not $SkipInstaller) {
    if ([string]::IsNullOrWhiteSpace($InnoCompiler)) { $InnoCompiler = Join-Path $sourceRoot 'private\toolchain\innosetup\ISCC.exe' }
    if (-not (Test-Path -LiteralPath $InnoCompiler)) { throw 'Inno Setup 6 compiler is required for the EXE. Use -InnoCompiler or explicitly choose -SkipInstaller.' }
    & $InnoCompiler '/Qp' "/DPackageVersion=$Version" "/DStageRoot=$stageRoot" "/DReleaseRoot=$outputRoot" (Join-Path $sourceRoot 'scripts\installer.iss')
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed: $LASTEXITCODE" }
}
$hash = Get-Sha256Hex $archivePath
$assetNames = @($archiveName,$portableName)
if (-not $SkipInstaller) { $assetNames += "CodexMonitorHUD-Setup-$Version-windows-x64.exe" }
$assetNames | ForEach-Object { "$(Get-Sha256Hex (Join-Path $outputRoot $_))  $_" } | Set-Content -LiteralPath (Join-Path $outputRoot 'SHA256SUMS.txt') -Encoding ascii

$upload = @"
# Release upload fields

Archive: $archiveName

SHA-256:

~~~text
$hash  $archiveName
~~~

Package files: $($packageFiles.Count)

Upload the archive and SHA256SUMS.txt to the normal v${Version} GitHub Release after the main commit is pushed. Write the user-facing body from the current CHANGELOG.md; do not add a root-level Release draft file.
"@
Set-Content -LiteralPath (Join-Path $outputRoot 'RELEASE_UPLOAD.md') -Value $upload -Encoding utf8

Write-Output "Release package: $archivePath"
Write-Output "SHA-256: $hash"
Write-Output "Package files: $($packageFiles.Count)"
Write-Output "Upload fields: $(Join-Path $outputRoot 'RELEASE_UPLOAD.md')"
