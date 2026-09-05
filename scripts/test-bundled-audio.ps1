param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$root = Split-Path -Parent $PSScriptRoot
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'config.default.json') | ConvertFrom-Json
if ([IO.Path]::IsPathRooted($config.completionSoundFile)) { throw 'Bundled audio must not reference a machine-specific path.' }
$audioPath = Join-Path $root $config.completionSoundFile
if (-not [IO.File]::Exists($audioPath)) { throw 'Default audio asset is missing.' }
$media = New-Object Windows.Media.MediaPlayer
$media.Volume = 0
$frame = New-Object Windows.Threading.DispatcherFrame
$result = [pscustomobject]@{Opened=$false;Error=''}
$media.Add_MediaOpened({ $result.Opened=$true; $frame.Continue=$false })
$media.Add_MediaFailed({ $result.Error=$_.ErrorException.Message; $frame.Continue=$false })
$timeout = New-Object Windows.Threading.DispatcherTimer
$timeout.Interval = [TimeSpan]::FromSeconds(10)
$timeout.Add_Tick({ $frame.Continue=$false })
try {
    # Decode with the same Windows backend as the HUD, without playing sound.
    $media.Open((New-Object Uri($audioPath,[UriKind]::Absolute)))
    $timeout.Start()
    [Windows.Threading.Dispatcher]::PushFrame($frame)
    if (-not $result.Opened -or $result.Error -or -not $media.NaturalDuration.HasTimeSpan) { throw ('Bundled audio decode failed: ' + $result.Error) }
    Write-Output ('Bundled completion audio: OK ({0:0.00}s, muted decode)' -f $media.NaturalDuration.TimeSpan.TotalSeconds)
} finally { $timeout.Stop(); $media.Close() }
