using System.Net;
using System.Net.Sockets;
using FellowOakDicom;
using FellowOakDicom.Imaging.Codec;

namespace DicomTestTool.Core;

/// <summary>Non-interactive check used by CI and for support: codecs, SCP, echo and store against itself.</summary>
public static class SelfTest
{
    public static async Task<int> RunAsync(TextWriter output)
    {
        var dir = Path.Combine(Path.GetTempPath(), "DICOMTestTool-selftest-" + Guid.NewGuid().ToString("N"));
        var failures = 0;
        void Ok(string s) => output.WriteLine("OK     " + s);
        void Fail(string s) { output.WriteLine("FEHLER " + s); failures++; }
        try
        {
            output.WriteLine($"{AppInfo.Name} {AppInfo.Version} – Selbsttest");
            DicomSetup.Initialize();
            var files = TestImageGenerator.Generate(new TestImageOptions { Count = 2 }, Path.Combine(dir, "gen"));
            Ok($"Testbilder erzeugt ({files.Count})");

            var source = DicomFile.Open(files[0]);
            foreach (var ts in new[] { DicomTransferSyntax.JPEGLSLossless, DicomTransferSyntax.JPEG2000Lossless, DicomTransferSyntax.JPEGProcess14SV1, DicomTransferSyntax.RLELossless })
            {
                try
                {
                    var compressed = new DicomTranscoder(source.Dataset.InternalTransferSyntax, ts).Transcode(source);
                    var path = Path.Combine(dir, $"codec-{ts.UID.UID}.dcm");
                    compressed.Save(path);
                    var px = new DicomImageRenderer(DicomFile.Open(path).Dataset).Render(0);
                    if (px.Length != 512 * 512) throw new Exception("falsche Bildgröße");
                    Ok($"Codec {DicomNames.TransferSyntax(ts.UID.UID)}: kodieren und dekodieren");
                }
                catch (Exception e) { Fail($"Codec {DicomNames.TransferSyntax(ts.UID.UID)}: {e.Message}"); }
            }

            var l = new TcpListener(IPAddress.Loopback, 0); l.Start();
            var port = ((IPEndPoint)l.LocalEndpoint).Port; l.Stop();
            var received = 0;
            using var scp = new StorageScp("SELFTEST", port, Path.Combine(dir, "in"), false) { OnReceived = _ => Interlocked.Increment(ref received) };
            scp.Start();
            Ok($"Storage SCP auf Port {port} gestartet");
            var node = new DicomNode { AeTitle = "SELFTEST", Host = "127.0.0.1", Port = port };
            var settings = new ScuSettings("SELFTEST_SCU", 10);
            var echo = await DicomScu.EchoAsync(node, settings);
            if (echo.Status == 0) Ok($"C-ECHO ({echo.TotalTime.TotalMilliseconds:0} ms)"); else Fail("C-ECHO: " + DicomNames.Status(echo.Status));
            var compressedFiles = Directory.GetFiles(dir, "codec-*.dcm");
            var results = await DicomScu.StoreAsync(node, settings, [.. files, .. compressedFiles]);
            if (results.All(r => r.Ok) && received == files.Count + compressedFiles.Length) Ok($"C-STORE ({received} Objekte)");
            else Fail("C-STORE: " + string.Join("; ", results.Where(r => !r.Ok).Select(r => r.Error)));
            try
            {
                node.AeTitle = "FALSCH";
                await DicomScu.EchoAsync(node, settings);
                Fail("Falscher AE-Titel wurde nicht abgelehnt");
            }
            catch (DicomToolException e) { Ok("Ablehnung bei falschem AE-Titel: " + e.Message); }
        }
        catch (Exception e)
        {
            Fail(e.ToString());
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch { }
        }
        output.WriteLine(failures == 0 ? "Selbsttest bestanden" : $"Selbsttest: {failures} Fehler");
        return failures == 0 ? 0 : 1;
    }
}
