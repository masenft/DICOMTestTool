using System.Diagnostics;

namespace DicomTestTool.Services;

/// <summary>Opening folders, files and links with the operating system.</summary>
internal static class Shell
{
    public static void OpenFolder(string path)
    {
        try
        {
            Directory.CreateDirectory(path);
            if (OperatingSystem.IsWindows()) Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
            else if (OperatingSystem.IsMacOS()) Process.Start("open", path);
            else Process.Start("xdg-open", path);
        }
        catch { }
    }

    public static void RevealFile(string path)
    {
        try
        {
            if (OperatingSystem.IsWindows()) Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
            else if (OperatingSystem.IsMacOS()) Process.Start("open", ["-R", path]);
            else OpenFolder(Path.GetDirectoryName(path)!);
        }
        catch { }
    }

    public static void OpenFile(string path) => OpenUri(path);

    public static void OpenUri(string uri)
    {
        try
        {
            if (OperatingSystem.IsMacOS()) Process.Start("open", uri);
            else Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true });
        }
        catch { }
    }
}
