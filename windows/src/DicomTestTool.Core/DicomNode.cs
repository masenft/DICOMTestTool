namespace DicomTestTool.Core;

public sealed class DicomNode
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string AeTitle { get; set; } = "";
    public string Host { get; set; } = "";
    public int Port { get; set; } = 104;

    public string Summary => $"{AeTitle}@{Host}:{Port}";

    public DicomNode Clone() => new() { Id = Id, Name = Name, AeTitle = AeTitle, Host = Host, Port = Port };
}

public sealed record ScuSettings(string CallingAe, double TimeoutSeconds)
{
    public int TimeoutMs => (int)Math.Max(1000, TimeoutSeconds * 1000);
}
