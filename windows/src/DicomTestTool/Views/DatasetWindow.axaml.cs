using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using DicomTestTool.Controls;
using DicomTestTool.Core;
using FellowOakDicom;

namespace DicomTestTool.Views;

public partial class DatasetWindow : Window
{
    private readonly List<TagRow> _rows;

    public DatasetWindow() : this(new DicomDataset(), "") { }

    public DatasetWindow(DicomDataset ds, string title)
    {
        InitializeComponent();
        Title = title;
        Heading.Text = title;
        _rows = TagRows.Flatten(ds);
        Grid.ItemsSource = _rows;
        Filter.TextChanged += (_, _) =>
        {
            var f = Filter.Text?.Trim() ?? "";
            Grid.ItemsSource = f.Length == 0 ? _rows : _rows.Where(r => Matches(r, f)).ToList();
        };
    }

    internal static bool Matches(TagRow r, string f) =>
        r.Tag.Contains(f, StringComparison.OrdinalIgnoreCase) || r.Name.Contains(f, StringComparison.OrdinalIgnoreCase) || r.Value.Contains(f, StringComparison.OrdinalIgnoreCase);

    public void ShowFor(Visual anchor)
    {
        if (TopLevel.GetTopLevel(anchor) is Window owner && owner.IsVisible) Show(owner); else Show();
    }

    private async void OnCopy(object? sender, RoutedEventArgs e) => await Ui.CopyAsync(this, TagRows.ToText(_rows));
    private void OnClose(object? sender, RoutedEventArgs e) => Close();
}
