using System.Globalization;
using FellowOakDicom;
using FellowOakDicom.IO.Buffer;

namespace DicomTestTool.Core;

public sealed class TestImageOptions
{
    public string PatientName { get; set; } = "TEST^PATIENT";
    public string PatientId { get; set; } = "TEST0001";
    public string BirthDate { get; set; } = "19700101";
    public string Sex { get; set; } = "O";
    public string AccessionNumber { get; set; } = "";
    public string Modality { get; set; } = "OT";
    public string StudyDescription { get; set; } = "DICOM Test Tool";
    public int Count { get; set; } = 1;
    public int Size { get; set; } = 512;
}

/// <summary>Generates Secondary Capture test images (16 bit, 12 bit stored) in one study/series – no real patient data.</summary>
public static class TestImageGenerator
{
    public static List<string> Generate(TestImageOptions o, string directory)
    {
        DicomSetup.Initialize();
        Directory.CreateDirectory(directory);
        var study = DicomUIDGenerator.GenerateDerivedFromUUID();
        var series = DicomUIDGenerator.GenerateDerivedFromUUID();
        var now = DateTime.Now;
        var date = now.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
        var time = now.ToString("HHmmss", CultureInfo.InvariantCulture);
        var n = Math.Clamp(o.Size, 64, 4096);
        var urls = new List<string>();
        for (var i = 1; i <= Math.Max(1, o.Count); i++)
        {
            var sop = DicomUIDGenerator.GenerateDerivedFromUUID();
            var ds = new DicomDataset(DicomTransferSyntax.ExplicitVRLittleEndian)
            {
                { DicomTag.SpecificCharacterSet, "ISO_IR 100" },
                { DicomTag.ImageType, "DERIVED", "SECONDARY" },
                { DicomTag.SOPClassUID, DicomUID.SecondaryCaptureImageStorage },
                { DicomTag.SOPInstanceUID, sop },
                { DicomTag.StudyDate, date }, { DicomTag.StudyTime, time },
                { DicomTag.ContentDate, date }, { DicomTag.ContentTime, time },
                { DicomTag.AccessionNumber, o.AccessionNumber },
                { DicomTag.Modality, o.Modality },
                { DicomTag.ConversionType, "WSD" },
                { DicomTag.Manufacturer, "DICOM Test Tool" },
                { DicomTag.ReferringPhysicianName, "" },
                { DicomTag.StudyDescription, o.StudyDescription },
                { DicomTag.SeriesDescription, "Testbild" },
                { DicomTag.PatientName, o.PatientName },
                { DicomTag.PatientID, o.PatientId },
                { DicomTag.PatientBirthDate, o.BirthDate },
                { DicomTag.PatientSex, o.Sex },
                { DicomTag.StudyInstanceUID, study },
                { DicomTag.SeriesInstanceUID, series },
                { DicomTag.StudyID, "1" },
                { DicomTag.SeriesNumber, "1" },
                { DicomTag.InstanceNumber, i.ToString(CultureInfo.InvariantCulture) },
                { DicomTag.SamplesPerPixel, (ushort)1 },
                { DicomTag.PhotometricInterpretation, "MONOCHROME2" },
                { DicomTag.Rows, (ushort)n },
                { DicomTag.Columns, (ushort)n },
                { DicomTag.BitsAllocated, (ushort)16 },
                { DicomTag.BitsStored, (ushort)12 },
                { DicomTag.HighBit, (ushort)11 },
                { DicomTag.PixelRepresentation, (ushort)0 },
                { DicomTag.WindowCenter, "2048" },
                { DicomTag.WindowWidth, "4096" },
            };
            ds.Add(new DicomOtherWord(DicomTag.PixelData, new MemoryByteBuffer(Pixels(n, i))));
            var file = new DicomFile(ds);
            var path = Path.Combine(directory, $"TEST_{i}.dcm");
            file.Save(path);
            urls.Add(path);
        }
        return urls;
    }

    internal static byte[] Pixels(int n, int index)
    {
        var buf = new ushort[n * n];
        var c = n / 2.0;
        for (var y = 0; y < n; y++)
        for (var x = 0; x < n; x++)
        {
            var v = (double)(x + y) / (2 * n) * 3000 + 200;
            var r = Math.Sqrt((x - c) * (x - c) + (y - c) * (y - c));
            if (Math.Abs(r - n * 0.35) < 3) v = 4000;
            if (x % 64 == 0 || y % 64 == 0) v = 1500;
            buf[y * n + x] = (ushort)Math.Clamp(v, 0, 4095);
        }
        // Instance marker: one bright square per image number (up to 20) in the top-left corner.
        for (var k = 0; k < Math.Min(index, 20); k++)
        {
            int ox = 8 + k % 10 * 14, oy = 8 + k / 10 * 14;
            for (var y = oy; y < Math.Min(n, oy + 10); y++)
            for (var x = ox; x < Math.Min(n, ox + 10); x++)
                buf[y * n + x] = 4095;
        }
        var bytes = new byte[buf.Length * 2];
        Buffer.BlockCopy(buf, 0, bytes, 0, bytes.Length); // little endian on x64/arm64
        return bytes;
    }
}
