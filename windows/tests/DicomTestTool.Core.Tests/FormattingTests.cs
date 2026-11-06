namespace DicomTestTool.Core.Tests;

public class FormattingTests
{
    [Theory]
    [InlineData("04111970", "19701104")]
    [InlineData("19701104", "19701104")]
    [InlineData("04.11.1970", "19701104")]
    [InlineData("4.11.70", "19701104")]
    [InlineData("1970-11-04", "19701104")]
    [InlineData("31.02.2026", "31.02.2026")]
    [InlineData("01.11.2026-04.11.2026", "20261101-20261104")]
    [InlineData("01.11.2026 - ", "20261101-")]
    [InlineData("2026*", "2026*")]
    [InlineData("", "")]
    public void Normalize_range(string input, string expected) =>
        Assert.Equal(expected, DicomDateInput.Normalize(input, allowsRange: true));

    [Fact]
    public void Display_and_describe()
    {
        Assert.Equal("04.11.2026", DicomDateInput.Display("20261104"));
        Assert.Equal("01.11.2026 - 04.11.2026", DicomDateInput.Display("20261101-20261104"));
        Assert.Equal("Zeitraum 01.11.2026 bis …", DicomDateInput.Describe("20261101-"));
        Assert.Equal("Kein Datum: alle Einträge", DicomDateInput.Describe(""));
    }

    [Fact]
    public void Names()
    {
        Assert.Equal("MUSTERMANN, MAX", DicomNames.FormatPN("MUSTERMANN^MAX"));
        Assert.Equal("03.11.2026", DicomNames.FormatDA("20261103"));
        Assert.Equal("0xA801 Fehler: Move-Ziel unbekannt", DicomNames.Status(0xA801));
        Assert.Equal("JPEG 2000", DicomNames.TransferSyntax("1.2.840.10008.1.2.4.91"));
        Assert.Equal("PID_1", StorageScp.SafeFolderName("PID/1"));
    }

    [Fact]
    public void Settings_roundtrip()
    {
        var dir = Path.Combine(Path.GetTempPath(), "dtt-set-" + Guid.NewGuid().ToString("N"));
        Environment.SetEnvironmentVariable("DICOMTESTTOOL_DATA_DIR", dir);
        var s = new AppSettings { CallingAe = "ABC", ScpPort = 4242 };
        s.Nodes.Add(new DicomNode { Name = "PACS", AeTitle = "PACS", Host = "10.0.0.1", Port = 104 });
        SettingsStore.Save(s);
        var l = SettingsStore.Load();
        Assert.Equal("ABC", l.CallingAe);
        Assert.Equal(2, l.Nodes.Count);
        Assert.Equal(4242, l.ScpPort);
        Directory.Delete(dir, true);
    }

    [Fact]
    public void Settings_from_1_4_0_still_load()
    {
        var dir = Path.Combine(Path.GetTempPath(), "dtt-old-" + Guid.NewGuid().ToString("N"));
        Environment.SetEnvironmentVariable("DICOMTESTTOOL_DATA_DIR", dir);
        File.WriteAllText(SettingsStore.FilePath, """
        { "nodes": [ { "Id": "7d1f0c1e-1111-4222-8333-944445555666", "Name": "PACS", "AeTitle": "PACS", "Host": "10.0.0.5", "Port": 104, "Summary": "PACS@10.0.0.5:104" } ],
          "callingAE": "OLD_AE", "timeout": 20, "scpPort": 4100, "watchNodeIDs": [ "7d1f0c1e-1111-4222-8333-944445555666" ], "theme": "clinicalDark" }
        """);
        var s = SettingsStore.Load();
        Assert.Equal("OLD_AE", s.CallingAe);
        Assert.Equal("10.0.0.5", s.Nodes.Single().Host);
        Assert.Single(s.WatchNodeIds);
        Assert.Equal("clinicalDark", s.Theme);
        Directory.Delete(dir, true);
    }
}
