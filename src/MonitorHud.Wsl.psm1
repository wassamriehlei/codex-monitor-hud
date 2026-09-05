Set-StrictMode -Version Latest

function Get-HudWslDistributions {
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'wsl.exe'
    $startInfo.Arguments = '--list --quiet'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.Encoding]::Unicode
    try { $process = [Diagnostics.Process]::Start($startInfo) } catch { return @() }
    try {
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        if (-not $process.WaitForExit(3000)) { $process.Kill(); return @() }
        return @($outputTask.Result -split "`r?`n" | ForEach-Object { $_.Replace([string][char]0,'').Trim() } | Where-Object { $_ -and $_ -notmatch '^(docker-desktop|docker-desktop-data)$' } | Select-Object -Unique)
    } finally { $process.Dispose() }
}

function Resolve-HudWslHome {
    param([Parameter(Mandatory=$true)][string]$Distribution)
    if ($Distribution -notmatch '^[A-Za-z0-9._-]{1,128}$') { return '' }
    try {
        $linuxHome = [string](& wsl.exe -d $Distribution -- sh -lc 'printf "%s" "$HOME"' 2>$null)
        $linuxHome = $linuxHome.Replace([string][char]0,'').Trim()
        if ($LASTEXITCODE -ne 0 -or $linuxHome -notmatch '^/(?:[^/\x00]+/)*[^/\x00]+$') { return '' }
        return ('\\wsl.localhost\{0}{1}' -f $Distribution,($linuxHome -replace '/','\'))
    } catch { return '' }
}

function Get-HudWslDistributionFromHome {
    param([string]$Home)
    if ([string]$Home -match '^\\\\(?:wsl\.localhost|wsl\$)\\([^\\]+)\\') { return [string]$Matches[1] }
    return ''
}

Export-ModuleMember -Function Get-HudWslDistributions,Resolve-HudWslHome,Get-HudWslDistributionFromHome
