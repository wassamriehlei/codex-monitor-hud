param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\MonitorHud.Wsl.psm1') -Force
if ((Get-HudWslDistributionFromHome '\\wsl.localhost\Ubuntu\home\fixture') -ne 'Ubuntu') { throw 'wsl.localhost distribution parsing failed.' }
if ((Get-HudWslDistributionFromHome '\\wsl$\Debian\home\fixture') -ne 'Debian') { throw 'legacy wsl$ distribution parsing failed.' }
if (-not [string]::IsNullOrEmpty((Resolve-HudWslHome -Distribution '../invalid'))) { throw 'Invalid WSL distribution was accepted.' }
$distributions = @(Get-HudWslDistributions)
if ($distributions.Count -gt 0) {
    $distribution = [string]($distributions | Where-Object { $_ -match '^Ubuntu' } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($distribution)) { $distribution = [string]$distributions[0] }
    $homePath = Resolve-HudWslHome -Distribution $distribution
    if ($homePath -notmatch ('^\\\\wsl\.localhost\\' + [regex]::Escape($distribution) + '\\')) { throw 'Detected WSL home is not a distribution UNC path.' }
    if ((Get-HudWslDistributionFromHome $homePath) -ne $distribution) { throw 'Detected WSL home did not round-trip.' }
    Write-Output "WSL source helpers: OK ($distribution -> $homePath)"
} else {
    Write-Output 'WSL source helpers: OK (no installed distribution; parsing and input validation passed)'
}
