using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Threading;
using DicomTestTool.Core;
using DicomTestTool.Services;
using DicomTestTool.ViewModels;
using DicomTestTool.Views;

namespace DicomTestTool;

public partial class App : Application
{
    private MainWindow? _window;
    private IClassicDesktopStyleApplicationLifetime? _desktop;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            _desktop = desktop;
            var state = AppState.Shared;
            ThemeService.Apply(state.Theme);
            DicomSetup.Initialize();

            var startHidden = desktop.Args?.Contains("--autostart") == true && state.ShowTrayIcon && state.KeepRunningInTray;
            _window = new MainWindow();
            desktop.MainWindow = _window;
            if (!startHidden) _window.Show();

            SetupTray(state);
            state.NodesChanged += () => Dispatcher.UIThread.Post(() => SetupTray(state));
            state.TrayVisibilityChanged += _ => Dispatcher.UIThread.Post(() => SetupTray(state));
            state.PropertyChanged += (_, e) =>
            {
                if (e.PropertyName is nameof(AppState.ScpRunning) or nameof(AppState.WatchRunning)) Dispatcher.UIThread.Post(() => SetupTray(state));
            };
            SingleInstance.ListenForShowRequests(() => Dispatcher.UIThread.Post(() => ShowMain()));
            desktop.ShutdownRequested += (_, _) => state.PrepareForShutdown();
            state.DidFinishLaunching();
        }
        base.OnFrameworkInitializationCompleted();
    }

    public void ShowMain(AppSection? section = null)
    {
        if (_window == null) return;
        if (section is { } s) AppState.Shared.Section = s;
        _window.Show();
        if (_window.WindowState == WindowState.Minimized) _window.WindowState = WindowState.Normal;
        _window.Activate();
        _window.Topmost = true;
        _window.Topmost = false;
    }

    public void Quit()
    {
        AppState.Shared.PrepareForShutdown();
        _desktop?.Shutdown();
    }

    private void SetupTray(AppState state)
    {
        var icons = TrayIcon.GetIcons(this);
        if (icons == null || icons.Count == 0) return;
        var tray = icons[0];
        tray.IsVisible = state.ShowTrayIcon;
        tray.Clicked -= OnTrayClicked;
        tray.Clicked += OnTrayClicked;

        var menu = new NativeMenu();
        menu.Add(new NativeMenuItem($"{AppInfo.Name} {AppInfo.Version}") { IsEnabled = false });
        menu.Add(new NativeMenuItemSeparator());
        menu.Add(Item(state.ScpRunning ? $"Storage SCP stoppen (Port {state.ScpPort})" : "Storage SCP starten",
            () => { if (state.ScpRunning) state.StopScp(); else state.StartScp(); }));
        menu.Add(Item(state.WatchRunning ? $"Watchdog stoppen ({state.WatchSummary})" : "Watchdog starten",
            () => { if (state.WatchRunning) state.StopWatchdog(); else state.StartWatchdog(); }, enabled: state.WatchRunning || state.Nodes.Any(n => n.Watched)));
        var echo = new NativeMenuItem("Echo senden an") { Menu = new NativeMenu() };
        if (state.Nodes.Count == 0) echo.Menu.Add(new NativeMenuItem("Keine Knoten angelegt") { IsEnabled = false });
        foreach (var n in state.Nodes)
        {
            var node = n;
            echo.Menu.Add(Item($"{node.Name}  ({node.Summary})", () => _ = state.QuickEchoAsync(node)));
        }
        menu.Add(echo);
        menu.Add(new NativeMenuItemSeparator());
        foreach (var (title, section) in new[]
                 {
                     ("Knoten & Einstellungen", AppSection.Nodes), ("Echo", AppSection.Echo), ("Store (Senden)", AppSection.Store),
                     ("Query / Retrieve", AppSection.Find), ("Worklist", AppSection.Worklist), ("Storage SCP", AppSection.Scp),
                     ("Watchdog", AppSection.Watchdog), ("Viewer / Tag-Dump", AppSection.Viewer),
                 })
            menu.Add(Item(title + " …", () => ShowMain(section)));
        menu.Add(new NativeMenuItemSeparator());
        menu.Add(Item("Allgemein …", () => ShowMain(AppSection.General)));
        menu.Add(Item("Nach Updates suchen …", () => { ShowMain(AppSection.About); _ = state.Updater.CheckAsync(userInitiated: true); }));
        menu.Add(new NativeMenuItemSeparator());
        menu.Add(Item($"{AppInfo.Name} beenden", Quit));
        tray.Menu = menu;
    }

    private void OnTrayClicked(object? sender, EventArgs e) => ShowMain();

    private static NativeMenuItem Item(string title, Action action, bool enabled = true)
    {
        var item = new NativeMenuItem(title) { IsEnabled = enabled };
        item.Click += (_, _) => action();
        return item;
    }
}
