using System.Net.Sockets;
using FellowOakDicom.Network;

namespace DicomTestTool.Core;

public sealed class DicomToolException(string message) : Exception(message);

public static class DicomErrors
{
    /// <summary>German, user-facing description of a network/DICOM error.</summary>
    public static string Describe(Exception e)
    {
        switch (e)
        {
            case AggregateException { InnerExceptions.Count: > 0 } ag:
                return Describe(ag.InnerExceptions[0]);
            case DicomToolException t:
                return t.Message;
            case OperationCanceledException:
                return "Abgebrochen";
            case DicomAssociationRejectedException r:
                return $"Assoziation abgelehnt ({(r.RejectResult == DicomRejectResult.Permanent ? "permanent" : "vorübergehend")}): {DicomNames.RejectReason(r.RejectSource, r.RejectReason)}";
            case DicomAssociationAbortedException a:
                return $"Assoziation abgebrochen (A-ABORT, Quelle {(int)a.AbortSource}, Grund {(int)a.AbortReason})";
            case DicomAssociationRequestTimedOutException:
                return "Zeitüberschreitung beim Assoziationsaufbau";
            case DicomRequestTimedOutException:
                return "Zeitüberschreitung: keine Antwort der Gegenstelle";
            case ConnectionClosedPrematurelyException:
                return "Verbindung wurde vorzeitig geschlossen";
            case SocketException s:
                return s.SocketErrorCode switch
                {
                    SocketError.ConnectionRefused => "Verbindung abgelehnt – am Port lauscht kein Dienst (Port, Firewall prüfen)",
                    SocketError.HostNotFound or SocketError.NoData => "Host nicht gefunden (Name oder IP-Adresse prüfen)",
                    SocketError.TimedOut => "Zeitüberschreitung beim Verbindungsaufbau",
                    SocketError.HostUnreachable or SocketError.NetworkUnreachable => "Host nicht erreichbar (Netzwerk, Routing prüfen)",
                    SocketError.ConnectionReset => "Verbindung wurde von der Gegenstelle zurückgesetzt",
                    _ => $"Netzwerkfehler: {s.Message}",
                };
            case TimeoutException:
                return "Zeitüberschreitung";
            case DicomNetworkException n when n.InnerException != null:
                return Describe(n.InnerException);
            case IOException io when io.InnerException != null:
                return Describe(io.InnerException);
            default:
                return e.InnerException != null && e.Message.Length == 0 ? Describe(e.InnerException) : e.Message;
        }
    }
}
