using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using DicomTestTool.Core;
using DicomTestTool.ViewModels;

namespace DicomTestTool.Views;

public partial class EchoView : UserControl
{
    private readonly AppState _state = AppState.Shared;
    private readonly ObservableCollection<string> _results = [];

    public EchoView()
    {
        InitializeComponent();
        Results.ItemsSource = _results;
    }

    private async void OnSend(object? sender, RoutedEventArgs e)
    {
        if (_state.SelectedNode is not { } item || !SendButton.IsEnabled) return;
        SendButton.IsEnabled = false;
        Busy.IsVisible = Busy.IsIndeterminate = true;
        var node = item.ToNode();
        var n = (int)(Repeat.Value ?? 1);
        var ok = 0;
        for (var i = 1; i <= n; i++)
        {
            string line;
            try
            {
                var r = await DicomScu.EchoAsync(node, _state.ScuSettings, _state.Logger("Echo"));
                if (r.Status == 0) ok++;
                line = $"#{i} {node.AeTitle} – {DicomNames.Status(r.Status)}  (Assoziation {r.AssociationTime.TotalMilliseconds:0} ms, Echo {r.EchoTime.TotalMilliseconds:0} ms, gesamt {r.TotalTime.TotalMilliseconds:0} ms)";
            }
            catch (Exception ex)
            {
                var msg = DicomErrors.Describe(ex);
                line = $"#{i} {node.AeTitle} – FEHLER: {msg}";
                _state.Append("Echo", msg, error: true);
            }
            _results.Insert(0, line);
        }
        if (n > 1) _results.Insert(0, $"Ergebnis: {ok}/{n} erfolgreich");
        Busy.IsVisible = Busy.IsIndeterminate = false;
        SendButton.IsEnabled = true;
    }

    private void OnClear(object? sender, RoutedEventArgs e) => _results.Clear();
}
