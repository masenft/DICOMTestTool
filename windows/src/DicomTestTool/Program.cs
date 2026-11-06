using Avalonia;
using DicomTestTool.Services;
using Velopack;

namespace DicomTestTool;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        // Must run first: handles install/update/uninstall hooks and exits in those cases.
        VelopackApp.Build()
            .OnBeforeUninstallFastCallback(_ =>
            {
                Autostart.Disable();
                Notifier.Uninstall();
            })
            .Run();

        // Non-interactive modes (CI, support): --version, --selftest [logfile]
        if (args.Contains("--version"))
        {
            Console.WriteLine(Core.AppInfo.Version);
            return;
        }
        var st = Array.IndexOf(args, "--selftest");
        if (st >= 0)
        {
            using var writer = st + 1 < args.Length ? new StreamWriter(args[st + 1]) : new StreamWriter(Console.OpenStandardOutput());
            Environment.ExitCode = Core.SelfTest.RunAsync(writer).GetAwaiter().GetResult();
            return;
        }

        if (!SingleInstance.TryAcquire())
        {
            SingleInstance.SignalFirstInstance();
            return;
        }
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args, Avalonia.Controls.ShutdownMode.OnExplicitShutdown);
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
