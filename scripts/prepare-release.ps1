param(
    [string]$Version = '3.4.3',
    [string]$OutputRoot = ''
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
if (Test-Path -LiteralPath $outputRoot) { throw 'Use a fresh OutputRoot to avoid stale release files.' }

$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $sourceRoot '.codex-plugin\plugin.json') | ConvertFrom-Json
if ([string]$manifest.version -ne $Version) { throw 'Release version differs from plugin manifest.' }

$portableStage = Join-Path ([IO.Path]::GetTempPath()) ('codex-monitor-hud-portable-stage-' + [Guid]::NewGuid().ToString('N'))
$portableName = "CodexMonitorHUD-Portable-$Version-windows-x64.zip"
$portablePath = Join-Path $outputRoot $portableName
$outputCreated = $false
try {
    New-Item -ItemType Directory -Force -Path $outputRoot,$portableStage | Out-Null
    $outputCreated = $true

    # Releases are Portable-only. Keep the runtime payload focused on files used
    # at run time; source projects, tests, build tools and user data stay out.
    $portableItems = @(
        '.codex-plugin','.mcp.json','CodexMonitorHUD.exe',
        'config.default.json','pricing.default.json','install-manifest.json',
        'LICENSE','README.md','README.en.md','README.zh-CN.md','CHANGELOG.md','PRIVACY.md','SECURITY.md','THIRD_PARTY_NOTICES.md',
        'src','locales','themes','assets\audio','assets\screenshots',
        'assets\codex-monitor-hud.ico','assets\codex-monitor-hud-256.png','assets\icon.svg',
        'scripts\restart.ps1','scripts\start.ps1'
    )
    foreach ($item in $portableItems) { Copy-ReleaseItem $item $portableStage }
    [IO.File]::WriteAllText((Join-Path $portableStage 'portable.marker'),"Codex Monitor HUD portable v$Version`r`n",(New-Object Text.UTF8Encoding($false)))

    foreach ($forbidden in Get-ChildItem -LiteralPath $portableStage -File -Recurse -Force | Where-Object {
        $_.Extension -in @('.cmd','.pdb','.log','.db','.sqlite','.sqlite3','.jsonl') -or $_.Name -like '.env*'
    }) { throw "Forbidden release file: $($forbidden.FullName)" }

    $portableFiles = Get-ChildItem -LiteralPath $portableStage -File -Recurse -Force | ForEach-Object {
        $_.FullName.Substring($portableStage.Length).TrimStart([char[]]@([char]92,[char]47)) -replace '\\','/'
    } | Sort-Object
    $portableFiles | Set-Content -LiteralPath (Join-Path $outputRoot 'PORTABLE_FILES.txt') -Encoding utf8

    New-ZipArchive $portableStage $portablePath
    "$(Get-Sha256Hex $portablePath)  $portableName" | Set-Content -LiteralPath (Join-Path $outputRoot 'SHA256SUMS.txt') -Encoding ascii

    $summary = [ordered]@{
        version = $Version
        channel = 'portable'
        portable_files = $portableFiles.Count
        portable_bytes = (Get-Item -LiteralPath $portablePath).Length
        stage_retained = $false
    }
    [IO.File]::WriteAllText((Join-Path $outputRoot 'release-summary.json'),($summary | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    Write-Output "Portable package: $portablePath"
    Write-Output ("Compressed size: {0:N1} MiB" -f ($summary.portable_bytes / 1MB))
    Write-Output "Checksums: $(Join-Path $outputRoot 'SHA256SUMS.txt')"
} catch {
    if ($outputCreated -and (Test-Path -LiteralPath $outputRoot)) {
        Remove-Item -LiteralPath $outputRoot -Recurse -Force
    }
    throw
} finally {
    if (Test-Path -LiteralPath $portableStage) {
        Remove-Item -LiteralPath $portableStage -Recurse -Force
    }
}
