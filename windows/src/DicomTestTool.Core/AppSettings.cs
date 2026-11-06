using System.Text.Json;
using System.Text.Json.Serialization;

namespace DicomTestTool.Core;

/// <summary>All persisted settings. Keys match the macOS app where a counterpart exists.</summary>
public sealed class AppSettings
{
    [JsonPropertyName("nodes")] public List<DicomNode> Nodes { get; set; } = DefaultNodes();
    [JsonPropertyName("callingAE")] public string CallingAe { get; set; } = "DICOMTEST_SCU";
    [JsonPropertyName("timeout")] public double Timeout { get; set; } = 15;

    [JsonPropertyName("scpAE")] public string ScpAe { get; set; } = "DICOMTEST";
    [JsonPropertyName("scpPort")] public int ScpPort { get; set; } = 11112;
    [JsonPropertyName("scpAnyAE")] public bool ScpAcceptAnyAe { get; set; } = true;
    [JsonPropertyName("scpDir")] public string ScpDirectory { get; set; } = AppInfo.DefaultStorageDirectory;

    [JsonPropertyName("notificationsEnabled")] public bool NotificationsEnabled { get; set; } = true;
    [JsonPropertyName("notifyWatchdog")] public bool NotifyWatchdog { get; set; } = true;
    [JsonPropertyName("notifySCP")] public bool NotifyScp { get; set; }
    [JsonPropertyName("showTrayIcon")] public bool ShowTrayIcon { get; set; } = true;
    [JsonPropertyName("keepRunningInTray")] public bool KeepRunningInTray { get; set; } = true;
    [JsonPropertyName("autoStartSCP")] public bool AutoStartScp { get; set; }
    [JsonPropertyName("autoStartWatchdog")] public bool AutoStartWatchdog { get; set; }
    [JsonPropertyName("watchInterval")] public double WatchInterval { get; set; } = 60;
    [JsonPropertyName("watchNodeIDs")] public List<Guid> WatchNodeIds { get; set; } = [];
    [JsonPropertyName("theme")] public string Theme { get; set; } = "standard";

    [JsonPropertyName("updateAutoCheck")] public bool UpdateAutoCheck { get; set; } = true;
    [JsonPropertyName("updatePrerelease")] public bool UpdatePrerelease { get; set; }
    [JsonPropertyName("updateLastCheck")] public DateTimeOffset? UpdateLastCheck { get; set; }
    [JsonPropertyName("updateSkippedVersion")] public string UpdateSkippedVersion { get; set; } = "";

    public static List<DicomNode> DefaultNodes() =>
        [new DicomNode { Name = "Lokaler SCP", AeTitle = "DICOMTEST", Host = "127.0.0.1", Port = 11112 }];
}

public static class SettingsStore
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };
    private static readonly object Gate = new();

    public static string FilePath => Path.Combine(AppInfo.DataDirectory, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), Options) ?? new AppSettings();
        }
        catch (Exception)
        {
            // A damaged file must not prevent the app from starting; keep a copy for inspection.
            try { File.Copy(FilePath, FilePath + ".defekt", overwrite: true); } catch { }
        }
        return new AppSettings();
    }

    public static void Save(AppSettings settings)
    {
        lock (Gate)
        {
            var tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(settings, Options));
            File.Move(tmp, FilePath, overwrite: true);
        }
    }

    public static void Delete()
    {
        lock (Gate) { try { File.Delete(FilePath); } catch { } }
    }
}
