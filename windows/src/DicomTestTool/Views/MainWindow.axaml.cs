using System.ComponentModel;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using Avalonia.Layout;
using Avalonia.Media;
using CommunityToolkit.Mvvm.ComponentModel;
using DicomTestTool.ViewModels;

namespace DicomTestTool.Views;

public sealed partial class SidebarEntry(AppSection section, string title, string glyph) : ObservableObject
{
    public AppSection Section { get; } = section;
    public string Title { get; } = title;
    public string Glyph { get; } = glyph;
    [ObservableProperty] private bool _showDot;
    [ObservableProperty] private IBrush _dotBrush = Brushes.LimeGreen;
    [ObservableProperty] private bool _showBadge;
}

public partial class MainWindow : Window
{
    private readonly AppState _state = AppState.Shared;
    private readonly Dictionary<AppSection, Control> _views = [];
    private readonly List<SidebarEntry> _tools =
    [
        new(AppSection.Nodes, "Knoten & Einstellungen", ""),
        new(AppSection.Echo, "Echo (Verification)", ""),
        new(AppSection.Store, "Store (Senden)", ""),
        new(AppSection.Find, "Query / Retrieve", ""),
        new(AppSection.Worklist, "Worklist", ""),
        new(AppSection.Scp, "Storage SCP (Empfang)", ""),
        new(AppSection.Watchdog, "Watchdog", ""),
        new(AppSection.Viewer, "Viewer / Tag-Dump", ""),
    ];
    private readonly List<SidebarEntry> _app =
    [
        new(AppSection.General, "Allgemein", ""),
        new(AppSection.About, "Über", ""),
    ];
    private bool _syncing;
    private ReleaseNotesWindow? _releaseWindow;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = _state;
        ToolList.ItemTemplate = EntryTemplate();
        AppList.ItemTemplate = EntryTemplate();
        ToolList.ItemsSource = _tools;
        AppList.ItemsSource = _app;
        ToolList.SelectionChanged += (_, _) => OnListSelection(ToolList, AppList);
        AppList.SelectionChanged += (_, _) => OnListSelection(AppList, ToolList);
        _state.PropertyChanged += OnStateChanged;
        _state.Updater.PropertyChanged += OnUpdaterChanged;
        ShowSection(_state.Section);
        UpdateDots();
    }

    /// <summary>Sidebar row built in code without reflection bindings (safe for trimmed builds).</summary>
    private static FuncDataTemplate<SidebarEntry> EntryTemplate() => new((e, _) =>
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("26,*,Auto"), Margin = new Thickness(2, 3) };
        if (e == null) return grid;
        grid.Children.Add(new TextBlock { Text = e.Glyph, Classes = { "icon" }, Foreground = (IBrush?)Application.Current!.FindResource("SystemControlForegroundAccentBrush") ?? Brushes.DodgerBlue });
        var title = new TextBlock { Text = e.Title, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        Grid.SetColumn(title, 1);
        grid.Children.Add(title);
        var dot = new Avalonia.Controls.Shapes.Ellipse { Width = 8, Height = 8, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 2, 0) };
        Grid.SetColumn(dot, 2);
        grid.Children.Add(dot);
        var badge = new Border
        {
            Background = Brushes.DodgerBlue, CornerRadius = new CornerRadius(8), Padding = new Thickness(6, 1),
            Child = new TextBlock { Text = "neu", Foreground = Brushes.White, FontSize = 11, FontWeight = FontWeight.Bold },
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(badge, 2);
        grid.Children.Add(badge);
        void Sync()
        {
            dot.IsVisible = e.ShowDot;
            dot.Fill = e.DotBrush;
            badge.IsVisible = e.ShowBadge;
        }
        Sync();
        e.PropertyChanged += (_, _) => Sync();
        return grid;
    }, supportsRecycling: false);

    private void OnListSelection(ListBox source, ListBox other)
    {
        if (_syncing || source.SelectedItem is not SidebarEntry e) return;
        _syncing = true;
        other.SelectedItem = null;
        _syncing = false;
        _state.Section = e.Section;
    }

    private void OnStateChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(AppState.Section):
                ShowSection(_state.Section);
                break;
            case nameof(AppState.ScpRunning) or nameof(AppState.WatchRunning) or nameof(AppState.WatchHasFailure):
                UpdateDots();
                break;
        }
    }

    private void OnUpdaterChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(Services.UpdateService.AvailableVersion)) UpdateDots();
        if (e.PropertyName == nameof(Services.UpdateService.ShowReleaseWindow) && _state.Updater.ShowReleaseWindow) ShowReleaseNotes();
    }

    private void ShowReleaseNotes()
    {
        if (_releaseWindow != null) { _releaseWindow.Activate(); return; }
        _releaseWindow = new ReleaseNotesWindow { DataContext = _state.Updater };
        _releaseWindow.Closed += (_, _) => { _releaseWindow = null; _state.Updater.ShowReleaseWindow = false; };
        if (IsVisible) _releaseWindow.Show(this); else _releaseWindow.Show();
    }

    private void UpdateDots()
    {
        var scp = _tools.First(t => t.Section == AppSection.Scp);
        scp.ShowDot = _state.ScpRunning;
        var wd = _tools.First(t => t.Section == AppSection.Watchdog);
        wd.ShowDot = _state.WatchRunning;
        wd.DotBrush = _state.WatchHasFailure ? Brushes.Red : Brushes.LimeGreen;
        _app.First(t => t.Section == AppSection.About).ShowBadge = _state.Updater.AvailableVersion != null;
    }

    private void ShowSection(AppSection s)
    {
        _syncing = true;
        ToolList.SelectedItem = _tools.FirstOrDefault(t => t.Section == s);
        AppList.SelectedItem = _app.FirstOrDefault(t => t.Section == s);
        _syncing = false;
        if (!_views.TryGetValue(s, out var view))
        {
            view = s switch
            {
                AppSection.Nodes => new NodesView(),
                AppSection.Echo => new EchoView(),
                AppSection.Store => new StoreView(),
                AppSection.Find => new FindView(),
                AppSection.Worklist => new WorklistView(),
                AppSection.Scp => new ScpView(),
                AppSection.Watchdog => new WatchdogView(),
                AppSection.Viewer => new ViewerView(),
                AppSection.General => new ScrollViewer { Content = new GeneralView() },
                _ => new ScrollViewer { Content = new AboutView() },
            };
            _views[s] = view;
        }
        ToolHost.Content = view;
        var tool = s is not (AppSection.General or AppSection.About);
        LogPane.IsVisible = tool;
        LogSplitter.IsVisible = tool;
        ContentGrid.RowDefinitions[2].Height = tool ? new GridLength(190) : new GridLength(0);
        Title = $"{_tools.Concat(_app).First(t => t.Section == s).Title} – DICOM Test Tool für Windows";
    }

    protected override void OnClosing(WindowClosingEventArgs e)
    {
        // With the tray icon the app keeps running in the background (SCP, Watchdog).
        if (!e.IsProgrammatic && _state.ShowTrayIcon && _state.KeepRunningInTray)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        if (!e.IsProgrammatic) (Application.Current as App)?.Quit();
        base.OnClosing(e);
    }
}
