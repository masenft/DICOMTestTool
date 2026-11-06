using Avalonia;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using DicomTestTool.ViewModels;
using DicomTestTool.Views;
using Xunit;

[assembly: AvaloniaTestApplication(typeof(DicomTestTool.UiTests.TestApp))]

namespace DicomTestTool.UiTests;

public static class TestApp
{
    public static AppBuilder BuildAvaloniaApp()
    {
        Environment.SetEnvironmentVariable("DICOMTESTTOOL_DATA_DIR", Path.Combine(Path.GetTempPath(), "dtt-ui-" + Environment.ProcessId));
        return AppBuilder.Configure<App>().UseSkia().WithInterFont()
            .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false });
    }
}

public class Snapshots
{
    [AvaloniaFact]
    public void Render_all_sections()
    {
        var outDir = Environment.GetEnvironmentVariable("DTT_SNAPSHOT_DIR") ?? Path.Combine(Path.GetTempPath(), "dtt-snapshots");
        Directory.CreateDirectory(outDir);
        var theme = Environment.GetEnvironmentVariable("DTT_THEME");
        if (theme != null) AppState.Shared.Theme = theme;
        var w = new MainWindow { Width = 1280, Height = 860 };
        w.Show();
        foreach (var s in Enum.GetValues<AppSection>())
        {
            AppState.Shared.Section = s;
            Dispatcher.UIThread.RunJobs();
            AvaloniaHeadlessPlatform.ForceRenderTimerTick();
            var frame = w.CaptureRenderedFrame();
            Assert.NotNull(frame);
            frame!.Save(Path.Combine(outDir, $"{(int)s:00}-{s}{(theme != null ? "-" + theme : "")}.png"));
        }
        var img = DicomTestTool.Core.TestImageGenerator.Generate(new DicomTestTool.Core.TestImageOptions(), Path.Combine(outDir, "img"))[0];
        AppState.Shared.OpenInViewer(img);
        AppState.Shared.Append("Echo", "C-ECHO-RSP: 0x0000 Erfolg");
        AppState.Shared.Append("Echo", "Verbindung abgelehnt", error: true);
        Dispatcher.UIThread.RunJobs();
        AvaloniaHeadlessPlatform.ForceRenderTimerTick();
        w.CaptureRenderedFrame()!.Save(Path.Combine(outDir, $"07-Viewer-loaded{(theme != null ? "-" + theme : "")}.png"));
    }
}
