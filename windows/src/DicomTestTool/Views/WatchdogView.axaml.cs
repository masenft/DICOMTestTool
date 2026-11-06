using Avalonia.Controls;
using Avalonia.Interactivity;
using DicomTestTool.ViewModels;

namespace DicomTestTool.Views;

public partial class WatchdogView : UserControl
{
    private readonly AppState _state = AppState.Shared;

    public WatchdogView()
    {
        InitializeComponent();
        DataContext = _state;
        Grid.ItemsSource = _state.Nodes;
    }

    private void OnStart(object? sender, RoutedEventArgs e)
    {
        if (!_state.Nodes.Any(n => n.Watched))
        {
            _state.Append("Watchdog", "Bitte mindestens einen Knoten zum Überwachen anhaken", error: true);
            return;
        }
        foreach (var n in _state.Nodes) n.ResetWatch();
        _state.StartWatchdog();
    }

    private void OnStop(object? sender, RoutedEventArgs e) => _state.StopWatchdog();
}
