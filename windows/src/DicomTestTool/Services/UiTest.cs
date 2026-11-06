using Avalonia.Controls;
using Avalonia.Threading;
using DicomTestTool.Core;
using DicomTestTool.ViewModels;
using DicomTestTool.Views;

namespace DicomTestTool.Services;

/// <summary>
/// Non-interactive UI smoke test (--uitest [logfile]): opens every page and dialog in a real window,
/// saves and reloads settings, shows a test notification and exits with 0 (ok) or 1. Used by CI on Windows.
/// </summary>
internal static class UiTest
{
    public static string? LogPath { get; set; }
    public static bool Enabled { get; set; }

    public static async Task<int> RunAsync(MainWindow window)
    {
        var lines = new List<string>();
        var failures = 0;
        void Ok(string s) => lines.Add("OK     " + s);
        void Fail(string s) { lines.Add("FEHLER " + s); failures++; }
        async Task Step(string name, Func<Task> action)
        {
            try { await action(); Ok(name); }
            catch (Exception e) { Fail($"{name}: {e}"); }
        }
        var state = AppState.Shared;
        lines.Add($"{AppInfo.Name} {AppInfo.Version} – UI-Test");
        await Task.Delay(500);
        foreach (var s in Enum.GetValues<AppSection>())
            await Step($"Seite {s}", async () =>
            {
                state.Section = s;
                await Task.Delay(400);
                if (window.FindControl<ContentControl>("ToolHost")?.Content == null) throw new Exception("keine Ansicht");
            });
        await Step("Viewer mit Testbild", async () =>
        {
            var f = TestImageGenerator.Generate(new TestImageOptions(), Path.Combine(Path.GetTempPath(), "dtt-uitest-" + Guid.NewGuid().ToString("N")))[0];
            state.OpenInViewer(f);
            await Task.Delay(800);
        });
        await Step("Tag-Dump-Fenster", async () =>
        {
            var w = new DatasetWindow(new FellowOakDicom.DicomDataset { { FellowOakDicom.DicomTag.PatientName, "TEST^UI" } }, "UI-Test");
            w.Show(window); await Task.Delay(400); w.Close();
        });
        await Step("Protokoll-Fenster", async () => { var w = new LogBrowserWindow(); w.Show(window); await Task.Delay(400); w.Close(); });
        await Step("Farbschema Klinik Dunkel", async () => { state.Theme = "clinicalDark"; await Task.Delay(300); state.Theme = "standard"; });
        await Step("Einstellungen speichern und laden", async () =>
        {
            state.CallingAe = "UITEST_AE";
            state.FlushSettings();
            if (SettingsStore.Load().CallingAe != "UITEST_AE") throw new Exception("Wert nicht gespeichert");
            await Task.CompletedTask;
        });
        await Step("Storage SCP starten/stoppen", async () =>
        {
            state.ScpPort = 47000 + Random.Shared.Next(1000);
            state.StartScp();
            await Task.Delay(300);
            if (!state.ScpRunning) throw new Exception("SCP läuft nicht");
            var r = await DicomScu.EchoAsync(new DicomNode { AeTitle = state.ScpAe, Host = "127.0.0.1", Port = state.ScpPort }, state.ScuSettings);
            state.StopScp();
            if (r.Status != 0) throw new Exception("Echo " + r.Status);
        });
        // Toasts may be unavailable on a build server; the result is reported but does not fail the test.
        var toast = Notifier.Show("DICOM Test Tool", "UI-Test");
        lines.Add(toast.Length == 0 ? "OK     Benachrichtigung angezeigt" : "HINWEIS Benachrichtigung: " + toast);
        lines.Add(failures == 0 ? "UI-Test bestanden" : $"UI-Test: {failures} Fehler");
        var text = string.Join(Environment.NewLine, lines) + Environment.NewLine;
        if (LogPath != null) await File.WriteAllTextAsync(LogPath, text); else Console.Write(text);
        return failures == 0 ? 0 : 1;
    }
}
