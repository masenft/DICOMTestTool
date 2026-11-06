using System.Collections.ObjectModel;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using DicomTestTool.Core;
using DicomTestTool.Services;

namespace DicomTestTool.ViewModels;

public enum AppSection { Nodes, Echo, Store, Find, Worklist, Scp, Watchdog, Viewer, General, About }

/// <summary>Central app state: settings, nodes, protocol, Storage SCP and watchdog.</summary>
public sealed partial class AppState : ObservableObject
{
    public static AppState Shared { get; } = new();

    public AppSettings Settings { get; private set; }
    public ObservableCollection<NodeItem> Nodes { get; } = [];
    public ObservableCollection<LogEntry> Log { get; } = [];
    public ObservableCollection<ReceivedRow> Received { get; } = [];
    public UpdateService Updater { get; }

    [ObservableProperty] private AppSection _section = AppSection.Echo;
    [ObservableProperty] private NodeItem? _selectedNode;
    [ObservableProperty] private bool _scpRunning;
    [ObservableProperty] private bool _watchRunning;
    [ObservableProperty] private bool _watchHasFailure;
    [ObservableProperty] private string _notificationPermission = "";

    /// <summary>Hand-over between tools (SCP/Store → Viewer, Viewer → Store).</summary>
    public event Action<string>? ViewerFileRequested;
    public event Action<IReadOnlyList<string>>? StoreFilesRequested;
    public event Action? NodesChanged;

    private StorageScp? _scp;
    private CancellationTokenSource? _watchCts;
    private bool _loading;
    private readonly Timer _saveTimer;

    private AppState()
    {
        Settings = SettingsStore.Load();
        _saveTimer = new Timer(_ => { try { SettingsStore.Save(Settings); } catch { } }, null, Timeout.Infinite, Timeout.Infinite);
        Updater = new UpdateService(this);
        LoadNodes();
        Nodes.CollectionChanged += (_, _) => { SaveNodes(); NodesChanged?.Invoke(); };
    }

    private void LoadNodes()
    {
        _loading = true;
        Nodes.Clear();
        foreach (var n in Settings.Nodes)
        {
            var item = NodeItem.From(n);
            item.Watched = Settings.WatchNodeIds.Contains(n.Id);
            Attach(item);
            Nodes.Add(item);
        }
        SelectedNode = Nodes.FirstOrDefault();
        _loading = false;
    }

    private void Attach(NodeItem item) => item.Changed += () => { SaveNodes(); NodesChanged?.Invoke(); };

    public NodeItem AddNode(DicomNode n)
    {
        var item = NodeItem.From(n);
        Attach(item);
        Nodes.Add(item);
        return item;
    }

    private void SaveNodes()
    {
        if (_loading) return;
        Settings.Nodes = Nodes.Select(n => n.ToNode()).ToList();
        Settings.WatchNodeIds = Nodes.Where(n => n.Watched).Select(n => n.Id).ToList();
        SaveSettings();
    }

    /// <summary>Saves shortly after the last change (typing in a field writes once).</summary>
    public void SaveSettings()
    {
        if (_loading) return;
        _saveTimer.Change(400, Timeout.Infinite);
    }

    public void FlushSettings()
    {
        _saveTimer.Change(Timeout.Infinite, Timeout.Infinite);
        try { SettingsStore.Save(Settings); } catch { }
    }

    public ScuSettings ScuSettings => new(Settings.CallingAe, Settings.Timeout);

    // MARK: Simple settings exposed for binding

    public string CallingAe { get => Settings.CallingAe; set { Settings.CallingAe = value.Trim(); SaveSettings(); OnPropertyChanged(); } }
    public double TimeoutSeconds { get => Settings.Timeout; set { Settings.Timeout = Math.Clamp(value, 1, 600); SaveSettings(); OnPropertyChanged(); } }
    public string ScpAe { get => Settings.ScpAe; set { Settings.ScpAe = value.Trim(); SaveSettings(); OnPropertyChanged(); } }
    public int ScpPort { get => Settings.ScpPort; set { Settings.ScpPort = value; SaveSettings(); OnPropertyChanged(); } }
    public bool ScpAcceptAnyAe { get => Settings.ScpAcceptAnyAe; set { Settings.ScpAcceptAnyAe = value; SaveSettings(); OnPropertyChanged(); } }
    public string ScpDirectory { get => Settings.ScpDirectory; set { Settings.ScpDirectory = value; SaveSettings(); OnPropertyChanged(); } }
    public double WatchInterval { get => Settings.WatchInterval; set { Settings.WatchInterval = Math.Max(5, value); SaveSettings(); OnPropertyChanged(); } }
    public bool NotificationsEnabled { get => Settings.NotificationsEnabled; set { Settings.NotificationsEnabled = value; SaveSettings(); OnPropertyChanged(); } }
    public bool NotifyWatchdog { get => Settings.NotifyWatchdog; set { Settings.NotifyWatchdog = value; SaveSettings(); OnPropertyChanged(); } }
    public bool NotifyScp { get => Settings.NotifyScp; set { Settings.NotifyScp = value; SaveSettings(); OnPropertyChanged(); } }
    public bool AutoStartScp { get => Settings.AutoStartScp; set { Settings.AutoStartScp = value; SaveSettings(); OnPropertyChanged(); } }
    public bool AutoStartWatchdog { get => Settings.AutoStartWatchdog; set { Settings.AutoStartWatchdog = value; SaveSettings(); OnPropertyChanged(); } }
    public bool KeepRunningInTray { get => Settings.KeepRunningInTray; set { Settings.KeepRunningInTray = value; SaveSettings(); OnPropertyChanged(); } }

    public bool ShowTrayIcon
    {
        get => Settings.ShowTrayIcon;
        set { Settings.ShowTrayIcon = value; SaveSettings(); OnPropertyChanged(); TrayVisibilityChanged?.Invoke(value); }
    }
    public event Action<bool>? TrayVisibilityChanged;

    public string Theme
    {
        get => Settings.Theme;
        set { Settings.Theme = value; SaveSettings(); OnPropertyChanged(); OnPropertyChanged(nameof(IsClinicalDark)); OnPropertyChanged(nameof(IsStandardTheme)); ThemeService.Apply(value); }
    }
    public bool IsStandardTheme { get => Theme != "clinicalDark"; set { if (value) Theme = "standard"; } }
    public bool IsClinicalDark { get => Theme == "clinicalDark"; set { if (value) Theme = "clinicalDark"; } }

    public bool LaunchAtLogin
    {
        get => Autostart.IsEnabled;
        set
        {
            try
            {
                if (value) Autostart.Enable(); else Autostart.Disable();
                Append("App", value ? "Start bei Anmeldung aktiviert" : "Start bei Anmeldung deaktiviert");
            }
            catch (Exception e)
            {
                Append("App", "Start bei Anmeldung: " + e.Message, error: true);
            }
            OnPropertyChanged();
            OnPropertyChanged(nameof(LaunchAtLoginStatus));
        }
    }
    public string LaunchAtLoginStatus => Autostart.Status;
    public bool IsWindows => OperatingSystem.IsWindows();

    // MARK: Lifecycle

    public void DidFinishLaunching()
    {
        FileLogger.PruneOldFiles();
        Append("App", $"{AppInfo.Name} {AppInfo.Version} gestartet");
        RefreshNotificationPermission();
        if (Settings.AutoStartScp) StartScp();
        if (Settings.AutoStartWatchdog && Nodes.Any(n => n.Watched)) StartWatchdog();
        Updater.StartAutomaticChecks();
    }

    public void PrepareForShutdown()
    {
        StopScp();
        StopWatchdog();
        FlushSettings();
        FileLogger.Write(new LogEntry(DateTime.Now, "App", "Beendet", false));
    }

    public void ResetToDefaults()
    {
        StopScp();
        StopWatchdog();
        if (Autostart.IsEnabled) Autostart.Disable();
        SettingsStore.Delete();
        Settings = new AppSettings();
        LoadNodes();
        SaveNodes();
        FlushSettings();
        Received.Clear();
        foreach (var p in typeof(AppState).GetProperties()) OnPropertyChanged(p.Name);
        ThemeService.Apply(Settings.Theme);
        TrayVisibilityChanged?.Invoke(Settings.ShowTrayIcon);
        NodesChanged?.Invoke();
        Append("App", "Alle Einstellungen wurden auf Standard zurückgesetzt");
    }

    // MARK: Protocol

    public void Append(string source, string text, bool error = false)
    {
        var entry = new LogEntry(DateTime.Now, source, text, error);
        FileLogger.Write(entry);
        void Add()
        {
            Log.Add(entry);
            if (Log.Count > 5000) for (var i = Log.Count - 5000; i > 0; i--) Log.RemoveAt(0);
        }
        if (Dispatcher.UIThread.CheckAccess()) Add(); else Dispatcher.UIThread.Post(Add);
    }

    public LogHandler Logger(string source) => msg => Append(source, msg);

    public string LogText() => string.Join(Environment.NewLine, Log.Select(e => e.Line)) + Environment.NewLine;

    // MARK: Navigation and hand-over

    public void OpenInViewer(string path)
    {
        Section = AppSection.Viewer;
        ViewerFileRequested?.Invoke(path);
    }

    public void SendWithStore(IReadOnlyList<string> paths)
    {
        Section = AppSection.Store;
        StoreFilesRequested?.Invoke(paths);
    }

    // MARK: Quick echo (tray)

    public async Task QuickEchoAsync(NodeItem node)
    {
        try
        {
            var r = await DicomScu.EchoAsync(node.ToNode(), ScuSettings, Logger("Echo"));
            var msg = $"{node.Name}: {DicomNames.Status(r.Status)} ({r.TotalTime.TotalMilliseconds:0} ms)";
            Append("Echo", msg, error: r.Status != 0);
            Notify(r.Status == 0 ? "Echo erfolgreich" : "Echo fehlgeschlagen", msg, force: true);
        }
        catch (Exception e)
        {
            var msg = $"{node.Name}: {DicomErrors.Describe(e)}";
            Append("Echo", msg, error: true);
            Notify("Echo fehlgeschlagen", msg, force: true);
        }
    }

    // MARK: Storage SCP

    public void StartScp()
    {
        if (ScpRunning) return;
        var scp = new StorageScp(ScpAe, ScpPort, ScpDirectory, ScpAcceptAnyAe)
        {
            Log = Logger("SCP"),
            OnReceived = obj => Dispatcher.UIThread.Post(() =>
            {
                Received.Insert(0, new ReceivedRow(obj));
                if (Received.Count > 10000) Received.RemoveAt(Received.Count - 1);
                if (NotifyScp) Notify("DICOM empfangen", $"{DicomNames.FormatPN(obj.PatientName)} [{obj.PatientId}] von {obj.CallingAe}");
            }),
        };
        try
        {
            scp.Start();
            _scp = scp;
            ScpRunning = true;
        }
        catch (Exception e)
        {
            Append("SCP", "Start fehlgeschlagen: " + DicomErrors.Describe(e), error: true);
        }
    }

    public void StopScp()
    {
        _scp?.Stop();
        _scp = null;
        ScpRunning = false;
    }

    // MARK: Watchdog

    public string WatchSummary
    {
        get
        {
            var watched = Nodes.Where(n => n.Watched).ToList();
            return $"{watched.Count(n => n.WatchOk == true)}/{watched.Count} erreichbar";
        }
    }

    public void StartWatchdog()
    {
        if (WatchRunning) return;
        WatchRunning = true;
        WatchHasFailure = false;
        Append("Watchdog", $"Überwachung gestartet ({(int)WatchInterval} s)");
        var cts = _watchCts = new CancellationTokenSource();
        _ = Task.Run(async () =>
        {
            while (!cts.IsCancellationRequested)
            {
                var targets = await Dispatcher.UIThread.InvokeAsync(() => Nodes.Where(n => n.Watched).Select(n => (Item: n, Node: n.ToNode())).ToList());
                var settings = ScuSettings;
                await Task.WhenAll(targets.Select(async t =>
                {
                    bool ok; double? ms = null; string msg;
                    try
                    {
                        var r = await DicomScu.EchoAsync(t.Node, settings, ct: cts.Token);
                        ok = r.Status == 0; ms = r.TotalTime.TotalMilliseconds; msg = DicomNames.Status(r.Status);
                    }
                    catch (OperationCanceledException) { return; }
                    catch (Exception e) { ok = false; msg = DicomErrors.Describe(e); }
                    await Dispatcher.UIThread.InvokeAsync(() => UpdateWatch(t.Item, ok, ms, msg));
                }));
                try { await Task.Delay(TimeSpan.FromSeconds(Math.Max(5, WatchInterval)), cts.Token); } catch (OperationCanceledException) { }
            }
        });
    }

    public void StopWatchdog()
    {
        if (!WatchRunning) return;
        _watchCts?.Cancel();
        _watchCts = null;
        WatchRunning = false;
        WatchHasFailure = false;
        Append("Watchdog", "Überwachung gestoppt");
    }

    private void UpdateWatch(NodeItem n, bool ok, double? ms, string msg)
    {
        if (!WatchRunning) return;
        var previous = n.WatchOk;
        n.WatchOk = ok;
        n.LastCheck = DateTime.Now.ToString("dd.MM. HH:mm:ss");
        n.Latency = ms is { } v ? $"{v:0} ms" : "";
        n.Failures = ok ? 0 : n.Failures + 1;
        n.Message = msg;
        WatchHasFailure = Nodes.Any(x => x.Watched && x.WatchOk == false);
        OnPropertyChanged(nameof(WatchSummary));
        if (previous != ok)
        {
            Append("Watchdog", ok ? $"{n.Name} erreichbar" : $"{n.Name} NICHT erreichbar: {msg}", error: !ok);
            if ((previous != null || !ok) && NotifyWatchdog)
                Notify(ok ? "DICOM-Knoten wieder erreichbar" : "DICOM-Knoten nicht erreichbar", $"{n.Name}: {msg}");
        }
    }

    // MARK: Notifications

    /// <summary><paramref name="force"/> bypasses the global switch for notifications the user explicitly triggered (tray echo).</summary>
    public void Notify(string title, string body, bool force = false)
    {
        if (!NotificationsEnabled && !force) return;
        if (!Notifier.IsSupported) return;
        var error = Notifier.Show(title, body);
        if (error.Length > 0) Append("App", "Benachrichtigung konnte nicht angezeigt werden: " + error, error: true);
    }

    public void SendTestNotification()
    {
        if (!Notifier.IsSupported) { Append("App", "Benachrichtigungen gibt es nur unter Windows", error: true); return; }
        Notify(AppInfo.Name, "So sehen Popup-Hinweise aus, z. B. wenn der Watchdog einen Ausfall meldet.", force: true);
        Append("App", "Test-Benachrichtigung gesendet");
        RefreshNotificationPermission();
    }

    public void RefreshNotificationPermission() => NotificationPermission = Notifier.PermissionText;
}
