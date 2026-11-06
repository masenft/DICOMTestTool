using Avalonia.Controls;
using Avalonia.Interactivity;
using DicomTestTool.Core;
using DicomTestTool.ViewModels;

namespace DicomTestTool.Views;

public partial class NodesView : UserControl
{
    private readonly AppState _state = AppState.Shared;

    public NodesView()
    {
        InitializeComponent();
        DataContext = _state;
    }

    private NodeItem? Selected => Grid.SelectedItem as NodeItem;

    private void OnAdd(object? sender, RoutedEventArgs e)
    {
        var n = _state.AddNode(new DicomNode { Name = "Neuer Knoten", AeTitle = "ANY-SCP", Host = "192.168.1.10", Port = 104 });
        Grid.SelectedItem = n;
        Grid.ScrollIntoView(n, null);
    }

    private void OnDuplicate(object? sender, RoutedEventArgs e)
    {
        if (Selected is not { } s) return;
        var copy = s.ToNode();
        copy.Id = Guid.NewGuid();
        copy.Name += " (Kopie)";
        Grid.SelectedItem = _state.AddNode(copy);
    }

    private void OnDelete(object? sender, RoutedEventArgs e)
    {
        if (Selected is not { } s) return;
        if (_state.SelectedNode == s) _state.SelectedNode = null;
        _state.Nodes.Remove(s);
        _state.SelectedNode ??= _state.Nodes.FirstOrDefault();
    }

    private async void OnEcho(object? sender, RoutedEventArgs e)
    {
        if (Selected is not { } s) return;
        _state.SelectedNode = s;
        try
        {
            var r = await DicomScu.EchoAsync(s.ToNode(), _state.ScuSettings, _state.Logger("Echo"));
            _state.Append("Echo", $"{s.Name}: {DicomNames.Status(r.Status)} ({r.TotalTime.TotalMilliseconds:0} ms)", r.Status != 0);
        }
        catch (Exception ex)
        {
            _state.Append("Echo", $"{s.Name}: {DicomErrors.Describe(ex)}", error: true);
        }
    }
}
