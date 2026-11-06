using System.Text;
using FellowOakDicom;
using FellowOakDicom.Network;
using Microsoft.Extensions.Logging;

namespace DicomTestTool.Core;

public sealed record ReceivedObject(DateTime Date, string CallingAe, string Remote, string PatientName, string PatientId,
    string Modality, string SopClassUid, string SopInstanceUid, string TransferSyntax, long Size, string Path);

/// <summary>Storage SCP: accepts C-STORE and C-ECHO and saves objects sorted by patient ID.</summary>
public sealed class StorageScp(string aeTitle, int port, string storageDirectory, bool acceptAnyCalledAe) : IDisposable
{
    public string AeTitle { get; } = aeTitle.Trim();
    public int Port { get; } = port;
    public string StorageDirectory { get; } = storageDirectory;
    public bool AcceptAnyCalledAe { get; } = acceptAnyCalledAe;
    public LogHandler? Log { get; set; }
    public Action<ReceivedObject>? OnReceived { get; set; }

    private IDicomServer? _server;

    public void Start()
    {
        DicomSetup.Initialize();
        if (Port is < 1 or > 65535) throw new DicomToolException($"Ungültiger Port {Port}");
        try
        {
            _server = DicomServerFactory.Create<ScpService>(Port, userState: this);
        }
        catch (Exception e)
        {
            throw new DicomToolException(PortError(e));
        }
        for (var i = 0; i < 20 && !_server.IsListening && _server.Exception == null; i++) Thread.Sleep(25);
        if (_server.Exception != null || !_server.IsListening)
        {
            var e = _server.Exception;
            _server.Dispose();
            _server = null;
            throw new DicomToolException(e != null ? PortError(e) : $"Port {Port} konnte nicht geöffnet werden");
        }
        Log?.Invoke($"Storage SCP gestartet: Port {Port}, AE-Titel {AeTitle}{(AcceptAnyCalledAe ? " (jeder Called AE)" : "")}, Ablage {StorageDirectory}");
    }

    private string PortError(Exception e)
    {
        var inner = e;
        while (inner.InnerException != null && inner is not System.Net.Sockets.SocketException) inner = inner.InnerException;
        if (inner is System.Net.Sockets.SocketException { SocketErrorCode: System.Net.Sockets.SocketError.AddressAlreadyInUse })
            return $"Port {Port} ist bereits belegt (läuft schon ein anderer SCP?)";
        if (inner is System.Net.Sockets.SocketException { SocketErrorCode: System.Net.Sockets.SocketError.AccessDenied })
            return $"Zugriff auf Port {Port} verweigert";
        return DicomErrors.Describe(e);
    }

    public void Stop()
    {
        if (_server == null) return;
        try { _server.Stop(); _server.Dispose(); } catch { }
        _server = null;
        Log?.Invoke("Storage SCP gestoppt");
    }

    public void Dispose() => Stop();

    internal static readonly string[] RejectedPrefixes =
        ["1.2.840.10008.5.1.4.1.2.", "1.2.840.10008.5.1.4.31", "1.2.840.10008.5.1.1.", "1.2.840.10008.3.1.2."];

    internal static string SafeFolderName(string patientId)
    {
        var invalid = Path.GetInvalidFileNameChars().Concat(['/', '\\', ':', '*', '?', '"', '<', '>', '|']).ToHashSet();
        var s = new string(patientId.Select(c => invalid.Contains(c) || char.IsControl(c) ? '_' : c).ToArray()).Trim().TrimEnd('.');
        return s.Length == 0 || s is "." or ".." ? "UNBEKANNT" : s;
    }

    internal ushort Save(DicomCStoreRequest request, string callingAe, string remote)
    {
        var ds = request.Dataset;
        var sopClass = request.SOPClassUID?.UID ?? ds.GetSingleValueOrDefault(DicomTag.SOPClassUID, "");
        var sopInstance = request.SOPInstanceUID?.UID ?? ds.GetSingleValueOrDefault(DicomTag.SOPInstanceUID, DicomUIDGenerator.GenerateDerivedFromUUID().UID);
        var ts = request.TransferSyntax?.UID.UID ?? request.File?.FileMetaInfo.TransferSyntax.UID.UID ?? "";
        var pid = ds.GetSingleValueOrDefault(DicomTag.PatientID, "");
        if (string.IsNullOrWhiteSpace(pid)) pid = "UNBEKANNT";
        var dir = Path.Combine(StorageDirectory, SafeFolderName(pid));
        var path = Path.Combine(dir, SafeFolderName(sopInstance) + ".dcm");
        try
        {
            Directory.CreateDirectory(dir);
            var file = request.File ?? new DicomFile(ds);
            file.FileMetaInfo.SourceApplicationEntityTitle = callingAe;
            file.Save(path);
        }
        catch (Exception e)
        {
            Log?.Invoke($"  Speichern fehlgeschlagen: {e.Message}");
            return 0xA700;
        }
        var obj = new ReceivedObject(DateTime.Now, callingAe, remote,
            ds.GetSingleValueOrDefault(DicomTag.PatientName, ""), pid, ds.GetSingleValueOrDefault(DicomTag.Modality, ""),
            sopClass, sopInstance, ts, new FileInfo(path).Length, path);
        Log?.Invoke($"  C-STORE {DicomNames.SopClass(sopClass)} – {obj.PatientName} [{pid}] gespeichert");
        OnReceived?.Invoke(obj);
        return 0;
    }
}

internal sealed class ScpService(INetworkStream stream, Encoding fallbackEncoding, ILogger log, DicomServiceDependencies dependencies)
    : DicomService(stream, fallbackEncoding, log, dependencies), IDicomServiceProvider, IDicomCStoreProvider, IDicomCEchoProvider
{
    private int _stored;
    private StorageScp Scp => (StorageScp)UserState;
    private string Remote => Association == null ? "?" : $"{Association.RemoteHost}:{Association.RemotePort}";

    public async Task OnReceiveAssociationRequestAsync(DicomAssociation association)
    {
        var scp = Scp;
        var remote = $"{association.RemoteHost}:{association.RemotePort}";
        scp.Log?.Invoke($"A-ASSOCIATE-RQ von {association.CallingAE}@{remote} an {association.CalledAE}");
        if (!scp.AcceptAnyCalledAe && !string.Equals(association.CalledAE.Trim(), scp.AeTitle, StringComparison.Ordinal))
        {
            scp.Log?.Invoke($"  abgelehnt: Called AE '{association.CalledAE}' ≠ '{scp.AeTitle}'");
            await SendAssociationRejectAsync(DicomRejectResult.Permanent, DicomRejectSource.ServiceUser, DicomRejectReason.CalledAENotRecognized);
            return;
        }
        var accepted = 0;
        foreach (var pc in DicomScu.Contexts(association.PresentationContexts))
        {
            if (StorageScp.RejectedPrefixes.Any(p => pc.AbstractSyntax.UID.StartsWith(p, StringComparison.Ordinal)))
            {
                pc.SetResult(DicomPresentationContextResult.RejectAbstractSyntaxNotSupported);
                continue;
            }
            var offered = pc.GetTransferSyntaxes();
            var chosen = new[] { DicomTransferSyntax.ExplicitVRLittleEndian, DicomTransferSyntax.ImplicitVRLittleEndian }.FirstOrDefault(offered.Contains)
                         ?? offered.FirstOrDefault(t => t != DicomTransferSyntax.ExplicitVRBigEndian);
            if (chosen == null)
            {
                pc.SetResult(DicomPresentationContextResult.RejectTransferSyntaxesNotSupported);
                continue;
            }
            pc.SetResult(DicomPresentationContextResult.Accept, chosen);
            accepted++;
        }
        await SendAssociationAcceptAsync(association);
        scp.Log?.Invoke($"  A-ASSOCIATE-AC: {accepted}/{association.PresentationContexts.Count} Presentation Context(s) akzeptiert");
    }

    public Task OnReceiveAssociationReleaseRequestAsync()
    {
        Scp.Log?.Invoke($"Assoziation von {Association?.CallingAE} beendet ({_stored} Objekt(e) empfangen)");
        return SendAssociationReleaseResponseAsync();
    }

    public void OnReceiveAbort(DicomAbortSource source, DicomAbortReason reason) =>
        Scp.Log?.Invoke($"Verbindung {Remote}: A-ABORT (Quelle {(int)source}, Grund {(int)reason})");

    public void OnConnectionClosed(Exception exception)
    {
        if (exception != null) Scp.Log?.Invoke($"Verbindung {Remote}: {DicomErrors.Describe(exception)}");
    }

    public Task<DicomCEchoResponse> OnCEchoRequestAsync(DicomCEchoRequest request)
    {
        Scp.Log?.Invoke($"  C-ECHO von {Association?.CallingAE} beantwortet");
        return Task.FromResult(new DicomCEchoResponse(request, DicomStatus.Success));
    }

    public Task<DicomCStoreResponse> OnCStoreRequestAsync(DicomCStoreRequest request)
    {
        var status = Scp.Save(request, Association?.CallingAE ?? "", Remote);
        if (status == 0) Interlocked.Increment(ref _stored);
        return Task.FromResult(new DicomCStoreResponse(request, status == 0 ? DicomStatus.Success : DicomStatus.Lookup(status)));
    }

    public Task OnCStoreRequestExceptionAsync(string tempFileName, Exception e)
    {
        Scp.Log?.Invoke($"  C-STORE fehlgeschlagen: {DicomErrors.Describe(e)}");
        return Task.CompletedTask;
    }
}
