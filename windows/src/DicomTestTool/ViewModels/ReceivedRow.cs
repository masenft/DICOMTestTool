using DicomTestTool.Core;

namespace DicomTestTool.ViewModels;

public sealed class ReceivedRow(ReceivedObject o)
{
    public ReceivedObject Object { get; } = o;
    public string Time => Object.Date.ToString("HH:mm:ss");
    public string From => $"{Object.CallingAe} ({Object.Remote})";
    public string Patient => DicomNames.FormatPN(Object.PatientName);
    public string PatientId => Object.PatientId;
    public string Modality => Object.Modality;
    public string SopClass => DicomNames.SopClass(Object.SopClassUid);
    public string TransferSyntax => DicomNames.TransferSyntax(Object.TransferSyntax);
    public string Size => DicomNames.FormatSize(Object.Size);
    public string Path => Object.Path;
}
