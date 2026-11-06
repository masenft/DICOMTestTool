using System.Globalization;

namespace DicomTestTool.Core;

public sealed record LogEntry(DateTime Date, string Source, string Text, bool IsError)
{
    public string Line => $"{Date.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture)} {(IsError ? "FEHLER" : "INFO  ")} [{Source}] {Text}";
}

/// <summary>Appends protocol lines to a daily log file (kept for 30 days).</summary>
public static class FileLogger
{
    public const int RetentionDays = 30;
    private static readonly object Gate = new();

    public static void Write(LogEntry e)
    {
        lock (Gate)
        {
            try
            {
                var file = Path.Combine(AppInfo.LogDirectory, $"dicomtesttool-{e.Date:yyyy-MM-dd}.log");
                File.AppendAllText(file, e.Line + Environment.NewLine);
            }
            catch { /* logging must never break the app */ }
        }
    }

    public static IReadOnlyList<FileInfo> LogFiles() =>
        new DirectoryInfo(AppInfo.LogDirectory).GetFiles("*.log").OrderByDescending(f => f.Name).ToList();

    public static void PruneOldFiles()
    {
        var cutoff = DateTime.Now.AddDays(-RetentionDays);
        foreach (var f in LogFiles())
            if (f.LastWriteTime < cutoff) { try { f.Delete(); } catch { } }
    }
}
