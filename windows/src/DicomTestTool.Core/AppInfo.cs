using System.Reflection;

namespace DicomTestTool.Core;

public static class AppInfo
{
    /// <summary>Name shown in title bar, Start menu and installer.</summary>
    public const string Name = "DICOM Test Tool für Windows";
    /// <summary>Folder name for settings, logs and received files (same as on the Mac).</summary>
    public const string ShortName = "DICOM Test Tool";
    public const string Developer = "Martin Senft";
    public const string Location = "Brakel, Deutschland";
    public const string DefaultRepository = "masenft/DICOMTestTool";
    public const string AppUserModelId = "de.martinsenft.dicomtesttool";

    public static string Version
    {
        get
        {
            // Core and app share the version from ../VERSION (Directory.Build.props).
            var v = typeof(AppInfo).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0-dev";
            var plus = v.IndexOf('+');
            return plus >= 0 ? v[..plus] : v;
        }
    }

    /// <summary>Overridable for tests (DICOMTESTTOOL_DATA_DIR).</summary>
    public static string DataDirectory
    {
        get
        {
            var overridden = Environment.GetEnvironmentVariable("DICOMTESTTOOL_DATA_DIR");
            var dir = !string.IsNullOrEmpty(overridden)
                ? overridden
                : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), ShortName);
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string LogDirectory
    {
        get
        {
            var overridden = Environment.GetEnvironmentVariable("DICOMTESTTOOL_DATA_DIR");
            var baseDir = !string.IsNullOrEmpty(overridden)
                ? overridden
                : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), ShortName);
            var dir = Path.Combine(baseDir, "Logs");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string DefaultStorageDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "DICOM Empfang");
}
