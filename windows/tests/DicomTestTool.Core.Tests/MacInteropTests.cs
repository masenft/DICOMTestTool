using System.Diagnostics;
using System.Net;
using System.Net.Sockets;

namespace DicomTestTool.Core.Tests;

/// <summary>Cross-checks against the macOS implementation (dicomcli). Runs only when DTT_MACCLI points to dicomcli.</summary>
public class MacInteropTests
{
    private static readonly string? Cli = Environment.GetEnvironmentVariable("DTT_MACCLI");

    private static int FreePort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0); l.Start();
        var p = ((IPEndPoint)l.LocalEndpoint).Port; l.Stop(); return p;
    }

    private static (int Code, string Output) Run(params string[] args)
    {
        var psi = new ProcessStartInfo(Cli!) { RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var a in args) psi.ArgumentList.Add(a);
        psi.Environment["DICOM_AET"] = "MACCLI";
        using var p = Process.Start(psi)!;
        var output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
        p.WaitForExit(30000);
        return (p.ExitCode, output);
    }

    [Fact]
    public void Mac_cli_echo_and_store_to_windows_scp()
    {
        if (string.IsNullOrEmpty(Cli)) return;
        var dir = Path.Combine(Path.GetTempPath(), "dtt-mac-" + Guid.NewGuid().ToString("N"));
        var port = FreePort();
        var received = new List<ReceivedObject>();
        using var scp = new StorageScp("WINSCP", port, Path.Combine(dir, "in"), false) { OnReceived = o => { lock (received) received.Add(o); } };
        scp.Start();
        var echo = Run("echo", "127.0.0.1", port.ToString(), "WINSCP");
        Assert.True(echo.Code == 0, echo.Output);
        Run("testimage", Path.Combine(dir, "mac"), "2");
        var store = Run("store", "127.0.0.1", port.ToString(), "WINSCP", Path.Combine(dir, "mac"));
        Assert.True(store.Code == 0, store.Output);
        Assert.Equal(2, received.Count);
        Assert.All(received, o => Assert.Equal("MACCLI", o.CallingAe));
        var dump = Run("dump", received[0].Path);
        Assert.Contains("TEST^PATIENT", dump.Output);
        Directory.Delete(dir, true);
    }

    [Fact]
    public async Task Windows_echo_and_store_to_mac_scp()
    {
        if (string.IsNullOrEmpty(Cli)) return;
        var dir = Path.Combine(Path.GetTempPath(), "dtt-mac2-" + Guid.NewGuid().ToString("N"));
        var port = FreePort();
        var psi = new ProcessStartInfo(Cli!) { RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var a in new[] { "scp", port.ToString(), "MACSCP", Path.Combine(dir, "in") }) psi.ArgumentList.Add(a);
        using var p = Process.Start(psi)!;
        try
        {
            await Task.Delay(800);
            var node = new DicomNode { AeTitle = "MACSCP", Host = "127.0.0.1", Port = port };
            var settings = new ScuSettings("WINSCU", 5);
            var log = new List<string>();
            var r = await DicomScu.EchoAsync(node, settings, log.Add);
            Assert.Equal((ushort)0, r.Status);
            Assert.Contains(log, l => l.StartsWith("A-ASSOCIATE-AC erhalten"));
            var files = TestImageGenerator.Generate(new TestImageOptions { Count = 2, PatientName = "MÜLLER^JÜRGEN" }, Path.Combine(dir, "win"));
            var res = await DicomScu.StoreAsync(node, settings, files, log: log.Add);
            Assert.All(res, x => Assert.True(x.Ok, x.Error));
            await Task.Delay(300);
            Assert.Equal(2, Directory.GetFiles(Path.Combine(dir, "in"), "*.dcm", SearchOption.AllDirectories).Length);
        }
        finally
        {
            p.Kill();
            try { Directory.Delete(dir, true); } catch { }
        }
    }
}
