Set-StrictMode -Version Latest

function Set-HudStartupRegistration {
    param(
        [Parameter(Mandatory=$true)][bool]$Enabled,
        [Parameter(Mandatory=$true)][string]$PluginRoot,
        [string]$HudHome = '',
        [bool]$Portable = (-not [string]::IsNullOrWhiteSpace($env:CODEX_MONITOR_HUD_DATA_HOME)),
        [string]$StartupDirectory = ([Environment]::GetFolderPath('Startup'))
    )
    $ErrorActionPreference = 'Stop'
    if ([string]::IsNullOrWhiteSpace($StartupDirectory)) {
        if (-not $Enabled) { return }
        $StartupDirectory = [Environment]::GetFolderPath('Startup', 'DoNotVerify')
        if ([string]::IsNullOrWhiteSpace($StartupDirectory)) { throw 'The current user Startup folder is unavailable.' }
    }
    $shortcutPath = Join-Path $StartupDirectory 'Codex Monitor HUD.lnk'
    $marker = 'Codex Monitor HUD - Windows login startup'
    $shell = $null; $shortcut = $null
    try {
        if (-not $Enabled -and -not [IO.File]::Exists($shortcutPath)) { return }
        $shell = New-Object -ComObject WScript.Shell
        if ([IO.File]::Exists($shortcutPath)) {
            $shortcut = $shell.CreateShortcut($shortcutPath)
            if ($shortcut.Description -ne $marker) {
                if (-not $Enabled) { return }
                throw 'A different shortcut already uses the HUD startup filename.'
            }
            # Preserve the captured WSL bridge when repairing from plain Windows.
            if ([string]::IsNullOrWhiteSpace($HudHome) -and $shortcut.Arguments -match '-HudHome "([^"]+)"') { $HudHome = $Matches[1] }
        }
        if (-not $Enabled) {
            $expectedLauncher = Join-Path ([IO.Path]::GetFullPath($PluginRoot)) 'scripts\start-at-login.ps1'
            if ($shortcut.Arguments.IndexOf($expectedLauncher,[StringComparison]::OrdinalIgnoreCase) -lt 0) { return }
            Remove-Item -LiteralPath $shortcutPath -Force
            return
        }
        $launcher = Join-Path ([IO.Path]::GetFullPath($PluginRoot)) 'scripts\start-at-login.ps1'
        if (-not [IO.File]::Exists($launcher)) { throw 'The HUD login launcher is missing.' }
        if ($launcher.Contains('"') -or $HudHome.Contains('"') -or $HudHome.Contains("`r") -or $HudHome.Contains("`n")) { throw 'Startup paths contain unsupported characters.' }
        New-Item -ItemType Directory -Force -Path $StartupDirectory | Out-Null
        if ($null -eq $shortcut) { $shortcut = $shell.CreateShortcut($shortcutPath) }
        $shortcut.TargetPath = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
        $shortcut.Arguments = '-NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcher + '"'
        if (-not [string]::IsNullOrWhiteSpace($HudHome)) { $shortcut.Arguments += ' -HudHome "' + $HudHome + '"' }
        if ($Portable) { $shortcut.Arguments += ' -Portable' }
        $shortcut.WorkingDirectory = [IO.Path]::GetFullPath($PluginRoot)
        $shortcut.Description = $marker
        $shortcut.IconLocation = (Join-Path $PluginRoot 'assets\codex-monitor-hud.ico') + ',0'
        $shortcut.WindowStyle = 7
        $shortcut.Save()
    } finally {
        if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
        if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    }
}

Export-ModuleMember -Function Set-HudStartupRegistration
