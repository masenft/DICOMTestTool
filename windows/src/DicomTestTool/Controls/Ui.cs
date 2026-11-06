using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Input;
using Avalonia.Platform.Storage;

namespace DicomTestTool.Controls;

/// <summary>Dialogs, pickers and clipboard helpers.</summary>
public static class Ui
{
    private static TopLevel? Top(Visual v) => TopLevel.GetTopLevel(v);

    public static async Task CopyAsync(Visual v, string text)
    {
        if (Top(v)?.Clipboard is { } cb) await cb.SetTextAsync(text);
    }

    public static async Task<List<string>> OpenFilesAsync(Visual v, string title, bool multiple = true)
    {
        var top = Top(v);
        if (top == null) return [];
        var files = await top.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions { Title = title, AllowMultiple = multiple });
        return files.Select(f => f.TryGetLocalPath()).OfType<string>().ToList();
    }

    public static async Task<string?> OpenFolderAsync(Visual v, string title)
    {
        var top = Top(v);
        if (top == null) return null;
        var folders = await top.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions { Title = title, AllowMultiple = false });
        return folders.FirstOrDefault()?.TryGetLocalPath();
    }

    public static async Task<string?> SaveFileAsync(Visual v, string suggestedName, string typeName, string extension)
    {
        var top = Top(v);
        if (top == null) return null;
        var file = await top.StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            SuggestedFileName = suggestedName,
            DefaultExtension = extension,
            FileTypeChoices = [new FilePickerFileType(typeName) { Patterns = [$"*.{extension}"] }],
        });
        return file?.TryGetLocalPath();
    }

#pragma warning disable CS0618 // DataTransfer API is new in 11.3; Data still works
    public static IEnumerable<string> DroppedPaths(Avalonia.Input.DragEventArgs e) =>
        e.Data.GetFiles()?.Select(f => f.TryGetLocalPath()).OfType<string>() ?? [];
#pragma warning restore CS0618

    /// <summary>Simple modal question with a destructive confirm button.</summary>
    public static async Task<bool> ConfirmAsync(Visual owner, string title, string message, string confirm)
    {
        if (Top(owner) is not Window w) return false;
        var result = false;
        var dlg = new Window
        {
            Title = title, Width = 460, SizeToContent = SizeToContent.Height, CanResize = false,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, ShowInTaskbar = false,
            Background = (IBrush?)Application.Current!.FindResource("AppBackground") ?? Brushes.White,
        };
        var ok = new Button { Content = confirm, Classes = { "accent" } };
        var cancel = new Button { Content = "Abbrechen", IsCancel = true };
        ok.Click += (_, _) => { result = true; dlg.Close(); };
        cancel.Click += (_, _) => dlg.Close();
        dlg.Content = new StackPanel
        {
            Margin = new Thickness(20), Spacing = 14,
            Children =
            {
                new TextBlock { Text = title, FontWeight = FontWeight.Bold, FontSize = 16 },
                new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 8, Children = { cancel, ok } },
            },
        };
        await dlg.ShowDialog(w);
        return result;
    }
}
