using System.Collections.Specialized;
using System.Globalization;
using Avalonia.Controls;
using Avalonia.Data.Converters;
using Avalonia.Interactivity;
using Avalonia.Threading;
using DicomTestTool.Core;
using DicomTestTool.ViewModels;

namespace DicomTestTool.Controls;

public sealed class LogLineConverter : IValueConverter
{
    public static readonly LogLineConverter Instance = new();
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is LogEntry e ? $"{e.Date:HH:mm:ss.fff}  [{e.Source}]  {e.Text}" : "";
    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}

public partial class LogView : UserControl
{
    private readonly AppState _state = AppState.Shared;

    public LogView()
    {
        InitializeComponent();
        Lines.ItemsSource = _state.Log;
        _state.Log.CollectionChanged += OnLogChanged;
    }

    private void OnLogChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (e.Action != NotifyCollectionChangedAction.Add || _state.Log.Count == 0) return;
        Dispatcher.UIThread.Post(() => Lines.ScrollIntoView(_state.Log.Count - 1), DispatcherPriority.Background);
    }

    private async void OnCopy(object? sender, RoutedEventArgs e)
    {
        var selected = Lines.SelectedItems?.OfType<LogEntry>().ToList();
        var text = selected is { Count: > 0 } ? string.Join(Environment.NewLine, selected.Select(l => l.Line)) : _state.LogText();
        await Ui.CopyAsync(this, text);
    }

    private async void OnExport(object? sender, RoutedEventArgs e)
    {
        var path = await Ui.SaveFileAsync(this, $"DICOM-Protokoll_{DateTime.Now:yyyy-MM-dd_HH-mm}.txt", "Textdatei", "txt");
        if (path == null) return;
        try
        {
            await File.WriteAllTextAsync(path, _state.LogText());
            _state.Append("App", "Protokoll exportiert: " + path);
        }
        catch (Exception ex)
        {
            _state.Append("App", "Export fehlgeschlagen: " + ex.Message, error: true);
        }
    }

    private void OnClear(object? sender, RoutedEventArgs e) => _state.Log.Clear();
}
