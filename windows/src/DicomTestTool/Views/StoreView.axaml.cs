using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using DicomTestTool.Controls;
using DicomTestTool.Core;
using DicomTestTool.ViewModels;

namespace DicomTestTool.Views;

public sealed partial class StoreFileRow(string path) : ObservableObject
{
    public string Path { get; } = path;
    public string FileName => System.IO.Path.GetFileName(Path);
    public string Folder => System.IO.Path.GetDirectoryName(Path) ?? "";
    [ObservableProperty] private string _status = "bereit";
    [ObservableProperty, NotifyPropertyChangedFor(nameof(Symbol), nameof(SymbolBrush))] private bool? _ok;
    public string Symbol => Ok switch { null => "○", true => "✓", false => "✕" };
    public IBrush SymbolBrush => Ok switch { null => Brushes.Gray, true => Brushes.LimeGreen, false => Brushes.Red };
}

public partial class StoreView : UserControl
{
    private readonly AppState _state = AppState.Shared;
    private readonly ObservableCollection<StoreFileRow> _files = [];
    private CancellationTokenSource? _cts;

    public StoreView()
    {
        InitializeComponent();
        Grid.ItemsSource = _files;
        _files.CollectionChanged += (_, _) => UpdateCount();
        AddHandler(DragDrop.DragOverEvent, (_, e) => { e.DragEffects = DragDropEffects.Copy; DropBorder.IsVisible = true; });
        AddHandler(DragDrop.DragLeaveEvent, (_, _) => DropBorder.IsVisible = false);
        AddHandler(DragDrop.DropEvent, (_, e) => { DropBorder.IsVisible = false; Add(Ui.DroppedPaths(e).ToList()); });
        _state.StoreFilesRequested += paths => Dispatcher.UIThread.Post(() => Add(paths));
        Grid.ContextRequested += OnContext;
        UpdateCount();
    }

    private void UpdateCount()
    {
        CountText.Text = $"{_files.Count} Datei(en)";
        DropHint.IsVisible = _files.Count == 0;
    }

    private void Add(IReadOnlyList<string> paths)
    {
        var found = DicomScu.CollectFiles(paths);
        var existing = _files.Select(f => f.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var f in found.Where(f => !existing.Contains(f))) _files.Add(new StoreFileRow(f));
        if (found.Count == 0 && paths.Count > 0) _state.Append("Store", "Keine DICOM-Dateien gefunden", error: true);
    }

    private async void OnAddFiles(object? sender, RoutedEventArgs e) => Add(await Ui.OpenFilesAsync(this, "DICOM-Dateien auswählen"));

    private async void OnAddFolder(object? sender, RoutedEventArgs e)
    {
        if (await Ui.OpenFolderAsync(this, "Ordner mit DICOM-Dateien auswählen") is { } d) Add([d]);
    }

    private void OnClearList(object? sender, RoutedEventArgs e)
    {
        if (_cts == null) _files.Clear();
    }

    private void OnGenerate(object? sender, RoutedEventArgs e)
    {
        var dir = Path.Combine(Path.GetTempPath(), "DICOMTestTool", Guid.NewGuid().ToString("N"));
        try
        {
            var urls = TestImageGenerator.Generate(new TestImageOptions
            {
                PatientName = PatName.Text?.Trim() ?? "",
                PatientId = PatId.Text?.Trim() ?? "",
                BirthDate = DicomDateInput.Normalize(BirthDate.Value, allowsRange: false),
                AccessionNumber = Accession.Text?.Trim() ?? "",
                Modality = string.IsNullOrWhiteSpace(Modality.Text) ? "OT" : Modality.Text.Trim().ToUpperInvariant(),
                Count = (int)(Count.Value ?? 1),
            }, dir);
            Add(urls);
            _state.Append("Store", $"{urls.Count} Testbild(er) erzeugt");
        }
        catch (Exception ex)
        {
            _state.Append("Store", "Testbild: " + ex.Message, error: true);
        }
    }

    private void OnCancel(object? sender, RoutedEventArgs e) => _cts?.Cancel();

    private async void OnSend(object? sender, RoutedEventArgs e)
    {
        if (_cts != null || _files.Count == 0 || _state.SelectedNode is not { } item) return;
        var cts = _cts = new CancellationTokenSource();
        SetRunning(true);
        foreach (var f in _files) { f.Status = "wartet"; f.Ok = null; }
        var rows = _files.ToDictionary(f => f.Path, StringComparer.OrdinalIgnoreCase);
        var start = DateTime.Now;
        try
        {
            var results = await Task.Run(() => DicomScu.StoreAsync(item.ToNode(), _state.ScuSettings, rows.Keys.ToList(),
                (done, total, r) => Dispatcher.UIThread.Post(() =>
                {
                    Progress.Value = (double)done / Math.Max(total, 1);
                    if (rows.TryGetValue(r.Path, out var row))
                    {
                        row.Ok = r.Ok;
                        row.Status = r.Error ?? (r.Status is { } s ? DicomNames.Status(s) : "");
                    }
                }), _state.Logger("Store"), cts.Token));
            var ok = results.Count(r => r.Ok);
            _state.Append("Store", $"Fertig: {ok}/{results.Count} erfolgreich in {(DateTime.Now - start).TotalSeconds:0.0} s", error: ok != results.Count);
        }
        catch (Exception ex)
        {
            _state.Append("Store", DicomErrors.Describe(ex), error: true);
        }
        _cts = null;
        SetRunning(false);
    }

    private void SetRunning(bool running)
    {
        Progress.IsVisible = running;
        Progress.Value = 0;
        CancelButton.IsVisible = running;
        SendButton.IsVisible = !running;
        ClearButton.IsEnabled = !running;
    }

    private void OnContext(object? sender, ContextRequestedEventArgs e)
    {
        if (Grid.SelectedItem is not StoreFileRow row) return;
        var menu = new ContextMenu();
        var view = new MenuItem { Header = "Im Viewer öffnen" };
        view.Click += (_, _) => _state.OpenInViewer(row.Path);
        var reveal = new MenuItem { Header = "Im Explorer zeigen" };
        reveal.Click += (_, _) => Services.Shell.RevealFile(row.Path);
        var remove = new MenuItem { Header = "Aus der Liste entfernen", IsEnabled = _cts == null };
        remove.Click += (_, _) => _files.Remove(row);
        menu.Items.Add(view);
        menu.Items.Add(reveal);
        menu.Items.Add(remove);
        menu.Open(Grid);
        e.Handled = true;
    }
}
