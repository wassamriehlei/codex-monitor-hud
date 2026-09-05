param()

# Synthetic, off-screen WPF checks. Never loads user settings or sessions.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$root = Split-Path -Parent $PSScriptRoot

# Exercise the actual theme functions without executing the runtime entry point.
$syntax = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src\CodexMonitorHUD.ps1'), [ref]$null, [ref]$null)
foreach ($functionName in @('Assert-HudThemeDefinition','Apply-HudThemeDefinition','Update-HudFloatingSurface','Update-HudIdleIndicatorMode','Start-HudSurfaceMotion','Stop-HudSurfaceMotion','Start-HudBallCollapse','Schedule-HudBallExpansion','Schedule-HudBallCollapse','Update-HudBallMotion','Get-HudClampedPosition','Get-HudBallExpansionPosition','Get-TaskSourceLabel','Get-TaskListSubtitle','Get-TaskListMetricsText')) {
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
function Get-HudStatus { $script:fixtureStatus }
function Test-HudQuietLayoutShowsTasks { $false }
function Test-HudStateQuiet($State,$Keep) { $true }
function Set-HudIndicatorCollapsed($Collapsed) { $script:isMainIndicatorCollapsed = $Collapsed }
function Position-TaskBubbles { }
function Move-HudToConfiguredPosition { }
function Write-HudDebug($Message) { }
function Set-HudBallExpanded([bool]$Expanded) { $script:isFloatingBallExpanded = $Expanded }
function New-HudRoleBrush($Color) { New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString($Color)) }
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
    $ballStatusBackground = $hud.FindName('BallStatusBackground')
    $surfaceMotionState = [pscustomobject]@{ Version=0; Collapsing=$false }
    $hudSurfaceMotion = $hud.FindName('HudSurfaceMotion')
    $surfaceMotionInitialized = $false
    $lastMotionCollapsed = $false
    $ballMotionSignature = ''
    $ballStateStoryboard = $null
    $ballBackgroundStoryboard = $null
    $fixtureStatus = 'idle'
    if ($floatingBallPanel.Children.Count -ne 2 -or $floatingBallPanel.Children[1] -ne $floatingBallCount -or $ballStatusBackground.IsHitTestVisible) { throw 'Floating ball must contain only its count and a non-interactive background.' }
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
    $ballExpandTimer = $null
    foreach ($statuses in @(@(),@('completed','idle','error','paused'),@('active','listening','completed','idle','error'),@('active','active','listening'))) {
        $fixtureStates = @($statuses | ForEach-Object { [pscustomobject]@{Status=$_} })
        Update-HudIdleIndicatorMode
        $expected = @($statuses | Where-Object { $_ -in @('active','listening') }).Count
        if ($floatingBallCount.Text -cne [string]$expected) { throw "Incorrect active task count: $($floatingBallCount.Text), expected $expected" }
        if ($hudShell.Width -ne $config.floatingBallSize -or $hudShell.Height -ne $config.floatingBallSize -or $hudShell.CornerRadius.TopLeft -ne $config.floatingBallSize / 2 -or $hudContentPanel.Visibility -ne 'Collapsed') { throw 'Collapsed ball geometry/content failed.' }
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
    $config.surfaceMode = 'ball'
    foreach ($diameter in @(32,48,80,120)) {
        $config.floatingBallSize = $diameter
        Update-HudIdleIndicatorMode
        if ($hudShell.Width -ne $diameter -or $hudShell.Height -ne $diameter -or $hudShell.CornerRadius.TopLeft -ne $diameter / 2 -or $floatingBallPanel.Width -gt $diameter - 2) { throw 'Ball size/radius/content did not update together.' }
    }
    $config.animateUpdates = $true
    Start-HudSurfaceMotion
    if (-not $hudSurfaceMotion.RenderTransform.HasAnimatedProperties) { throw 'Surface transition animation did not start.' }
    $config.animateUpdates = $false
    Start-HudSurfaceMotion
    if ($hudSurfaceMotion.RenderTransform.HasAnimatedProperties -or $hudSurfaceMotion.Opacity -ne 1 -or $hudSurfaceMotion.RenderTransform.ScaleX -ne 1) { throw 'Disabling animations left a scaled/faded surface.' }
    foreach ($status in @('active','listening','completed','error','aborted','idle','paused')) {
        $fixtureStatus = $status
        Update-HudIdleIndicatorMode
        if ($floatingBallCount.Foreground.Color.ToString() -ne ([Windows.Media.ColorConverter]::ConvertFromString($config.statusColors.$status)).ToString()) { throw "Ball count did not follow status palette: $status" }
        Update-HudBallMotion $true $status
        if ($status -in @('active','listening','completed','error','aborted')) {
            if ($null -eq $ballBackgroundStoryboard) { throw "Missing background motion: $status" }
            $backgroundClock = $ballBackgroundStoryboard
            Update-HudBallMotion $true $status
            if (-not [object]::ReferenceEquals($backgroundClock,$ballBackgroundStoryboard)) { throw 'Unchanged refresh restarted background motion.' }
            foreach ($timeline in $ballBackgroundStoryboard.Children) {
                if ([Windows.Media.Animation.Storyboard]::GetTargetName($timeline) -ne 'BallStatusBackground') { throw 'Background motion targets content.' }
                if (($timeline.RepeatBehavior -eq [Windows.Media.Animation.RepeatBehavior]::Forever) -ne ($status -in @('active','listening'))) { throw 'Only working states may continuously breathe.' }
            }
        } elseif ($null -ne $ballBackgroundStoryboard) { throw 'Idle/paused background must be still.' }
        if ($status -ne 'paused') {
            if ($null -eq $ballStateStoryboard -or $ballStateStoryboard.FillBehavior -ne 'Stop') { throw "Ball status motion missing or unbounded: $status" }
            foreach ($timeline in $ballStateStoryboard.Children) {
                if ($timeline.RepeatBehavior -eq [Windows.Media.Animation.RepeatBehavior]::Forever -or $timeline.Duration.TimeSpan.TotalSeconds -gt 2 -or [Windows.Media.Animation.Storyboard]::GetTargetName($timeline) -ne 'FloatingBallCount') { throw "Ball animation escaped its bounded count-only target: $status" }
            }
            $previousStoryboard = $ballStateStoryboard
            Update-HudBallMotion $true $status
            if (-not [object]::ReferenceEquals($previousStoryboard,$ballStateStoryboard)) { throw 'Unchanged state restarted the ball animation.' }
            $ballStateStoryboard.SeekAlignedToLastTick($hud,[TimeSpan]::FromSeconds(5),[Windows.Media.Animation.TimeSeekOrigin]::BeginTime)
            if ($floatingBallCount.Opacity -ne 1 -or $floatingBallCount.RenderTransform.Children[0].ScaleX -ne 1 -or $floatingBallCount.RenderTransform.Children[0].ScaleY -ne 1 -or $floatingBallCount.RenderTransform.Children[1].X -ne 0 -or $floatingBallCount.RenderTransform.Children[1].Y -ne 0) { throw "Ball motion did not settle naturally: $status" }
        } elseif ($null -ne $ballStateStoryboard) { throw 'Paused ball must remain still.' }
        Update-HudBallMotion $false $status
        if ($null -ne $ballBackgroundStoryboard -or [Math]::Abs($ballStatusBackground.Opacity - 0.12) -gt 0.001) { throw 'Background clock leaked after cancellation.' }
        if ($null -ne $ballStateStoryboard -or $floatingBallCount.Opacity -ne 1 -or $floatingBallCount.RenderTransform.Children[0].ScaleX -ne 1 -or $floatingBallCount.RenderTransform.Children[1].X -ne 0 -or $floatingBallCount.RenderTransform.Children[1].Y -ne 0) { throw 'Stopping ball motion did not restore its neutral appearance.' }
    }
    $config.statusColors.active = '#FF123456'
    $fixtureStatus = 'active'
    Update-HudIdleIndicatorMode
    if ($floatingBallCount.Foreground.Color.ToString() -ne '#FF123456') { throw 'Ball ignored custom status color.' }
    if ($ballStatusBackground.Fill.Color.ToString() -ne '#FF123456') { throw 'Background ignored custom status color.' }
    $config.animateUpdates = $true
    $isFloatingBallExpanded = $true
    Arrange-TestWindow $hud 600 250
    Start-HudBallCollapse
    if (-not $surfaceMotionState.Collapsing) { throw 'Collapse did not start.' }
    $oldVersion = $surfaceMotionState.Version
    Start-HudSurfaceMotion
    if ($surfaceMotionState.Collapsing -or $surfaceMotionState.Version -le $oldVersion) { throw 'Reversal did not invalidate pending collapse.' }
    Stop-HudSurfaceMotion
    if ($hudSurfaceMotion.RenderTransform.ScaleX -ne 1 -or $hudSurfaceMotion.Opacity -ne 1) { throw 'Motion cancellation left a scaled window.' }
    # Let a real WPF completion run: verifies the PowerShell closure writes into
    # the original script scope, not its temporary dynamic module.
    Start-HudBallCollapse
    $frame = New-Object Windows.Threading.DispatcherFrame
    $deadline = New-Object Windows.Threading.DispatcherTimer
    $deadline.Interval = [TimeSpan]::FromMilliseconds(350)
    $deadline.Add_Tick({ $deadline.Stop(); $frame.Continue = $false })
    $deadline.Start()
    [Windows.Threading.Dispatcher]::PushFrame($frame)
    if ($isFloatingBallExpanded -or $surfaceMotionState.Collapsing) { throw 'Collapse completion failed to restore ball mode.' }
} finally { $hud.Close() }

foreach ($screenLeft in @(0,-1920)) {
    $screen = [pscustomobject]@{Left=$screenLeft;Top=-200;Width=1920;Height=1040}
    foreach ($diameter in @(32,48,120)) {
        foreach ($leftward in @($false,$true)) {
            $ball = [pscustomobject]@{Left=$(if ($leftward) { $screenLeft + 1920 - $diameter - 18 } else { $screenLeft - 18 });Top=-218}
            $expanded = Get-HudBallExpansionPosition $ball $diameter $screen 700 300
            $expected = if ($leftward) { $screenLeft + 1238 } else { $screenLeft - 18 }
            if ($expanded.Left -ne $expected -or $expanded.Top -ne -218) { throw 'Ball expansion lost its screen-side anchor.' }
            $offset = $ball.Left - $expanded.Left
            if ($expanded.Left + $offset -ne $ball.Left) { throw 'Collapse anchor drifted.' }
        }
    }
}
Write-Output 'Ball geometry: OK (left/right, negative monitor origins, sizes, anchor restoration)'

# Invoke the actual event handlers against a fake pointer/window, without
# moving the user's mouse or waiting a wall-clock second for every case.
function Get-HudTestHandler([string]$Target,[string]$Member) {
    $node = $syntax.Find({ param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Expression.Extent.Text -eq $Target -and $n.Member.Value -eq $Member },$true)
    if ($null -eq $node) { throw "Interaction handler missing: $Target.$Member" }
    $node.Arguments[0].ScriptBlock.GetScriptBlock()
}
$hud = [pscustomobject]@{IsVisible=$true;IsMouseOver=$true;ContextMenu=$null}
$ballExpandTimer = New-Object Windows.Threading.DispatcherTimer
$intervalAssignment = $syntax.Find({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$ballExpandTimer.Interval' },$true)
if ($null -eq $intervalAssignment) { throw 'Hover interval assignment missing.' }
$ballExpandTimer.Interval = & ([scriptblock]::Create($intervalAssignment.Right.Extent.Text))
if ($ballExpandTimer.Interval.TotalMilliseconds -ne 200) { throw 'Hover expansion must wait 200 ms.' }
$compiledView = [IO.File]::ReadAllText((Join-Path $root 'src-dotnet\CodexMonitorHud.App\MainHudView.cs'))
if ($compiledView -notmatch '_ballExpandTimer = [^\r\n]+TimeSpan.FromMilliseconds\(200\)') { throw 'Compiled and legacy hover delays diverged.' }
$ballCollapseTimer = New-Object Windows.Threading.DispatcherTimer
$ballModeActive=$true; $isFloatingBallExpanded=$false; $isHudDragging=$false; $closingApp=$false
$surfaceMotionState = [pscustomobject]@{Version=0;Collapsing=$false}
$enter = Get-HudTestHandler '$hud' 'Add_MouseEnter'
$leave = Get-HudTestHandler '$hud' 'Add_MouseLeave'
$press = Get-HudTestHandler '$hud' 'Add_PreviewMouseDown'
$tick = Get-HudTestHandler '$ballExpandTimer' 'Add_Tick'
& $enter
if ($isFloatingBallExpanded) { throw 'Pointer entry expanded immediately.' }
& $press
if ($ballExpandTimer.IsEnabled) { throw 'Press did not cancel hover delay.' }
$isHudDragging=$true
& $enter; & $tick
if ($ballExpandTimer.IsEnabled -or $isFloatingBallExpanded) { throw 'Drag allowed hover expansion.' }
$isHudDragging=$false
& $enter; & $leave
if ($ballExpandTimer.IsEnabled) { throw 'Leave retained a stale expansion timer.' }
$hud.IsMouseOver=$false
& $tick
if ($isFloatingBallExpanded) { throw 'Stale hover tick expanded after leave.' }
$hud.IsMouseOver=$true; $hud.IsVisible=$false
& $tick
if ($isFloatingBallExpanded) { throw 'Hidden HUD expanded.' }
$hud.IsVisible=$true; $hud.ContextMenu=[pscustomobject]@{IsOpen=$true}
& $tick
if ($isFloatingBallExpanded) { throw 'Context menu allowed expansion.' }
$hud.ContextMenu=$null
& $tick
if ([Windows.Input.Mouse]::LeftButton -ne 'Pressed' -and [Windows.Input.Mouse]::RightButton -ne 'Pressed' -and -not $isFloatingBallExpanded) { throw 'Valid dwell did not expand.' }
$ballExpandTimer.Stop(); $ballCollapseTimer.Stop()
Write-Output 'Hover delay: OK (no immediate expand, press/drag/leave/hidden/menu guards, valid dwell)'

# Test completed-click vs drag-out-and-back using the production mouse handler.
function Stop-HudSurfaceMotion { }
$click = Get-HudTestHandler '$hud' 'Add_MouseLeftButtonDown'
$hud = [pscustomobject]@{ IsVisible=$true;IsMouseOver=$true;Left=100.0;Top=200.0;TrackMove=$null;DragKind='click' }
$hud | Add-Member ScriptMethod Add_LocationChanged { param($handler) $this.TrackMove=$handler }
$hud | Add-Member ScriptMethod Remove_LocationChanged { param($handler) $this.TrackMove=$null }
$hud | Add-Member ScriptMethod DragMove {
    if ($this.DragKind -eq 'outback') {
        $this.Left += 10
        $this.TrackMove.Invoke($this,[EventArgs]::Empty)
        $this.Left -= 10
        $this.TrackMove.Invoke($this,[EventArgs]::Empty)
    }
    if ($this.DragKind -eq 'error') { throw 'Synthetic drag cancellation' }
}
$mouseFixture = [pscustomobject]@{ClickCount=1;ButtonState=[Windows.Input.MouseButtonState]::Pressed}
$mouseFixture | Add-Member ScriptMethod GetPosition { param($window) New-Object Windows.Point(3,3) }
foreach ($dragKind in @('click','outback','error')) {
    $hud.DragKind=$dragKind; $isFloatingBallExpanded=$false; $isHudDragging=$false; $ballModeActive=$true
    $mouseFixture | ForEach-Object { & $click }
    if ($isFloatingBallExpanded -ne ($dragKind -eq 'click') -or $isHudDragging -or $null -ne $hud.TrackMove) { throw "Click/drag discrimination or cleanup failed: $dragKind" }
}
Write-Output 'Ball click: OK (immediate completed click, no expansion after drag out/back or canceled drag)'
Write-Output 'Floating ball: OK (count-only, active counts, expand/collapse, click-through, seven status colors, bounded state motion, cancellation, no refresh replay)'

$bubble = Read-TestWindow 'TaskBubbleWindow.xaml'
try {
    if ($null -ne $bubble.FindName('TaskBubbleDismissButton')) { throw 'Detached bubble still exposes a redundant close button.' }
    $mergeButton = $bubble.FindName('TaskBubbleMergeButton')
    if ($null -eq $mergeButton) { throw 'Detached bubble lost its merge action.' }
    $header = $mergeButton.Parent
    if (@($header.Children | Where-Object { $_ -is [Windows.Controls.Button] }).Count -ne 1) { throw 'Detached bubble must have exactly one action button.' }
    $scaleRoot = $bubble.FindName('TaskBubbleScaleRoot')
    $bubble.FindName('TaskBubbleName').Text = 'Synthetic task'
    $bubble.FindName('TaskBubbleMetrics').Text = 'Model / context / total'
    if ($null -ne $bubble.FindName('TaskBubbleResizeThumb') -or $bubble.SizeToContent -ne 'WidthAndHeight') { throw 'The old window resize affordance remains.' }
    $unbounded = New-Object Windows.Size([double]::PositiveInfinity,[double]::PositiveInfinity)
    $scaleRoot.Measure($unbounded)
    $baseWidth = $scaleRoot.DesiredSize.Width - 32
    $baseHeight = $scaleRoot.DesiredSize.Height - 32
    foreach ($scale in @(0.6,1.0,1.5,2.0)) {
        $scaleRoot.LayoutTransform.ScaleX = $scaleRoot.LayoutTransform.ScaleY = $scale
        $scaleRoot.Measure($unbounded)
        if ([Math]::Abs(($scaleRoot.DesiredSize.Width - 32) - $baseWidth * $scale) -gt 2 -or [Math]::Abs(($scaleRoot.DesiredSize.Height - 32) - $baseHeight * $scale) -gt 2) { throw 'Bubble content did not scale proportionally.' }
        $scaleRoot.Arrange((New-Object Windows.Rect(0,0,$scaleRoot.DesiredSize.Width,$scaleRoot.DesiredSize.Height)))
        $scaleRoot.UpdateLayout()
        Assert-InBounds $mergeButton $scaleRoot $scaleRoot.ActualWidth $scaleRoot.ActualHeight
    }
} finally { $bubble.Close() }
Import-Module (Join-Path $root 'src\MonitorHud.Core.psm1') -Force
$settingsLocale = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'locales\en.json') | ConvertFrom-Json
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $paths.DefaultConfigPath | ConvertFrom-Json
$state = [pscustomobject]@{ClientSurface='cli';ProfileId='codex';ModelProvider='custom';ConversationLabel='';StartedAt=[DateTimeOffset]::Now;Snapshot=[pscustomobject]@{CallTotal=49115;Model='test-model';Input=100;Cached=50;TaskTotal=50000}}
foreach ($provider in @('custom','openai','deepseek')) {
    $state.ModelProvider = $provider
    $config.showProviderLabel = $true
    if ((Get-TaskSourceLabel $state) -eq $settingsLocale.sourceCli) { throw 'Enabled provider label is missing.' }
    $config.showProviderLabel = $false
    if ((Get-TaskSourceLabel $state) -ne $settingsLocale.sourceCli) { throw 'Disabled provider label leaked its name.' }
}
$config.multiTask.listFields.status = $false
$config.multiTask.listFields.callTotal = $true
$config.multiTask.listFields.time = $true
$config.multiTask.listFields.updated = $false
$config.multiTask.listDetail = 'balanced'
$time = $state.StartedAt.ToLocalTime().ToString('HH:mm')
$subtitle = Get-TaskListSubtitle $state
if ($subtitle.IndexOf($settingsLocale.callTotal) -le $subtitle.IndexOf($time) -or (Get-TaskListMetricsText $state).Contains($settingsLocale.callTotal)) { throw 'Call total was not moved after time on the lower line.' }
$config.multiTask.listFields.time = $false
if (-not (Get-TaskListSubtitle $state).Contains($settingsLocale.callTotal)) { throw 'Hiding time also hid call total.' }
$config.multiTask.listFields.callTotal = $false
if ((Get-TaskListSubtitle $state).Contains($settingsLocale.callTotal)) { throw 'Call-total visibility switch was ignored.' }
Write-Output 'Surface interactions: OK (whole-bubble scale, motion disable, ball sizes, provider visibility, lower-line call total)'
