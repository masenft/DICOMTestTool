using Microsoft.Win32;

namespace DicomTestTool.Services;

/// <summary>Start at sign-in via HKCU\...\Run (no admin rights needed).</summary>
internal static class Autostart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "DICOMTestTool";

    public static bool IsSupported => OperatingSystem.IsWindows();

    public static bool IsEnabled
    {
        get
        {
            if (!OperatingSystem.IsWindows()) return false;
            using var k = Registry.CurrentUser.OpenSubKey(RunKey);
            return k?.GetValue(ValueName) is string;
        }
    }

    public static string Status => !IsSupported ? "nur unter Windows verfügbar" : IsEnabled ? "aktiv" : "nicht aktiv";

    public static void Enable()
    {
        if (!OperatingSystem.IsWindows()) return;
        var exe = Environment.ProcessPath ?? throw new InvalidOperationException("Programmpfad unbekannt");
        using var k = Registry.CurrentUser.CreateSubKey(RunKey);
        k.SetValue(ValueName, $"\"{exe}\" --autostart");
    }

    public static void Disable()
    {
        if (!OperatingSystem.IsWindows()) return;
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            k?.DeleteValue(ValueName, throwOnMissingValue: false);
        }
        catch { }
    }
}
