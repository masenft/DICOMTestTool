using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;
using DicomTestTool.Core;
using DicomTestTool.Services;

namespace DicomTestTool.Views;

public partial class ReleaseNotesWindow : Window
{
    public ReleaseNotesWindow()
    {
        InitializeComponent();
        DataContextChanged += (_, _) => Fill();
    }

    private UpdateService? Updater => DataContext as UpdateService;

    private void Fill()
    {
        if (Updater is not { } u) return;
        VersionLine.Text = $"Version {u.AvailableVersion} – installiert ist {AppInfo.Version}";
        Notes.Children.Clear();
        // Minimal Markdown: headings, bullet lists, plain lines (inline ** and ` are stripped).
        foreach (var raw in u.ReleaseNotes.Replace("\r", "").Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;
            string Clean(string s) => s.Replace("**", "").Replace("`", "");
            if (line.StartsWith('#'))
                Notes.Children.Add(new TextBlock { Text = Clean(line.TrimStart('#').Trim()), FontWeight = FontWeight.Bold, FontSize = line.StartsWith("###") ? 14 : 15, Margin = new Avalonia.Thickness(0, 6, 0, 0), TextWrapping = TextWrapping.Wrap });
            else if (line.StartsWith("- ") || line.StartsWith("* "))
                Notes.Children.Add(new TextBlock { Text = "•  " + Clean(line[2..]), TextWrapping = TextWrapping.Wrap, Margin = new Avalonia.Thickness(6, 0, 0, 0) });
            else
                Notes.Children.Add(new TextBlock { Text = Clean(line), TextWrapping = TextWrapping.Wrap });
        }
    }

    private void OnLater(object? sender, RoutedEventArgs e) => Close();
    private void OnSkip(object? sender, RoutedEventArgs e) { Updater?.Skip(); Close(); }
    private void OnGitHub(object? sender, RoutedEventArgs e) => Shell.OpenUri(UpdateService.RepositoryUrl + "/releases");
    private async void OnInstall(object? sender, RoutedEventArgs e) { if (Updater is { } u) await u.InstallAsync(); }
}
