using System.Net;
using System.Net.Sockets;
using FellowOakDicom;
using FellowOakDicom.Network;

namespace DicomTestTool.Core.Tests;

public class ScuScpTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "dtt-tests-" + Guid.NewGuid().ToString("N"));
    private readonly List<string> _log = [];
    private static readonly ScuSettings Settings = new("TESTSCU", 5);

    public ScuScpTests()
    {
        Environment.SetEnvironmentVariable("DICOMTESTTOOL_DATA_DIR", Path.Combine(_dir, "data"));
        DicomSetup.Initialize();
    }

    public void Dispose()
    {
        try { Directory.Delete(_dir, true); } catch { }
    }

    private static int FreePort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        var p = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return p;
    }

    private void Log(string s) { lock (_log) _log.Add(s); }

    private (StorageScp scp, DicomNode node, List<ReceivedObject> received) StartScp(bool anyAe = true)
    {
        var port = FreePort();
        var received = new List<ReceivedObject>();
        var scp = new StorageScp("DTTSCP", port, Path.Combine(_dir, "in"), anyAe) { Log = Log, OnReceived = o => { lock (received) received.Add(o); } };
        scp.Start();
        return (scp, new DicomNode { Name = "Test", AeTitle = "DTTSCP", Host = "127.0.0.1", Port = port }, received);
    }

    [Fact]
    public async Task Echo_against_own_scp_succeeds_and_logs_negotiation()
    {
        var (scp, node, _) = StartScp();
        using (scp)
        {
            var r = await DicomScu.EchoAsync(node, Settings, Log);
            Assert.Equal((ushort)0, r.Status);
            Assert.True(r.TotalTime >= r.AssociationTime);
        }
        Assert.Contains(_log, l => l.StartsWith("A-ASSOCIATE-AC erhalten"));
        Assert.Contains(_log, l => l.Contains("PC 1 Verification: akzeptiert"));
        Assert.Contains(_log, l => l.StartsWith("C-ECHO-RSP: 0x0000 Erfolg"));
        Assert.Contains(_log, l => l.Contains("C-ECHO von TESTSCU beantwortet"));
    }

    [Fact]
    public async Task Echo_wrong_called_ae_is_rejected_with_german_message()
    {
        var (scp, node, _) = StartScp(anyAe: false);
        using (scp)
        {
            node.AeTitle = "FALSCH";
            var e = await Assert.ThrowsAsync<DicomToolException>(() => DicomScu.EchoAsync(node, Settings, Log));
            Assert.Equal("Assoziation abgelehnt (permanent): Called AE-Titel nicht erkannt", e.Message);
        }
    }

    [Fact]
    public async Task Echo_closed_port_reports_connection_refused()
    {
        var node = new DicomNode { AeTitle = "X", Host = "127.0.0.1", Port = FreePort() };
        var e = await Assert.ThrowsAsync<DicomToolException>(() => DicomScu.EchoAsync(node, Settings, Log));
        Assert.Contains("Verbindung abgelehnt", e.Message);
    }

    [Fact]
    public async Task Store_test_images_are_saved_by_patient_id()
    {
        var files = TestImageGenerator.Generate(new TestImageOptions { Count = 3, PatientId = "PID/1", PatientName = "MÜLLER^JÜRGEN" }, Path.Combine(_dir, "gen"));
        Assert.Equal(3, files.Count);
        var (scp, node, received) = StartScp();
        IReadOnlyList<StoreItemResult> results;
        using (scp)
        {
            var progress = 0;
            results = await DicomScu.StoreAsync(node, Settings, files, (d, t, r) => progress = d, Log);
            Assert.Equal(3, progress);
        }
        Assert.All(results, r => Assert.True(r.Ok, r.Error));
        Assert.Equal(3, received.Count);
        Assert.All(received, o => Assert.Equal("PID/1", o.PatientId));
        Assert.All(received, o => Assert.True(File.Exists(o.Path)));
        Assert.Equal(Path.Combine(_dir, "in", "PID_1"), Path.GetDirectoryName(received[0].Path));
        var stored = DicomFile.Open(received[0].Path);
        Assert.Equal("MÜLLER^JÜRGEN", stored.Dataset.GetString(DicomTag.PatientName));
        Assert.Equal("TESTSCU", stored.FileMetaInfo.SourceApplicationEntityTitle);
    }

    [Fact]
    public async Task Store_reports_unreadable_file_without_aborting_others()
    {
        var files = TestImageGenerator.Generate(new TestImageOptions { Count = 1 }, Path.Combine(_dir, "gen2"));
        var bad = Path.Combine(_dir, "gen2", "kaputt.dcm");
        File.WriteAllText(bad, "kein DICOM");
        var (scp, node, received) = StartScp();
        using (scp)
        {
            var results = await DicomScu.StoreAsync(node, Settings, [.. files, bad], log: Log);
            Assert.Equal(2, results.Count);
            Assert.False(results.Single(r => r.Path == bad).Ok);
            Assert.True(results.Single(r => r.Path == files[0]).Ok);
        }
        Assert.Single(received);
    }

    [Fact]
    public async Task Collect_files_finds_dicom_in_folders_only_with_preamble()
    {
        var dir = Path.Combine(_dir, "collect", "sub");
        TestImageGenerator.Generate(new TestImageOptions { Count = 2 }, dir);
        File.WriteAllText(Path.Combine(dir, "readme.txt"), "x");
        var found = DicomScu.CollectFiles([Path.Combine(_dir, "collect")]);
        Assert.Equal(2, found.Count);
        await Task.CompletedTask;
    }

    [Fact]
    public async Task Find_move_and_worklist_against_test_qr_scp()
    {
        var port = FreePort();
        using var server = DicomServerFactory.Create<TestQrScp>(port);
        var node = new DicomNode { AeTitle = "QR", Host = "127.0.0.1", Port = port };

        var q = new DicomDataset { { DicomTag.QueryRetrieveLevel, "STUDY" }, { DicomTag.PatientName, "MUSTER*" }, { DicomTag.StudyInstanceUID, "" } };
        var rows = new List<DicomDataset>();
        var status = await DicomScu.FindAsync(node, Settings, DicomNames.StudyRootFind, q, rows.Add, Log);
        Assert.Equal((ushort)0, status);
        Assert.Equal(2, rows.Count);
        Assert.Equal("MUSTER*", TestQrScp.LastQuery!.GetString(DicomTag.PatientName));
        Assert.Contains(_log, l => l == "C-FIND abgeschlossen: 0x0000 Erfolg, 2 Treffer");

        var ident = new DicomDataset { { DicomTag.QueryRetrieveLevel, "PATIENT" }, { DicomTag.PatientID, "P1" } };
        var p = await DicomScu.MoveAsync(node, Settings, DicomNames.PatientRootMove, ident, "ZIEL", log: Log);
        Assert.Equal(2, p.Completed);
        Assert.Equal("ZIEL", TestQrScp.LastMoveDestination);
        Assert.Equal(DicomNames.PatientRootMove, TestQrScp.LastSopClass);
        Assert.Equal("PATIENT", TestQrScp.LastQuery!.GetString(DicomTag.QueryRetrieveLevel));

        var mwl = new DicomDataset { { DicomTag.PatientName, "" } };
        mwl.Add(new DicomSequence(DicomTag.ScheduledProcedureStepSequence, new DicomDataset { { DicomTag.Modality, "CR" }, { DicomTag.ScheduledProcedureStepStartDate, "20261106" } }));
        rows.Clear();
        await DicomScu.FindAsync(node, Settings, DicomNames.ModalityWorklistFind, mwl, rows.Add, Log);
        Assert.Equal(2, rows.Count);
        Assert.Equal(DicomNames.ModalityWorklistFind, TestQrScp.LastSopClass);
    }

    [Fact]
    public void Viewer_renders_generated_image_with_window()
    {
        var f = TestImageGenerator.Generate(new TestImageOptions(), Path.Combine(_dir, "img"))[0];
        var r = new DicomImageRenderer(DicomFile.Open(f).Dataset);
        Assert.Equal(512, r.Width);
        Assert.Equal(2048, r.DefaultCenter);
        var px = r.Render(0, 2048, 4096);
        Assert.Equal(512 * 512, px.Length);
        var rows = TagRows.Flatten(DicomFile.Open(f).Dataset);
        Assert.Contains(rows, x => x.Name == "Patient's Name" && x.Value == "TEST^PATIENT");
    }
}
