using System.Text;
using FellowOakDicom;
using FellowOakDicom.Network;
using Microsoft.Extensions.Logging;

namespace DicomTestTool.Core.Tests;

/// <summary>Minimal Query/Retrieve + Worklist SCP for client tests.</summary>
public sealed class TestQrScp(INetworkStream stream, Encoding fallbackEncoding, ILogger log, DicomServiceDependencies dependencies)
    : DicomService(stream, fallbackEncoding, log, dependencies), IDicomServiceProvider, IDicomCFindProvider, IDicomCMoveProvider, IDicomCEchoProvider
{
    public static DicomDataset? LastQuery;
    public static string? LastMoveDestination;
    public static string? LastSopClass;

    public Task OnReceiveAssociationRequestAsync(DicomAssociation association)
    {
        foreach (var pc in association.PresentationContexts)
            pc.AcceptTransferSyntaxes(DicomTransferSyntax.ExplicitVRLittleEndian, DicomTransferSyntax.ImplicitVRLittleEndian);
        return SendAssociationAcceptAsync(association);
    }

    public Task OnReceiveAssociationReleaseRequestAsync() => SendAssociationReleaseResponseAsync();
    public void OnReceiveAbort(DicomAbortSource source, DicomAbortReason reason) { }
    public void OnConnectionClosed(Exception exception) { }

    public Task<DicomCEchoResponse> OnCEchoRequestAsync(DicomCEchoRequest request) =>
        Task.FromResult(new DicomCEchoResponse(request, DicomStatus.Success));

    public async IAsyncEnumerable<DicomCFindResponse> OnCFindRequestAsync(DicomCFindRequest request)
    {
        LastQuery = request.Dataset;
        LastSopClass = request.SOPClassUID.UID;
        for (var i = 1; i <= 2; i++)
        {
            var ds = new DicomDataset
            {
                { DicomTag.PatientName, $"MUSTER^PATIENT{i}" },
                { DicomTag.PatientID, $"P{i}" },
                { DicomTag.StudyInstanceUID, $"1.2.3.{i}" },
            };
            yield return new DicomCFindResponse(request, DicomStatus.Pending) { Dataset = ds };
        }
        await Task.Yield();
        yield return new DicomCFindResponse(request, DicomStatus.Success);
    }

    public async IAsyncEnumerable<DicomCMoveResponse> OnCMoveRequestAsync(DicomCMoveRequest request)
    {
        LastMoveDestination = request.DestinationAE;
        LastQuery = request.Dataset;
        LastSopClass = request.SOPClassUID.UID;
        yield return new DicomCMoveResponse(request, DicomStatus.Pending) { Remaining = 1, Completed = 1 };
        await Task.Yield();
        yield return new DicomCMoveResponse(request, DicomStatus.Success) { Completed = 2 };
    }
}
