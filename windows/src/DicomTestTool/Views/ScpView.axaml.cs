using System.ComponentModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using DicomTestTool.Controls;
using DicomTestTool.Services;
using DicomTestTool.ViewModels;

namespace DicomTestTool.Views;

public partial class ScpView : UserControl
{
    private readonly AppState _state = AppState.Shared;

    public ScpView()
    {
        InitializeComponent();
        DataContext = _state;
        Grid.ItemsSource = _state.Received;
        _state.PropertyChanged += OnState;
        _state.Received.CollectionChanged += (_, _) => UpdateTexts();
        Grid.DoubleTapped += (_, _) => { if (Grid.SelectedItem is ReceivedRow r) _state.OpenInViewer(r.Path); };
        Grid.ContextRequested += (_, e) =>
        {
            if (Grid.SelectedItem is not ReceivedRow r) return;
            var menu = new ContextMenu();
            var open = new MenuItem { Header = "Im Viewer öffnen" };
            open.Click += (_, _) => _state.OpenInViewer(r.Path);
            var reveal = new MenuItem { Header = "Im Explorer zeigen" };
            reveal.Click += (_, _) => Shell.RevealFile(r.Path);
            var send = new MenuItem { Header = "Weitersenden (Store) …" };
            send.Click += (_, _) => _state.SendWithStore([r.Path]);
            menu.Items.Add(open);
            menu.Items.Add(reveal);
            menu.Items.Add(send);
            menu.Open(Grid);
            e.Handled = true;
        };
        UpdateTexts();
    }

    private void OnState(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppState.ScpRunning) or nameof(AppState.ScpPort) or nameof(AppState.ScpAe)) UpdateTexts();
    }

    private void UpdateTexts()
    {
        CountText.Text = $"{_state.Received.Count} empfangen";
        RunningText.Text = $"Läuft auf Port {_state.ScpPort} als {_state.ScpAe}";
    }

    private void OnStart(object? sender, RoutedEventArgs e) => _state.StartScp();
    private void OnStop(object? sender, RoutedEventArgs e) => _state.StopScp();
    private void OnOpenFolder(object? sender, RoutedEventArgs e) => Shell.OpenFolder(_state.ScpDirectory);
    private void OnClear(object? sender, RoutedEventArgs e) => _state.Received.Clear();

    private async void OnChooseFolder(object? sender, RoutedEventArgs e)
    {
        if (await Ui.OpenFolderAsync(this, "Speicherordner für empfangene DICOM-Dateien") is { } d) _state.ScpDirectory = d;
    }

    private async void OnCopyFirewall(object? sender, RoutedEventArgs e)
    {
        var exe = Environment.ProcessPath ?? "DICOMTestTool.exe";
        var cmd = $"netsh advfirewall firewall add rule name=\"DICOM Test Tool SCP\" dir=in action=allow protocol=TCP localport={_state.ScpPort} program=\"{exe}\" profile=private,domain";
        await Ui.CopyAsync(this, cmd);
        _state.Append("SCP", "Firewall-Befehl in die Zwischenablage kopiert (in einer Eingabeaufforderung „Als Administrator ausführen“ einfügen): " + cmd);
    }
}
