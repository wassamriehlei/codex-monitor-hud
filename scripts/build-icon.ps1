param(
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\anime-mascot-source.png'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\codex-monitor-hud.ico'),
    [string]$PreviewPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\codex-monitor-hud-256.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not (Test-Path -LiteralPath $SourcePath)) { throw "Mascot source image is missing: $SourcePath" }

function New-RoundedRectanglePath {
    param([Drawing.RectangleF]$Bounds,[single]$Radius)
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $diameter = [single]($Radius * 2)
    $path.AddArc($Bounds.Left,$Bounds.Top,$diameter,$diameter,180,90)
    $path.AddArc($Bounds.Right-$diameter,$Bounds.Top,$diameter,$diameter,270,90)
    $path.AddArc($Bounds.Right-$diameter,$Bounds.Bottom-$diameter,$diameter,$diameter,0,90)
    $path.AddArc($Bounds.Left,$Bounds.Bottom-$diameter,$diameter,$diameter,90,90)
    $path.CloseFigure()
    return $path
}

function New-MascotIconPng {
    param([int]$Size,[Drawing.Bitmap]$Source)
    $bitmap = New-Object Drawing.Bitmap($Size,$Size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([Drawing.Color]::Transparent)
        $margin = [single][Math]::Max(1,$Size * 0.045)
        $bounds = New-Object Drawing.RectangleF($margin,$margin,[single]($Size-2*$margin),[single]($Size-2*$margin))
        $shape = New-RoundedRectanglePath $bounds ([single]($Size * 0.225))
        try {
            $gradient = New-Object Drawing.Drawing2D.LinearGradientBrush($bounds,[Drawing.Color]::FromArgb(255,210,225,255),[Drawing.Color]::FromArgb(255,255,205,232),42)
            try { $graphics.FillPath($gradient,$shape) } finally { $gradient.Dispose() }
            $saved = $graphics.Save()
            try {
                $graphics.SetClip($shape)
                # Cyan-haired CC0 portrait, cropped closely so the face remains
                # recognizable in Windows taskbar and tray icon sizes.
                $sourceRect = New-Object Drawing.RectangleF(1080,2040,840,840)
                $graphics.DrawImage($Source,$bounds,$sourceRect,[Drawing.GraphicsUnit]::Pixel)
            } finally { $graphics.Restore($saved) }
            $rim = New-Object Drawing.Pen([Drawing.Color]::FromArgb(205,255,255,255),[single][Math]::Max(1,$Size*0.022))
            try { $graphics.DrawPath($rim,$shape) } finally { $rim.Dispose() }
        } finally { $shape.Dispose() }
        $stream = New-Object IO.MemoryStream
        try { $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png); return $stream.ToArray() }
        finally { $stream.Dispose() }
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}

function Convert-PngToIconDib {
    param([byte[]]$PngBytes,[int]$Size)
    $input = New-Object IO.MemoryStream(,$PngBytes)
    $bitmap = [Drawing.Bitmap]::FromStream($input)
    $output = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($output)
    try {
        $xorBytes = $Size*$Size*4
        $maskStride = [int]([Math]::Ceiling($Size/32.0)*4)
        $writer.Write([uint32]40); $writer.Write([int32]$Size); $writer.Write([int32]($Size*2))
        $writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]0); $writer.Write([uint32]$xorBytes)
        $writer.Write([int32]0); $writer.Write([int32]0); $writer.Write([uint32]0); $writer.Write([uint32]0)
        for ($y=$Size-1; $y -ge 0; $y--) {
            for ($x=0; $x -lt $Size; $x++) {
                $pixel=$bitmap.GetPixel($x,$y)
                $writer.Write([byte]$pixel.B); $writer.Write([byte]$pixel.G); $writer.Write([byte]$pixel.R); $writer.Write([byte]$pixel.A)
            }
        }
        $maskRow = New-Object byte[] $maskStride
        for ($y=0; $y -lt $Size; $y++) { $writer.Write([byte[]]$maskRow) }
        $writer.Flush(); return $output.ToArray()
    } finally { $writer.Dispose(); $output.Dispose(); $bitmap.Dispose(); $input.Dispose() }
}

$source = [Drawing.Bitmap]::FromFile([IO.Path]::GetFullPath($SourcePath))
try {
    $sizes = @(16,20,24,32,40,48,64,128,256)
    $pngFrames = @(); $frames = @()
    foreach ($size in $sizes) {
        $png = New-MascotIconPng $size $source
        $pngFrames += ,$png
        $frames += ,(Convert-PngToIconDib $png $size)
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
    $stream = New-Object IO.FileStream($OutputPath,[IO.FileMode]::Create)
    $writer = New-Object IO.BinaryWriter($stream)
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
        $offset = 6 + 16*$frames.Count
        for ($i=0; $i -lt $frames.Count; $i++) {
            $sizeByte = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
            $writer.Write([byte]$sizeByte); $writer.Write([byte]$sizeByte); $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]$frames[$i].Length); $writer.Write([uint32]$offset)
            $offset += $frames[$i].Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame) }
    } finally { $writer.Dispose(); $stream.Dispose() }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PreviewPath) | Out-Null
    [IO.File]::WriteAllBytes($PreviewPath,[byte[]]$pngFrames[-1])
} finally { $source.Dispose() }

Write-Output "Mascot icon: $OutputPath ($($sizes.Count) sizes)"
