param()

# Synthetic, off-screen WPF checks. Never loads user settings or sessions.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$root = Split-Path -Parent $PSScriptRoot

# Exercise the actual theme functions without executing the runtime entry point.
$syntax = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src\CodexMonitorHUD.ps1'), [ref]$null, [ref]$null)
foreach ($functionName in @('Assert-HudThemeDefinition','Apply-HudThemeDefinition','Update-HudFloatingSurface','Update-HudIdleIndicatorMode')) {
    $definition = $syntax.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $false)
    if ($null -eq $definition) { throw "Theme function missing: $functionName" }
    . ([scriptblock]::Create($definition.Extent.Text))
}
$paths = [pscustomobject]@{ DefaultConfigPath = Join-Path $root 'config.default.json' }
foreach ($themeFile in Get-ChildItem -LiteralPath (Join-Path $root 'themes') -Filter '*.json') {
    $theme = Get-Content -Raw -Encoding UTF8 -LiteralPath $themeFile.FullName | ConvertFrom-Json
    [void](Assert-HudThemeDefinition $theme $false)
    $config = Get-Content -Raw -Encoding UTF8 -LiteralPath $paths.DefaultConfigPath | ConvertFrom-Json
    $config.hudWidth = 547
    $config.surfaceMode = 'ball'
    $config.completionSound = 'file'
    $config.completionSoundFile = 'C:\Synthetic\chime.wav'
    $config.multiTask.listFields.directory = $false
    $config.sessionSources.deepSeekCli = $false
    Apply-HudThemeDefinition $theme
    if ($config.surfaceMode -ne 'ball' -or $config.hudWidth -ne 547 -or $config.completionSoundFile -ne 'C:\Synthetic\chime.wav' -or $config.completionSound -ne 'file' -or $config.multiTask.listFields.directory -or $config.sessionSources.deepSeekCli -or $config.agentNotifications.enabled) { throw "Theme changed non-visual preferences: $($theme.id)" }
    if ($null -eq $theme.settings.PSObject.Properties['themeStyle'] -and ($config.themeStyle.surface -ne 'solid' -or $config.themeStyle.gradientStart -ne $theme.settings.background)) { throw "Legacy theme inherited the Liquid gradient: $($theme.id)" }
    if ($theme.id -eq 'ios26-liquid' -and ($config.themeStyle.surface -ne 'gradient' -or $config.themeStyle.backdrop -ne 'none')) { throw 'Liquid preset surface is invalid.' }
}
Write-Output 'Theme application: OK (all bundled themes; preserved sound, width, fields, sources, permissions)'
foreach ($retiredMode in @('blur','acrylic')) {
    $legacyTheme = [pscustomobject]@{ id='legacy-glass'; names=@{ en='Legacy glass' }; settings=[pscustomobject]@{ themeStyle=[pscustomobject]@{ backdrop=$retiredMode } } }
    [void](Assert-HudThemeDefinition $legacyTheme $false)
    Apply-HudThemeDefinition $legacyTheme
    if ($config.themeStyle.backdrop -ne 'none') { throw "An imported theme re-enabled retired glass: $retiredMode" }
}
Write-Output 'Retired glass theme compatibility: OK'

function Read-TestWindow([string]$Name) {
    [Windows.Markup.XamlReader]::Parse((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root "src\$Name")))
}
function Arrange-TestWindow($Window, [double]$Width, [double]$Height) {
    $size = New-Object Windows.Size($Width,$Height)
    $Window.Content.Measure($size)
    $Window.Content.Arrange((New-Object Windows.Rect(0,0,$Width,$Height)))
    $Window.Content.UpdateLayout()
}
function Assert-InBounds($Element, $Root, [double]$Width, [double]$Height) {
    if ($Element.ActualWidth -le 0 -or $Element.ActualHeight -le 0) { throw "Zero-sized control: $($Element.Name)" }
    $bounds = $Element.TransformToAncestor($Root).TransformBounds((New-Object Windows.Rect(0,0,$Element.ActualWidth,$Element.ActualHeight)))
    if ($bounds.Left -lt 0 -or $bounds.Top -lt 0 -or $bounds.Right -gt ($Width + 1) -or $bounds.Bottom -gt ($Height + 1)) { throw "Clipped control: $($Element.Name) $bounds" }
}

$settings = Read-TestWindow 'SettingsWindow.xaml'
try {
    $tabs = $settings.FindName('SettingsTabs')
    foreach ($size in @(@(760,700),@(900,820),@(1200,900))) {
        foreach ($tab in $tabs.Items) {
            $tabs.SelectedItem = $tab
            Arrange-TestWindow $settings $size[0] $size[1]
            foreach ($header in $tabs.Items) { Assert-InBounds $header $settings.Content $size[0] $size[1] }
            foreach ($name in @('CloseSettingsButton','ResetButton','SaveButton')) { Assert-InBounds ($settings.FindName($name)) $settings.Content $size[0] $size[1] }
            $selectedHost = $tabs.Template.FindName('PART_SelectedContentHost',$tabs)
            if ($null -eq $selectedHost -or $selectedHost.ActualHeight -lt 300) { throw 'Segmented navigation lost its content host.' }
        }
    }
    $tabs.SelectedItem = $settings.FindName('SourcesTab')
    Arrange-TestWindow $settings 760 700
    $check = $settings.FindName('SourceDesktopCheck')
    $check.IsChecked = $false
    $check.ApplyTemplate() | Out-Null
    $thumb = $check.Template.FindName('SwitchThumb',$check)
    if ($null -eq $thumb -or $thumb.HorizontalAlignment -ne 'Left') { throw 'Unchecked switch thumb is invalid.' }
    $check.IsChecked = $true
    if ($thumb.HorizontalAlignment -ne 'Right') { throw 'Checked switch thumb did not update.' }
    $check.IsEnabled = $false
    if ($check.Template.FindName('CheckRoot',$check).Opacity -ge 1) { throw 'Disabled switch lost its visual state.' }

    $tabs.SelectedItem = $settings.FindName('AppearanceTab')
    Arrange-TestWindow $settings 760 700
    foreach ($name in @('HudWidthSlider','FontSizeSlider','RadiusSlider','OpacitySlider')) {
        $slider = $settings.FindName($name)
        $slider.Value = ($slider.Minimum + $slider.Maximum) / 2
        $track = $slider.Template.FindName('PART_Track',$slider)
        if ($null -eq $track -or [Math]::Abs($track.Value - $slider.Value) -gt 0.001) { throw "Slider track/value binding failed: $name" }
    }
    $colorInput = $settings.FindName('BackgroundText')
    $colorInput.ApplyTemplate() | Out-Null
    if ($null -eq $colorInput.Template.FindName('PART_ContentHost',$colorInput)) { throw 'Rounded input lost its editing host.' }
    $scroll = $settings.FindName('AppearanceScrollViewer')
    $scroll.ScrollToEnd()
    Arrange-TestWindow $settings 760 700
    if ($scroll.VerticalOffset -le 0) { throw 'Appearance settings no longer scroll.' }
} finally { $settings.Close() }

foreach ($name in @('HudWindow.xaml','TaskBubbleWindow.xaml')) {
    $window = Read-TestWindow $name
    try {
        $rim = $window.FindName('LiquidRim')
        if ($null -eq $rim -or $rim.IsHitTestVisible) { throw 'The optical rim must be non-interactive.' }
        $shellName = if ($name -eq 'HudWindow.xaml') { 'HudShell' } else { 'TaskBubbleShell' }
        $shell = $window.FindName($shellName)
        foreach ($radius in @(8,28,36)) {
            $shell.CornerRadius = New-Object Windows.CornerRadius($radius)
            Arrange-TestWindow $window 547 180
            if ($rim.CornerRadius.TopLeft -ne $radius) { throw 'The optical rim does not follow the configured radius.' }
        }
    } finally { $window.Close() }
}
$picker = Read-TestWindow 'ColorPickerWindow.xaml'
try {
    Arrange-TestWindow $picker 420 580
    foreach ($name in @('ColorPickerClose','PickerCancelButton','PickerApplyButton','PickerHexText')) { Assert-InBounds ($picker.FindName($name)) $picker.Content 420 580 }
} finally { $picker.Close() }
Write-Output 'Liquid design: OK (all tabs at 760/900/1200 DIP, switches, sliders, input, scrolling, rims, color picker)'

# Actual legacy projection functions with synthetic states and off-screen XAML.
function Get-HudUserTaskStates { $script:fixtureStates }
function Get-TaskStatus($State) { $State.Status }
function Test-HudQuietLayoutShowsTasks { $false }
function Test-HudStateQuiet($State,$Keep) { $true }
function Set-HudIndicatorCollapsed($Collapsed) { $script:isMainIndicatorCollapsed = $Collapsed }
function Position-TaskBubbles { }
function Move-HudToConfiguredPosition { }
function Write-HudDebug($Message) { }
function New-HudRoleBrush { [Windows.Media.Brushes]::Black }
function Apply-HudAppearance {
    $hudShell.Width = $config.hudWidth
    $hudShell.Padding = New-Object Windows.Thickness(14,10,14,10)
    $hudShell.CornerRadius = New-Object Windows.CornerRadius($config.cornerRadius)
}
$hud = Read-TestWindow 'HudWindow.xaml'
try {
    $hudShell = $hud.FindName('HudShell')
    $hudContentPanel = $hud.FindName('HudContentPanel')
    $quietIndicatorPanel = $hud.FindName('QuietIndicatorPanel')
    $floatingBallPanel = $hud.FindName('FloatingBallPanel')
    $floatingBallCount = $hud.FindName('FloatingBallCount')
    if ($floatingBallPanel.Children.Count -ne 1 -or $floatingBallPanel.Children[0] -ne $floatingBallCount) { throw 'Floating ball must contain only its count.' }
    $config = Get-Content -Raw -Encoding UTF8 -LiteralPath $paths.DefaultConfigPath | ConvertFrom-Json
    $config.surfaceMode = 'ball'
    $settingsLocale = @{surfaceBallHint='Synthetic hover hint'}
    $splitWindows = @{}
    $ballModeActive = $false
    $isFloatingBallExpanded = $false
    $wasBallCollapsed = $false
    $isMainIndicatorCollapsed = $false
    $isHudDragging = $false
    $ballCollapseTimer = $null
    foreach ($statuses in @(@(),@('completed','idle','error','paused'),@('active','listening','completed','idle','error'),@('active','active','listening'))) {
        $fixtureStates = @($statuses | ForEach-Object { [pscustomobject]@{Status=$_} })
        Update-HudIdleIndicatorMode
        $expected = @($statuses | Where-Object { $_ -in @('active','listening') }).Count
        if ($floatingBallCount.Text -cne [string]$expected) { throw "Incorrect active task count: $($floatingBallCount.Text), expected $expected" }
        if ($hudShell.Width -ne 48 -or $hudShell.Height -ne 48 -or $hudShell.CornerRadius.TopLeft -ne 24 -or $hudContentPanel.Visibility -ne 'Collapsed') { throw 'Collapsed ball geometry/content failed.' }
    }
    $isFloatingBallExpanded = $true
    Update-HudIdleIndicatorMode
    if ($floatingBallPanel.Visibility -ne 'Collapsed' -or $hudContentPanel.Visibility -ne 'Visible' -or $hudShell.Width -ne $config.hudWidth -or -not [double]::IsNaN($hudShell.Height)) { throw 'Hover expansion failed to restore normal content.' }
    $isFloatingBallExpanded = $false
    Update-HudIdleIndicatorMode
    $config.mousePassthrough = $true
    $config.behavior.idleIndicator.enabled = $false
    Update-HudIdleIndicatorMode
    if ($floatingBallPanel.Visibility -ne 'Collapsed' -or $hudContentPanel.Visibility -ne 'Visible') { throw 'Click-through trapped the HUD in ball mode.' }
    $config.mousePassthrough = $false
    Update-HudIdleIndicatorMode
    $config.surfaceMode = 'window'
    Update-HudIdleIndicatorMode
    if ($floatingBallPanel.Visibility -ne 'Collapsed' -or $hudContentPanel.Visibility -ne 'Visible') { throw 'Switching to window failed to restore content.' }
} finally { $hud.Close() }
Write-Output 'Floating ball: OK (count-only, zero/mixed/active states, expand, collapse, click-through, window restore)'
