using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using CodexMonitorHud.Core.Configuration;
using CodexMonitorHud.Core.Models;
using CodexMonitorHud.Core.Presentation;
using CodexMonitorHud.Core.Pricing;
using CodexMonitorHud.Core.Sessions;
using CodexMonitorHud.Core.State;

namespace CodexMonitorHud.App;

internal sealed partial class HudApplicationController : IDisposable
{
    private readonly Application _application;
    private readonly HudPaths _paths;
    private readonly AppArguments _arguments;
    private readonly HudLog _log;
    private readonly LocaleCatalog _locales;
    private readonly SessionMonitorEngine _engine;
    private readonly IReadOnlyList<SessionProfile> _profiles;
    private readonly IReadOnlyList<SessionChangeTracker> _changeTrackers;
    private readonly IReadOnlyList<SessionChangeTracker> _titleTrackers;
    private readonly SessionChangeTracker _notificationTracker;
    private readonly SessionChangeTracker _signalTracker;
    private readonly MainHudView _view;
    private readonly HudCommandSurfaces _commands;
    private readonly DispatcherTimer _timer;
    private readonly System.Windows.Media.MediaPlayer _completionMediaPlayer = new();
    private readonly Dictionary<string, int> _completionRevisions = new(StringComparer.OrdinalIgnoreCase);
    private readonly string _heartbeatPath;
    private readonly string _hostsRoot;
    private readonly string _notificationsRoot;
    private JsonObject _configDocument;
    private HudSettings _settings;
    private PricingCatalog _pricing;
    private IReadOnlyDictionary<string, string> _locale;
    private IReadOnlyDictionary<string, string> _settingsLocale;
    private DateTimeOffset _lastTick = DateTimeOffset.Now;
    private DateTimeOffset _lastHeartbeat = DateTimeOffset.MinValue;
    private DateTimeOffset _lastReconciliation = DateTimeOffset.MinValue;
    private DateTimeOffset _lastRuntimeReconciliation = DateTimeOffset.MinValue;
    private DateTimeOffset _lastLifecyclePoll = DateTimeOffset.MinValue;
    private DateTimeOffset _lastQuietPoll = DateTimeOffset.MinValue;
    private DateTimeOffset _lastNotificationReconciliation = DateTimeOffset.MinValue;
    private DateTimeOffset _managedGraceUntil = DateTimeOffset.MinValue;
    private DateTimeOffset _responsiveUntil = DateTimeOffset.MinValue;
    private DateTimeOffset _lastHostCheck = DateTimeOffset.MinValue;
    private DateTimeOffset _lastMaterialUpdateAt = DateTimeOffset.Now;
    private DateTimeOffset _lastWorkingSetTrimAt = DateTimeOffset.MinValue;
    private DateTimeOffset _lastFullGcAt = DateTimeOffset.MinValue;
    private bool _lastHostActive = true;
    private long _lastRenderedRevision = -1;
    private string _lastOverallStatus = string.Empty;
    private string _lastRegistryContent = string.Empty;
    private string _previousQuotaGuardState = "unavailable";
    private bool _quotaGuardObserved;
    private Task<OfficialCodexAllowance?>? _officialAllowanceRead;
    private OfficialCodexAllowance? _officialAllowance;
    private DateTimeOffset _lastOfficialAllowanceAttempt = DateTimeOffset.MinValue;
    private bool _officialAllowanceWasEnabled;
    private bool _paused;
    private bool _initialScanComplete;
    private bool _disposed;
    private bool _memoryTrimPending = true;
    private Process? _settingsHostProcess;
    private int _wakePending;

    public HudApplicationController(
        Application application,
        HudPaths paths,
        AppArguments arguments,
        HudLog log)
    {
        _application = application;
        _paths = paths;
        _arguments = arguments;
        _log = log;
        _completionMediaPlayer.MediaFailed += (_, args) =>
            _log.Write("Completion audio failed: " + args.ErrorException.Message);
        _configDocument = HudConfigStore.Load(paths);
        _settings = HudSettings.From(_configDocument);
        _pricing = PricingCatalog.Load(paths.PluginRoot, _settings.PricingPath);
        _locales = new LocaleCatalog(paths.LocaleRoot);
        _locale = _locales.Get(_settings.Language);
        _settingsLocale = _settings.Language == "symbols" ? _locales.Get("en") : _locale;
        _profiles = SessionProfile.CreateDefaultSet(paths);
        _engine = new SessionMonitorEngine(
            _profiles,
            _settings.ToRuntimeOptions(),
            activitySource: new WindowsSessionActivitySource());
        _changeTrackers = _profiles.Select(static profile => new SessionChangeTracker(profile.SessionsRoot)).ToArray();
        _titleTrackers = _profiles.Select(static profile => new SessionChangeTracker(
            Path.GetDirectoryName(profile.SessionIndexPath)!,
            Path.GetFileName(profile.SessionIndexPath),
            includeSubdirectories: false)).ToArray();
        _view = new MainHudView(
            Path.Combine(paths.PluginRoot, "src", "HudWindow.xaml"),
            Path.Combine(paths.PluginRoot, "src", "TaskBubbleWindow.xaml"));
        _commands = new HudCommandSurfaces(_view.Window, Path.Combine(paths.PluginRoot, "assets", "codex-monitor-hud.ico"));
        _heartbeatPath = Path.Combine(paths.StateRoot, "hud.heartbeat");
        _hostsRoot = Path.Combine(paths.StateRoot, "hosts");
        _notificationsRoot = Path.Combine(paths.StateRoot, "notifications");
        Directory.CreateDirectory(_notificationsRoot);
        _notificationTracker = new SessionChangeTracker(_notificationsRoot, "*.json", includeSubdirectories: false);
        _signalTracker = new SessionChangeTracker(paths.StateRoot, "*.signal", includeSubdirectories: false);
        _timer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromMilliseconds(200)
        };
        _timer.Tick += OnTick;
        foreach (var tracker in _changeTrackers) tracker.ChangeAvailable += QueueWake;
        foreach (var tracker in _titleTrackers) tracker.ChangeAvailable += QueueWake;
        _notificationTracker.ChangeAvailable += QueueWake;
        _signalTracker.ChangeAvailable += QueueWake;
        WireCommands();
    }

    public void Start()
    {
        _log.Write($"Compiled HUD v3.3.0 starting. config={_paths.ConfigPath}; profiles={string.Join(',', _profiles.Select(static profile => profile.Id))}; agentNotices={_settings.AgentNotifications.Enabled}/{_settings.AgentNotifications.Permission}");
        var now = DateTimeOffset.Now;
        _engine.RefreshActiveSessions(now);
        _engine.Poll(now);
        InitializeCompletionRevisions();
        StartOfficialAllowanceRead(now);
        _lastReconciliation = now;
        _lastRuntimeReconciliation = now;
        _lastLifecyclePoll = now;
        _initialScanComplete = true;
        ApplyPricing();
        Render(force: true);
        _view.Window.Show();
        _timer.Start();
        if (_arguments.OpenSettings)
        {
            OpenSettings();
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _timer.Stop();
        foreach (var tracker in _changeTrackers) tracker.Dispose();
        foreach (var tracker in _titleTrackers) tracker.Dispose();
        _notificationTracker.Dispose();
        _signalTracker.Dispose();
        _commands.Dispose();
        _completionMediaPlayer.Close();
        _settingsHostProcess?.Dispose();
        _view.Dispose();
        TryDelete(_heartbeatPath);
    }

    private void QueueWake()
    {
        if (_disposed || Interlocked.Exchange(ref _wakePending, 1) == 1)
        {
            return;
        }
        try
        {
            _application.Dispatcher.BeginInvoke(DispatcherPriority.Background, (Action)(() =>
            {
                Interlocked.Exchange(ref _wakePending, 0);
                if (!_disposed)
                {
                    OnTick(null, EventArgs.Empty);
                }
            }));
        }
        catch (InvalidOperationException)
        {
            Interlocked.Exchange(ref _wakePending, 0);
        }
    }

    private void WireCommands()
    {
        _view.SettingsRequested += OpenSettings;
        _view.ExitRequested += StopByUser;
        _view.ToggleListRequested += ToggleTaskList;
        _view.SurfaceChanged += () => Render(force: true);
        _view.DismissRequested += path =>
        {
            _engine.Dismiss(path);
            _view.RemoveState(path);
            Render(force: true);
        };
        _view.OpenRequested += OpenTask;
        _view.PositionChanged += (left, top) =>
        {
            _configDocument["position"] = "custom";
            _configDocument["customLeft"] = left;
            _configDocument["customTop"] = top;
            // Position-only edits do not change monitor options, locales or pricing.
            HudConfigStore.Save(_paths, _configDocument);
            _settings = _settings with { Position = "custom", CustomLeft = left, CustomTop = top };
        };
        _view.DetachedChanged += (_, _) => Render(force: true);
        _view.AttentionPresented += (surface, path, reason) =>
        {
            var workspace = _engine.States.TryGetValue(path, out var state) ? state.Workspace : Path.GetFileName(path);
            _log.Write($"Attention surface: {surface} {workspace} reason={reason}");
        };
        _commands.SettingsRequested += OpenSettings;
        _commands.PassthroughToggleRequested += TogglePassthrough;
        _commands.PauseToggleRequested += () =>
        {
            _paused = !_paused;
            Render(force: true);
        };
        _commands.ResetPositionRequested += () =>
        {
            if (_settings.Position == "custom")
            {
                _configDocument["position"] = "top-right";
                SaveAndReloadSettings();
            }
            Render(force: true);
        };
        _commands.ModeRequested += SetMode;
        _commands.ExitRequested += StopByUser;
    }

    private void OnTick(object? sender, EventArgs args)
    {
        var now = DateTimeOffset.Now;
        var tickGap = now - _lastTick;
        _lastTick = now;
        if (tickGap > TimeSpan.FromSeconds(10))
        {
            _managedGraceUntil = now.AddSeconds(15);
            foreach (var tracker in _changeTrackers) tracker.ForceReconciliation();
            _log.Write($"Resume/tick gap detected: {tickGap.TotalSeconds:0.0}s; managed grace applied.");
        }

        if (now - _lastHeartbeat >= TimeSpan.FromSeconds(2))
        {
            _lastHeartbeat = now;
            TryWriteText(_heartbeatPath, DateTime.UtcNow.ToString("O"));
        }
        // DragMove pumps messages: avoid disk scans, GC and preset repositioning mid-drag.
        if (_view.IsDragging) return;

        if (_arguments.Managed && now - _lastHostCheck >= TimeSpan.FromSeconds(2))
        {
            _lastHostCheck = now;
            _lastHostActive = HasActiveHost(now);
        }
        if (_arguments.Managed && now >= _managedGraceUntil && !_lastHostActive)
        {
            Stop();
            return;
        }

        if (ConsumeSignal("exit.signal"))
        {
            Stop();
            return;
        }
        if (ConsumeSignal("open-settings.signal")) OpenSettings();
        if (ConsumeSignal("show.signal")) _view.Window.Show();
        if (ConsumeSignal("hide.signal")) _view.Window.Hide();
        if (ConsumeSignal("pause.signal")) _paused = !_paused;
        if (ConsumeSignal("passthrough-off.signal") && _settings.MousePassthrough) SetMousePassthrough(false);
        if (ConsumeSignal("reload-settings.signal")) ReloadSettings();

        var notificationReconciliationDue = now - _lastNotificationReconciliation >= TimeSpan.FromSeconds(30);
        var changed = _notificationTracker.ConsumeDirty() || notificationReconciliationDue
            ? ProcessNotifications(now)
            : false;
        _ = _notificationTracker.DrainChangedPaths();
        var titleDirty = false;
        foreach (var tracker in _titleTrackers)
        {
            titleDirty |= tracker.ConsumeDirty();
            _ = tracker.DrainChangedPaths();
        }
        if (titleDirty || _engine.HasTitleBacklog)
        {
            changed |= _engine.RefreshTitles();
            if (_engine.HasTitleBacklog)
            {
                _responsiveUntil = now.AddSeconds(2);
            }
        }
        if (notificationReconciliationDue)
        {
            _lastNotificationReconciliation = now;
        }
        if (!_paused)
        {
            if (now - _lastRuntimeReconciliation >= TimeSpan.FromSeconds(2))
            {
                _lastRuntimeReconciliation = now;
                changed |= _engine.RefreshRuntimeSessions(now);
            }
            var filePollPerformed = false;
            var reconcileDue = now - _lastReconciliation >= TimeSpan.FromSeconds(30);
            var dirty = false;
            var overflowed = false;
            var structural = false;
            var changedPaths = new List<string>();
            foreach (var tracker in _changeTrackers)
            {
                dirty |= tracker.ConsumeDirty();
                overflowed |= tracker.ConsumeOverflowed();
                structural |= tracker.ConsumeStructural();
                changedPaths.AddRange(tracker.DrainChangedPaths());
            }
            if (dirty || reconcileDue || overflowed)
            {
                filePollPerformed = true;
                _lastLifecyclePoll = now;
                if (reconcileDue)
                {
                    _lastReconciliation = now;
                }
                if (reconcileDue || structural || overflowed)
                {
                    changed |= _engine.RefreshActiveSessions(now);
                    changed |= _engine.Poll(now);
                }
                else
                {
                    changed |= _engine.PollPaths(changedPaths, now);
                }
            }
            else if (_engine.HasBacklog)
            {
                filePollPerformed = true;
                _lastLifecyclePoll = now;
                changed |= _engine.PollBacklog(now);
            }
            else if (_engine.HasPendingIdentity && now - _lastLifecyclePoll >= TimeSpan.FromMilliseconds(800))
            {
                filePollPerformed = true;
                _lastLifecyclePoll = now;
                changed |= _engine.PollPendingIdentity(now);
            }
            else if (now - _lastLifecyclePoll >= TimeSpan.FromMilliseconds(800))
            {
                _lastLifecyclePoll = now;
                changed |= _engine.AdvanceLifecycleOnly(now);
            }
            if (filePollPerformed && _engine.HasBacklog)
            {
                _responsiveUntil = now.AddSeconds(2);
            }
        }

        PlayCompletionSoundForTransitions();

        changed |= CompleteOrStartOfficialAllowanceRead(now);
        var overallStatus = GetOverallStatus(now);
        if (now - _lastQuietPoll >= TimeSpan.FromMilliseconds(500))
        {
            _lastQuietPoll = now;
            var quietStates = _engine.GetVisibleStates(now);
            _view.RefreshQuietMode(
                _settings,
                _settingsLocale,
                quietStates,
                state => _engine.GetStatus(state, _paused, now),
                GetOverallStatus(now, quietStates),
                now);
            _engine.HoldTerminalExits = _view.HoldTerminalExits;
        }
        if (changed || _lastRenderedRevision != _engine.MaterialRevision || overallStatus != _lastOverallStatus)
        {
            _responsiveUntil = now.AddSeconds(2);
            _lastMaterialUpdateAt = now;
            _memoryTrimPending = true;
            ApplyPricing();
            Render(force: true);
        }
        _timer.Interval = now < _responsiveUntil
            ? TimeSpan.FromMilliseconds(250)
            : overallStatus is "active" or "listening"
                ? TimeSpan.FromMilliseconds(800)
                : TimeSpan.FromMilliseconds(1500);
        TryTrimWorkingSet(now);
    }

    private void TryTrimWorkingSet(DateTimeOffset now)
    {
        if (!_memoryTrimPending)
        {
            return;
        }
        var quietEnough = now - _lastMaterialUpdateAt >= TimeSpan.FromSeconds(5);
        var activeTrimDue = now - _lastWorkingSetTrimAt >= TimeSpan.FromSeconds(5);
        if (!quietEnough && !activeTrimDue)
        {
            return;
        }

        try
        {
            using var process = Process.GetCurrentProcess();
            process.Refresh();
            if (process.WorkingSet64 < 220L * 1024 * 1024)
            {
                _memoryTrimPending = false;
                return;
            }
            if (now - _lastFullGcAt >= TimeSpan.FromMinutes(2))
            {
                GC.Collect(2, GCCollectionMode.Optimized, blocking: true, compacting: false);
                GC.WaitForPendingFinalizers();
                GC.Collect(2, GCCollectionMode.Optimized, blocking: true, compacting: false);
                _lastFullGcAt = now;
            }
            _ = NativeMethods.SetProcessWorkingSetSize(NativeMethods.GetCurrentProcess(), (nint)(-1), (nint)(-1));
            _lastWorkingSetTrimAt = now;
            _memoryTrimPending = false;
            process.Refresh();
            _log.Write($"Idle memory trim completed; workingSetMB={process.WorkingSet64 / 1024d / 1024d:0.0}");
        }
        catch (Exception exception)
        {
            _memoryTrimPending = false;
            _log.Write("Idle memory trim skipped: " + exception.Message);
        }
    }

    private void Render(bool force)
    {
        if (_view.IsDragging) return;
        var now = DateTimeOffset.Now;
        var states = _engine.GetVisibleStates(now);
        var snapshot = BuildDisplaySnapshot(states);
        var status = GetOverallStatus(now, states, snapshot);
        if (!force && _lastRenderedRevision == _engine.MaterialRevision && _lastOverallStatus == status)
        {
            return;
        }
        _lastRenderedRevision = _engine.MaterialRevision;
        _lastOverallStatus = status;
        _view.Render(
            _settings,
            _locale,
            _settingsLocale,
            _locales.Get("zh-CN"),
            _locales.Get("en"),
            states,
            snapshot,
            state => _engine.GetStatus(state, _paused, now),
            status,
            _paused,
            _initialScanComplete);
        _engine.HoldTerminalExits = _view.HoldTerminalExits;
        _commands.Update(_locales.Get("zh-CN"), _locales.Get("en"), status, _settings.MultiTask.DisplayMode, _paused, _settings.MousePassthrough);
        WriteTaskRegistry(states, snapshot, now);
    }

    private HudSnapshot? BuildDisplaySnapshot(IReadOnlyList<SessionState> states)
    {
        var snapshots = states.Select(static state => state.Snapshot).OfType<HudSnapshot>().ToArray();
        if (snapshots.Length == 0)
        {
            return null;
        }
        HudSnapshot? display;
        if (_settings.MonitorScope == "aggregate")
        {
            display = SnapshotAggregator.Merge(snapshots, Get(_locale, "multiTaskSummary"));
        }
        else
        {
            var latest = snapshots.OrderByDescending(static snapshot => snapshot.Timestamp).First() with { ActiveTasks = snapshots.Length };
            var allowance = SnapshotAggregator.GetLatestAllowance(snapshots);
            display = allowance is null
                ? latest
                : latest with
                {
                    AllowanceTimestamp = allowance.AllowanceTimestamp,
                    WeeklyRemainingPercent = allowance.WeeklyRemainingPercent,
                    FiveHourRemainingPercent = allowance.FiveHourRemainingPercent
                };
        }
        if (display is null) return null;
        if (_settings.OfficialAllowance.Enabled)
        {
            // Never mix a selected official source with a local session-log
            // value that may belong to the previously signed-in account.
            var officialAllowance = _officialAllowance;
            return display with
            {
                AllowanceTimestamp = officialAllowance?.ObservedAt,
                WeeklyRemainingPercent = officialAllowance?.WeeklyRemainingPercent,
                FiveHourRemainingPercent = officialAllowance?.FiveHourRemainingPercent
            };
        }
        return display;
    }

    private bool CompleteOrStartOfficialAllowanceRead(DateTimeOffset now)
    {
        if (!_settings.OfficialAllowance.Enabled)
        {
            var changed = _officialAllowance is not null;
            _officialAllowance = null;
            _officialAllowanceRead = null;
            return changed;
        }
        if (_officialAllowanceRead is { IsCompleted: true })
        {
            var result = _officialAllowanceRead.Status == TaskStatus.RanToCompletion ? _officialAllowanceRead.Result : null;
            _officialAllowanceRead = null;
            if (result is not null)
            {
                var changed = !Equals(_officialAllowance, result);
                _officialAllowance = result;
                return changed;
            }

            // Do not leave a previous account's number visible if the fresh
            // official read failed after an account switch.
            var unavailableChanged = _officialAllowance is not null;
            _officialAllowance = null;
            return unavailableChanged;
        }
        StartOfficialAllowanceRead(now);
        return false;
    }

    private void StartOfficialAllowanceRead(DateTimeOffset now)
    {
        var interval = _officialAllowance is null ? TimeSpan.FromSeconds(3) : TimeSpan.FromSeconds(20);
        if (!_settings.OfficialAllowance.Enabled || _officialAllowanceRead is not null || now - _lastOfficialAllowanceAttempt < interval) return;
        _lastOfficialAllowanceAttempt = now;
        _officialAllowanceRead = Task.Run(OfficialCodexAllowanceReader.TryReadAsync);
    }

    private string GetOverallStatus(DateTimeOffset now, IReadOnlyList<SessionState>? states = null, HudSnapshot? snapshot = null)
    {
        if (_paused)
        {
            return "paused";
        }
        states ??= _engine.GetVisibleStates(now);
        var statuses = states.Select(state => _engine.GetStatus(state, false, now)).ToArray();
        if (statuses.Contains("aborted", StringComparer.Ordinal)) return "aborted";
        if (statuses.Contains("completed", StringComparer.Ordinal)) return "completed";
        if (_engine.LastReadErrorAt != DateTimeOffset.MinValue &&
            (now - _engine.LastReadErrorAt).TotalSeconds <= _settings.StatusTiming.ErrorHoldSeconds) return "error";
        snapshot ??= states.Select(static state => state.Snapshot)
            .OfType<HudSnapshot>()
            .OrderByDescending(static item => item.Timestamp)
            .FirstOrDefault();
        if (snapshot is null) return "idle";
        var reference = _engine.LastUsageAt != DateTimeOffset.MinValue ? _engine.LastUsageAt : snapshot.Timestamp;
        var age = (now - reference).TotalSeconds;
        return age <= _settings.StatusTiming.ActiveSeconds
            ? "active"
            : age <= _settings.StatusTiming.IdleSeconds
                ? "listening"
                : "idle";
    }

    private void ApplyPricing()
    {
        foreach (var state in _engine.States.Values)
        {
            if (state.Snapshot is null)
            {
                continue;
            }
            if (state.Snapshot.EstimatedCostUsd.HasValue)
            {
                continue;
            }
            var estimate = _pricing.Estimate(state.Snapshot);
            if (estimate is not null)
            {
                state.Snapshot = state.Snapshot with { EstimatedCostUsd = estimate.CostUsd };
            }
        }
    }

    private void SetMode(string mode)
    {
        if (mode is not ("summary" or "list" or "split"))
        {
            return;
        }
        if (mode == "summary" || mode == "list" && _settings.MultiTask.DisplayMode == "split")
        {
            _view.MergeAll();
        }
        _view.ResetTaskListVisibility();
        _configDocument["multiTask"]!["displayMode"] = mode;
        SaveAndReloadSettings();
        if (mode == "split")
        {
            _view.SplitAll(_engine.GetVisibleStates(), _settings.MultiTask.MaxSplitBubbles);
        }
        Render(force: true);
    }

    private void ToggleTaskList()
    {
        // The aggregate button is a list visibility control, not a "merge all"
        // command. In split mode and when individual bubbles are detached, it
        // must leave those windows alone.
        if (_settings.MultiTask.DisplayMode == "summary")
        {
            SetMode("list");
            return;
        }
        _view.ToggleTaskListVisibility(_settings);
        Render(force: true);
    }

    private void TogglePassthrough()
    {
        if (!_settings.MousePassthrough)
        {
            var answer = MessageBox.Show(
                Get(_settingsLocale, "mousePassthroughConfirm"),
                Get(_settingsLocale, "mousePassthroughTitle"),
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            if (answer != MessageBoxResult.Yes)
            {
                return;
            }
            SetMousePassthrough(true);
            OpenSettings();
        }
        else
        {
            SetMousePassthrough(false);
        }
    }

    private void SetMousePassthrough(bool enabled)
    {
        _configDocument["mousePassthrough"] = enabled;
        SaveAndReloadSettings();
        _view.SetMousePassthrough(enabled);
        Render(force: true);
    }

    private void SaveAndReloadSettings()
    {
        HudConfigStore.Save(_paths, _configDocument);
        _settings = HudSettings.From(_configDocument);
        _engine.UpdateOptions(_settings.ToRuntimeOptions());
        _locale = _locales.Get(_settings.Language);
        _settingsLocale = _settings.Language == "symbols" ? _locales.Get("en") : _locale;
        ResetOfficialAllowanceWhenSourceChanges();
    }

    private void ReloadSettings()
    {
        var previousMode = _settings.MultiTask.DisplayMode;
        _configDocument = HudConfigStore.Load(_paths);
        _settings = HudSettings.From(_configDocument);
        _pricing = PricingCatalog.Load(_paths.PluginRoot, _settings.PricingPath);
        foreach (var state in _engine.States.Values)
        {
            if (state.Snapshot is not null)
            {
                state.Snapshot = state.Snapshot with { EstimatedCostUsd = null };
            }
        }
        _engine.UpdateOptions(_settings.ToRuntimeOptions());
        _locale = _locales.Get(_settings.Language);
        _settingsLocale = _settings.Language == "symbols" ? _locales.Get("en") : _locale;
        ResetOfficialAllowanceWhenSourceChanges();
        if (_settings.MultiTask.DisplayMode == "split" && previousMode != "split")
        {
            _view.SplitAll(_engine.GetVisibleStates(), _settings.MultiTask.MaxSplitBubbles);
        }
        else if (previousMode == "split" && _settings.MultiTask.DisplayMode != "split")
        {
            _view.MergeAll();
        }
        Render(force: true);
    }

    private void InitializeCompletionRevisions()
    {
        _completionRevisions.Clear();
        foreach (var state in _engine.States.Values)
        {
            _completionRevisions[state.Path] = state.CompletionRevision;
        }
    }

    private void PlayCompletionSoundForTransitions()
    {
        var livePaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var completionDetected = false;
        foreach (var state in _engine.States.Values)
        {
            livePaths.Add(state.Path);
            _completionRevisions.TryGetValue(state.Path, out var previousRevision);
            if (state.CompletionRevision > previousRevision)
            {
                completionDetected = true;
            }
            _completionRevisions[state.Path] = state.CompletionRevision;
        }

        foreach (var stalePath in _completionRevisions.Keys.Where(path => !livePaths.Contains(path)).ToArray())
        {
            _completionRevisions.Remove(stalePath);
        }

        if (!completionDetected || _settings.CompletionSound == "off")
        {
            return;
        }

        try
        {
            if (_settings.CompletionSound == "file")
            {
                var path = Environment.ExpandEnvironmentVariables(_settings.CompletionSoundFile.Trim());
                if (string.IsNullOrWhiteSpace(path)) return;
                if (!Path.IsPathRooted(path)) path = Path.Combine(_paths.PluginRoot, path);
                if (!File.Exists(path))
                {
                    _log.Write("Completion audio file not found: " + path);
                    return;
                }
                _completionMediaPlayer.Stop();
                _completionMediaPlayer.Close();
                _completionMediaPlayer.Volume = 1;
                _completionMediaPlayer.Open(new Uri(Path.GetFullPath(path), UriKind.Absolute));
                _completionMediaPlayer.Play();
                _log.Write("Completion audio played: " + path);
                return;
            }
            var sound = _settings.CompletionSound switch
            {
                "exclamation" => System.Media.SystemSounds.Exclamation,
                "beep" => System.Media.SystemSounds.Beep,
                _ => System.Media.SystemSounds.Asterisk
            };
            sound.Play();
            _log.Write($"Completion sound played: {_settings.CompletionSound}");
        }
        catch (Exception exception) when (exception is InvalidOperationException or IOException or UnauthorizedAccessException or UriFormatException)
        {
            _log.Write("Completion sound failed: " + exception.Message);
        }
    }

    private void ResetOfficialAllowanceWhenSourceChanges()
    {
        if (_settings.OfficialAllowance.Enabled == _officialAllowanceWasEnabled) return;
        _officialAllowanceWasEnabled = _settings.OfficialAllowance.Enabled;
        _officialAllowance = null;
        _lastOfficialAllowanceAttempt = DateTimeOffset.MinValue;
    }

    private void OpenSettings()
    {
        var legacy = Path.Combine(_paths.PluginRoot, "src", "CodexMonitorHUD.ps1");
        if (!File.Exists(legacy))
        {
            return;
        }
        try
        {
            using var existingSettings = OpenSettingsMutex();
            if ((_settingsHostProcess is not null && !_settingsHostProcess.HasExited) || existingSettings is not null)
            {
                TryWriteText(Path.Combine(_paths.StateRoot, "settings-host-open.signal"), DateTime.UtcNow.ToString("O"));
                return;
            }
            _settingsHostProcess?.Dispose();
            _settingsHostProcess = Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                ArgumentList =
                {
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    legacy,
                    "-SettingsHost",
                    "-InstanceId",
                    _arguments.InstanceId
                }
            });
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            _log.Write("Settings host launch failed: " + exception.Message);
        }
    }

    private Mutex? OpenSettingsMutex()
    {
        var suffix = string.IsNullOrWhiteSpace(_arguments.InstanceId) ? "" : "-" + string.Concat(_arguments.InstanceId.Select(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-' or '.' ? c : '_'));
        try { return Mutex.TryOpenExisting(@"Local\CodexMonitorHUD-settings" + suffix, out var mutex) ? mutex : null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    private void OpenTask(string path)
    {
        if (!_settings.Behavior.OpenTaskOnDoubleClick || !_engine.States.TryGetValue(path, out var state))
        {
            return;
        }
        if (state.ClientSurface != "desktop")
        {
            _log.Write($"Desktop deep link skipped for {state.ClientSurface}/{state.ModelProvider} task #{state.Number}.");
            return;
        }
        var link = HudFormatting.GetTaskDeepLink(state.SessionId);
        if (link is null)
        {
            return;
        }
        try
        {
            _ = Process.Start(new ProcessStartInfo(link) { UseShellExecute = true });
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            _log.Write("Task deep link failed: " + exception.Message);
        }
    }

    private bool ProcessNotifications(DateTimeOffset now)
    {
        if (!Directory.Exists(_notificationsRoot))
        {
            return false;
        }
        var changed = false;
        foreach (var path in Directory.EnumerateFiles(_notificationsRoot, "*.json").OrderBy(static path =>
                 {
                     try { return File.GetCreationTimeUtc(path); }
                     catch (IOException) { return DateTime.MaxValue; }
                     catch (UnauthorizedAccessException) { return DateTime.MaxValue; }
                 }))
        {
            try
            {
                var file = new FileInfo(path);
                if (!_settings.AgentNotifications.Enabled || file.Length > 8192)
                {
                    _log.Write($"Agent notice discarded; enabled={_settings.AgentNotifications.Enabled}; bytes={file.Length}");
                    TryDelete(path);
                    continue;
                }
                using var document = JsonDocument.Parse(File.ReadAllText(path));
                var root = document.RootElement;
                if (!root.TryGetProperty("source", out var source) || source.GetString() != "codex-mcp")
                {
                    throw new InvalidDataException("Unsupported notification source.");
                }
                var message = root.TryGetProperty("message", out var messageNode) ? messageNode.GetString() ?? string.Empty : string.Empty;
                message = ControlRegex().Replace(message, " ");
                message = WhitespaceRegex().Replace(message, " ").Trim();
                if (message.Length > 160) message = message[..160];
                if (message.Length == 0) throw new InvalidDataException("Empty notification.");
                int? taskNumber = root.TryGetProperty("task_number", out var taskNode) && taskNode.TryGetInt32(out var number)
                    ? number
                    : null;
                var recipe = _settings.AgentNotifications.Permission == "expressive" &&
                             root.TryGetProperty("animation", out var animationNode)
                    ? ParseAgentAnimationRecipe(animationNode, _settings.AgentNotifications.Color)
                    : null;
                if (_engine.AcceptAgentNotice(taskNumber, message, _settings.AgentNotifications.DurationSeconds, recipe, now))
                {
                    var targetLabel = taskNumber?.ToString() ?? "auto";
                    _log.Write($"Agent notice accepted for task #{targetLabel}; expressive={recipe is not null}");
                    TryDelete(path);
                    changed = true;
                }
                else if (now.UtcDateTime - file.CreationTimeUtc > TimeSpan.FromSeconds(60))
                {
                    _log.Write($"Agent notice expired before a visible target was available; task=#{taskNumber?.ToString() ?? "auto"}");
                    TryDelete(path);
                }
                else
                {
                    _log.Write($"Agent notice deferred; target task #{taskNumber?.ToString() ?? "auto"} is not visible yet");
                }
            }
            catch (Exception exception) when (exception is JsonException or IOException or InvalidDataException)
            {
                _log.Write("Agent notice rejected: " + exception.Message);
                TryDelete(path);
            }
        }
        return changed;
    }

    private void WriteTaskRegistry(IReadOnlyList<SessionState> states, HudSnapshot? snapshot, DateTimeOffset now)
    {
        var tasks = states.OrderBy(static state => state.Number).Select(state => new
        {
            task_number = state.Number,
            workspace = state.Workspace,
            status = _engine.GetStatus(state, _paused, now),
            client = state.ClientSurface,
            provider = state.ModelProvider,
            profile = state.ProfileId,
            updated_at = state.LastUsageAt.ToString("O")
        }).ToArray();
        var quotaGuard = BuildQuotaGuard(snapshot);
        var content = JsonSerializer.Serialize(new { tasks, quotaGuard });
        if (content == _lastRegistryContent)
        {
            return;
        }
        _lastRegistryContent = content;
        var registry = JsonSerializer.Serialize(new
        {
            version = 3,
            generated_at = now.ToString("O"),
            quota_guard = quotaGuard,
            tasks
        });
        TryWriteText(Path.Combine(_paths.StateRoot, "task-registry.json"), registry);
    }

    private object BuildQuotaGuard(HudSnapshot? snapshot)
    {
        if (!_settings.QuotaGuard.Enabled)
        {
            _previousQuotaGuardState = "disabled";
            _quotaGuardObserved = false;
            return new
            {
                state = "disabled",
                @event = "disabled",
                should_alert = false,
                five_hour_remaining_percent = snapshot?.FiveHourRemainingPercent,
                weekly_remaining_percent = snapshot?.WeeklyRemainingPercent,
                observed_at = snapshot?.AllowanceTimestamp?.ToString("O") ?? string.Empty,
                instruction = "HUD allowance handoff protection is off in Settings. Do not activate a quota-based handoff."
            };
        }

        var fiveHour = snapshot?.FiveHourRemainingPercent;
        var weekly = snapshot?.WeeklyRemainingPercent;
        if (!fiveHour.HasValue && !weekly.HasValue)
        {
            _previousQuotaGuardState = "unavailable";
            _quotaGuardObserved = false;
            return new
            {
                state = "unavailable",
                @event = "unavailable",
                should_alert = false,
                five_hour_remaining_percent = (double?)null,
                weekly_remaining_percent = (double?)null,
                observed_at = string.Empty,
                instruction = "No locally observed Codex allowance is available. Do not guess a limit or interrupt work."
            };
        }

        var prepareFiveHour = _settings.QuotaGuard.PrepareFiveHourPercent;
        var prepareWeekly = _settings.QuotaGuard.PrepareWeeklyPercent;
        var handoffFiveHour = _settings.QuotaGuard.HandoffFiveHourPercent;
        var handoffWeekly = _settings.QuotaGuard.HandoffWeeklyPercent;
        var state = (fiveHour.HasValue && fiveHour.Value <= handoffFiveHour) || (weekly.HasValue && weekly.Value <= handoffWeekly)
            ? "handoff_now"
            : (fiveHour.HasValue && fiveHour.Value <= prepareFiveHour) || (weekly.HasValue && weekly.Value <= prepareWeekly)
                ? "prepare_handoff"
                : "clear";
        var previous = _previousQuotaGuardState;
        var eventName = "steady";
        var shouldAlert = false;
        if (!_quotaGuardObserved)
        {
            eventName = state switch
            {
                "prepare_handoff" => "entered_prepare",
                "handoff_now" => "entered_handoff",
                _ => "clear"
            };
            shouldAlert = state is "prepare_handoff" or "handoff_now";
        }
        else if (state != previous)
        {
            if (state == "handoff_now" && previous == "prepare_handoff")
            {
                eventName = "escalated_handoff";
                shouldAlert = true;
            }
            else if (state is "prepare_handoff" or "handoff_now")
            {
                eventName = state == "handoff_now" ? "entered_handoff" : "entered_prepare";
                shouldAlert = true;
            }
            else if (state == "clear")
            {
                eventName = "recovered";
            }
            else
            {
                eventName = "deescalated";
            }
        }
        _previousQuotaGuardState = state;
        _quotaGuardObserved = true;
        var instruction = state switch
        {
            "handoff_now" => ResolveQuotaInstruction(_settings.QuotaGuard.HandoffInstruction, "quotaGuardHandoffDefault"),
            "prepare_handoff" => ResolveQuotaInstruction(_settings.QuotaGuard.PrepareInstruction, "quotaGuardPrepareDefault"),
            _ => "Observed allowance is above the conservative handoff threshold. Continue normally, but check again before an expensive or broad step."
        };
        return new
        {
            state,
            @event = eventName,
            should_alert = shouldAlert,
            five_hour_remaining_percent = fiveHour,
            weekly_remaining_percent = weekly,
            observed_at = snapshot?.AllowanceTimestamp?.ToString("O") ?? string.Empty,
            instruction
        };
    }

    private string ResolveQuotaInstruction(string customInstruction, string localeKey) =>
        string.IsNullOrWhiteSpace(customInstruction) ? Get(_settingsLocale, localeKey) : customInstruction;

    private bool HasActiveHost(DateTimeOffset now)
    {
        try
        {
            if (Directory.Exists(_hostsRoot))
            {
                var cutoff = now.UtcDateTime.AddSeconds(-8);
                foreach (var path in Directory.EnumerateFiles(_hostsRoot, "*.heartbeat"))
                {
                    if (File.GetLastWriteTimeUtc(path) >= cutoff)
                    {
                        return true;
                    }
                    TryDelete(path);
                }
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
        if (_arguments.ParentPid <= 0)
        {
            return false;
        }
        try
        {
            using var process = Process.GetProcessById(_arguments.ParentPid);
            return !process.HasExited;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    private bool ConsumeSignal(string name)
    {
        var path = Path.Combine(_paths.StateRoot, name);
        if (!File.Exists(path))
        {
            return false;
        }
        TryDelete(path);
        return true;
    }

    private void Stop()
    {
        _timer.Stop();
        _application.Shutdown();
    }

    private void StopByUser()
    {
        TryWriteText(Path.Combine(_paths.StateRoot, "manual-exit.signal"), DateTime.UtcNow.ToString("O"));
        Stop();
    }

    private void TryWriteText(string path, string content)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var temporary = path + ".tmp";
            File.WriteAllText(temporary, content, new UTF8Encoding(false));
            File.Move(temporary, path, overwrite: true);
        }
        catch (IOException exception)
        {
            _log.Write("State write failed: " + exception.Message);
        }
        catch (UnauthorizedAccessException exception)
        {
            _log.Write("State write denied: " + exception.Message);
        }
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static string Get(IReadOnlyDictionary<string, string> locale, string key) =>
        locale.TryGetValue(key, out var value) ? value : key;

    private static AgentAnimationRecipe? ParseAgentAnimationRecipe(JsonElement node, string fallbackColor)
    {
        if (node.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var allowedLayers = new HashSet<string>(new[] { "glow", "pulse", "breathe", "flow" }, StringComparer.Ordinal);
        var layers = node.TryGetProperty("layers", out var layersNode) && layersNode.ValueKind == JsonValueKind.Array
            ? layersNode.EnumerateArray()
                .Where(static item => item.ValueKind == JsonValueKind.String)
                .Select(static item => item.GetString() ?? string.Empty)
                .Where(allowedLayers.Contains)
                .Distinct(StringComparer.Ordinal)
                .Take(4)
                .ToArray()
            : Array.Empty<string>();
        if (layers.Length == 0)
        {
            return null;
        }

        var color = node.TryGetProperty("color", out var colorNode) && colorNode.ValueKind == JsonValueKind.String
            ? colorNode.GetString() ?? fallbackColor
            : fallbackColor;
        if (!Regex.IsMatch(color, "^#[0-9A-Fa-f]{8}$", RegexOptions.CultureInvariant))
        {
            color = fallbackColor;
        }

        return new AgentAnimationRecipe(
            layers,
            color,
            ReadBoundedDouble(node, "intensity", 0.70, 0.20, 1.00),
            (int)Math.Round(ReadBoundedDouble(node, "tempo_ms", 720, 240, 2500)),
            (int)Math.Round(ReadBoundedDouble(node, "cycles", 3, 1, 8)),
            ReadBoundedDouble(node, "glow_radius", 30, 8, 60),
            ReadBoundedDouble(node, "scale", 1.028, 1, 1.08),
            node.TryGetProperty("direction", out var directionNode) && directionNode.GetString() == "right-to-left"
                ? "right-to-left"
                : "left-to-right");
    }

    private static double ReadBoundedDouble(JsonElement node, string name, double fallback, double minimum, double maximum)
    {
        var value = node.TryGetProperty(name, out var property) && property.TryGetDouble(out var candidate)
            ? candidate
            : fallback;
        return double.IsFinite(value) ? Math.Clamp(value, minimum, maximum) : fallback;
    }

    [GeneratedRegex("[\\x00-\\x1F\\x7F]+", RegexOptions.CultureInvariant)]
    private static partial Regex ControlRegex();

    [GeneratedRegex("\\s+", RegexOptions.CultureInvariant)]
    private static partial Regex WhitespaceRegex();
}
