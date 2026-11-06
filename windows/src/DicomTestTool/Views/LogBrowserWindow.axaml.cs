using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using DicomTestTool.Controls;
using DicomTestTool.Core;
using DicomTestTool.Services;
using DicomTestTool.ViewModels;

namespace DicomTestTool.Views;

public partial class LogBrowserWindow : Window
{
    private sealed record LogFileItem(FileInfo File)
    {
        public override string ToString() => $"{File.Name}  ({DicomNames.FormatSize(File.Length)})";
    }

    public LogBrowserWindow()
    {
        InitializeComponent();
        AddFolder(0, "App-Datenordner", AppInfo.DataDirectory);
        AddFolder(1, "Log-Dateien", AppInfo.LogDirectory);
        AddFolder(2, "Empfangsordner (SCP)", AppState.Shared.ScpDirectory);
        Files.SelectionChanged += (_, _) => LoadContent();
        Reload();
    }

    public void ShowFor(Visual anchor)
    {
        if (TopLevel.GetTopLevel(anchor) is Window owner && owner.IsVisible) Show(owner); else Show();
    }

    private void AddFolder(int row, string title, string path)
    {
        var t = new TextBlock { Text = title, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center, Margin = new Thickness(0, 3) };
        var p = new TextBlock { Text = path, Classes = { "secondary" }, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center, TextTrimming = Avalonia.Media.TextTrimming.CharacterEllipsis };
        var b = new Button { Content = "Öffnen", Margin = new Thickness(8, 3, 0, 3) };
        b.Click += (_, _) => Shell.OpenFolder(path);
        Grid.SetRow(t, row); Grid.SetRow(p, row); Grid.SetRow(b, row);
        Grid.SetColumn(p, 1); Grid.SetColumn(b, 2);
        Folders.Children.Add(t); Folders.Children.Add(p); Folders.Children.Add(b);
    }

    private LogFileItem? Selected => Files.SelectedItem as LogFileItem;

    private void Reload()
    {
        var items = FileLogger.LogFiles().Select(f => new LogFileItem(f)).ToList();
        Files.ItemsSource = items;
        Files.SelectedItem = items.FirstOrDefault();
        LoadContent();
    }

    private void LoadContent()
    {
        if (Selected is not { } s) { LogText.Text = "Keine Einträge"; return; }
        try
        {
            using var fs = new FileStream(s.File.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            const long limit = 200_000;
            var truncated = fs.Length > limit;
            if (truncated) fs.Seek(-limit, SeekOrigin.End);
            using var r = new StreamReader(fs);
            LogText.Text = (truncated ? "… (nur die letzten 200 KB)\n" : "") + r.ReadToEnd();
        }
        catch (Exception e)
        {
            LogText.Text = e.Message;
        }
    }

    private void OnReload(object? sender, RoutedEventArgs e) => Reload();
    private void OnOpenFile(object? sender, RoutedEventArgs e) { if (Selected is { } s) Shell.OpenFile(s.File.FullName); }
    private void OnReveal(object? sender, RoutedEventArgs e) { if (Selected is { } s) Shell.RevealFile(s.File.FullName); }
    private void OnClose(object? sender, RoutedEventArgs e) => Close();

    private async void OnDeleteAll(object? sender, RoutedEventArgs e)
    {
        if (!await Ui.ConfirmAsync(this, "Alle Log-Dateien löschen?", "Die Log-Dateien der App werden endgültig gelöscht.", "Löschen")) return;
        foreach (var f in FileLogger.LogFiles()) { try { f.Delete(); } catch { } }
        Reload();
    }
}
