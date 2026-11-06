using Avalonia.Controls;
using Avalonia.Interactivity;
using DicomTestTool.ViewModels;

namespace DicomTestTool.Controls;

public partial class NodePicker : UserControl
{
    public NodePicker()
    {
        InitializeComponent();
        DataContext = AppState.Shared;
    }

    private void OnEdit(object? sender, RoutedEventArgs e) => AppState.Shared.Section = AppSection.Nodes;
}
