using System.Diagnostics;
using FellowOakDicom;
using FellowOakDicom.Network;
using FellowOakDicom.Network.Client;

namespace DicomTestTool.Core;

public delegate void LogHandler(string message);

public sealed record EchoResult(ushort Status, TimeSpan AssociationTime, TimeSpan EchoTime, TimeSpan TotalTime);

public sealed record MoveProgress(ushort Status, int Remaining, int Completed, int Failed, int Warning);

public sealed record StoreItemResult(string Path, ushort? Status, string? Error, string? SopInstanceUid)
{
    public bool Ok => Error == null && Status is { } s && (DicomNames.IsSuccess(s) || DicomNames.IsWarning(s));
}

/// <summary>DICOM client operations (C-ECHO, C-FIND, C-MOVE, C-STORE) with protocol logging.</summary>
public static class DicomScu
{
    private static readonly DicomTransferSyntax[] Uncompressed = [DicomTransferSyntax.ExplicitVRLittleEndian, DicomTransferSyntax.ImplicitVRLittleEndian];

    private sealed class Session
    {
        public required IDicomClient Client;
        public readonly Stopwatch Clock = Stopwatch.StartNew();
        public TimeSpan? AcceptedAt;
        public readonly HashSet<string> AcceptedSopClasses = [];
    }

    private static Session Open(DicomNode node, ScuSettings s, LogHandler? log)
    {
        DicomSetup.Initialize();
        if (string.IsNullOrWhiteSpace(node.Host)) throw new DicomToolException("Kein Host angegeben");
        if (node.Port is < 1 or > 65535) throw new DicomToolException($"Ungültiger Port {node.Port}");
        var client = DicomClientFactory.Create(node.Host.Trim(), node.Port, false, s.CallingAe.Trim(), node.AeTitle.Trim());
        client.ClientOptions.ConnectionTimeoutInMs = s.TimeoutMs;
        client.ClientOptions.AssociationRequestTimeoutInMs = s.TimeoutMs;
        client.ClientOptions.AssociationReleaseTimeoutInMs = Math.Min(s.TimeoutMs, 5000);
        client.ClientOptions.AssociationLingerTimeoutInMs = 0;
        client.ClientOptions.MaximumNumberOfConsecutiveTimedOutAssociationRequests = 1;
        client.ServiceOptions.RequestTimeout = TimeSpan.FromMilliseconds(s.TimeoutMs);
        client.ServiceOptions.MaxPDULength = 65536;
        client.FallbackEncoding = System.Text.Encoding.Latin1;

        var session = new Session { Client = client };
        log?.Invoke($"Verbinde mit {node.Host}:{node.Port} …");
        log?.Invoke($"A-ASSOCIATE-RQ: {s.CallingAe} → {node.AeTitle}");
        client.AssociationAccepted += (_, e) =>
        {
            session.AcceptedAt = session.Clock.Elapsed;
            foreach (var pc in Contexts(e.Association.PresentationContexts))
            {
                var accepted = pc.Result == DicomPresentationContextResult.Accept;
                if (accepted) session.AcceptedSopClasses.Add(pc.AbstractSyntax.UID);
                log?.Invoke($"  PC {pc.ID} {DicomNames.SopClass(pc.AbstractSyntax.UID)}: {DicomNames.PresentationContextResult(pc.Result)}"
                            + (accepted && pc.AcceptedTransferSyntax != null ? $" – {DicomNames.TransferSyntax(pc.AcceptedTransferSyntax.UID.UID)}" : ""));
            }
            var impl = string.IsNullOrEmpty(e.Association.RemoteImplementationVersion)
                ? e.Association.RemoteImplementationClassUID?.UID ?? "?"
                : e.Association.RemoteImplementationVersion;
            log?.Invoke($"A-ASSOCIATE-AC erhalten (max. PDU {e.Association.MaximumPDULength}, Implementierung {impl})");
        };
        client.AssociationReleased += (_, _) => log?.Invoke("Assoziation freigegeben");
        return session;
    }

    /// <summary>The collection does not implement CopyTo, so LINQ ordering must not see it as ICollection.</summary>
    internal static List<DicomPresentationContext> Contexts(DicomPresentationContextCollection c)
    {
        var list = new List<DicomPresentationContext>();
        foreach (var pc in c) list.Add(pc);
        list.Sort((a, b) => a.ID.CompareTo(b.ID));
        return list;
    }

    private static async Task SendAsync(Session session, CancellationToken ct)
    {
        try
        {
            await session.Client.SendAsync(ct, DicomClientCancellationMode.ImmediatelyAbortAssociation).ConfigureAwait(false);
        }
        catch (Exception e) when (e is not DicomToolException)
        {
            if (ct.IsCancellationRequested) throw new OperationCanceledException(ct);
            if (Environment.GetEnvironmentVariable("DTT_DEBUG") == "1") Console.Error.WriteLine(e);
            throw new DicomToolException(DicomErrors.Describe(e));
        }
        ct.ThrowIfCancellationRequested();
    }

    private static void EnsureAccepted(Session s, string sopClass)
    {
        if (s.AcceptedAt != null && !s.AcceptedSopClasses.Contains(sopClass))
            throw new DicomToolException($"Kein akzeptierter Presentation Context: {DicomNames.SopClass(sopClass)} wurde nicht akzeptiert");
    }

    // MARK: C-ECHO

    public static async Task<EchoResult> EchoAsync(DicomNode node, ScuSettings settings, LogHandler? log = null, CancellationToken ct = default)
    {
        var s = Open(node, settings, log);
        ushort? status = null;
        var echoTime = TimeSpan.Zero;
        var rq = new DicomCEchoRequest
        {
            OnResponseReceived = (_, rsp) =>
            {
                status = rsp.Status.Code;
                echoTime = s.Clock.Elapsed - (s.AcceptedAt ?? TimeSpan.Zero);
                log?.Invoke($"C-ECHO-RSP: {DicomNames.Status(rsp.Status.Code)}");
            },
        };
        await s.Client.AddRequestAsync(rq).ConfigureAwait(false);
        log?.Invoke("C-ECHO-RQ gesendet");
        await SendAsync(s, ct).ConfigureAwait(false);
        EnsureAccepted(s, DicomNames.Verification);
        if (status is not { } st) throw new DicomToolException("Keine Antwort auf C-ECHO erhalten");
        return new EchoResult(st, s.AcceptedAt ?? TimeSpan.Zero, echoTime, s.Clock.Elapsed);
    }

    // MARK: C-FIND

    /// <summary>Sends a C-FIND with the given identifier; returns the final status.</summary>
    public static async Task<ushort> FindAsync(DicomNode node, ScuSettings settings, string sopClass, DicomDataset query,
        Action<DicomDataset> onResult, LogHandler? log = null, CancellationToken ct = default)
    {
        var s = Open(node, settings, log);
        var count = 0;
        ushort? final = null;
        var rq = new DicomCFindRequest(DicomUID.Parse(sopClass), DicomPriority.Medium) { Dataset = query };
        rq.OnResponseReceived = (_, rsp) =>
        {
            var code = rsp.Status.Code;
            if (DicomNames.IsPending(code))
            {
                count++;
                if (rsp.HasDataset) onResult(rsp.Dataset);
                return;
            }
            final = code;
            var msg = $"C-FIND abgeschlossen: {DicomNames.Status(code)}, {count} Treffer";
            var comment = rsp.Command.GetSingleValueOrDefault(DicomTag.ErrorComment, "");
            if (!string.IsNullOrEmpty(comment)) msg += $" – {comment}";
            log?.Invoke(msg);
        };
        await s.Client.AddRequestAsync(rq).ConfigureAwait(false);
        log?.Invoke($"C-FIND-RQ gesendet ({DicomNames.SopClass(sopClass)})");
        await SendAsync(s, ct).ConfigureAwait(false);
        EnsureAccepted(s, sopClass);
        return final ?? throw new DicomToolException("Keine abschließende C-FIND-Antwort erhalten");
    }

    // MARK: C-MOVE

    public static async Task<MoveProgress> MoveAsync(DicomNode node, ScuSettings settings, string sopClass, DicomDataset identifier,
        string destination, Action<MoveProgress>? progress = null, LogHandler? log = null, CancellationToken ct = default)
    {
        var s = Open(node, settings, log);
        MoveProgress? last = null;
        var rq = new DicomCMoveRequest(destination, identifier.GetSingleValueOrDefault(DicomTag.StudyInstanceUID, ""), DicomPriority.Medium);
        rq.Command.AddOrUpdate(DicomTag.AffectedSOPClassUID, sopClass);
        rq.Dataset = identifier;
        rq.OnResponseReceived = (_, rsp) =>
        {
            var p = new MoveProgress(rsp.Status.Code, rsp.Remaining, rsp.Completed, rsp.Failures, rsp.Warnings);
            last = p;
            progress?.Invoke(p);
            if (DicomNames.IsPending(p.Status)) return;
            var msg = $"C-MOVE abgeschlossen: {DicomNames.Status(p.Status)} – erfolgreich {p.Completed}, fehlgeschlagen {p.Failed}, Warnung {p.Warning}";
            var comment = rsp.Command.GetSingleValueOrDefault(DicomTag.ErrorComment, "");
            if (!string.IsNullOrEmpty(comment)) msg += $" – {comment}";
            log?.Invoke(msg);
        };
        await s.Client.AddRequestAsync(rq).ConfigureAwait(false);
        log?.Invoke($"C-MOVE-RQ gesendet, Ziel: {destination}");
        await SendAsync(s, ct).ConfigureAwait(false);
        EnsureAccepted(s, sopClass);
        return last ?? throw new DicomToolException("Keine Antwort auf C-MOVE erhalten");
    }

    // MARK: C-STORE

    public static async Task<IReadOnlyList<StoreItemResult>> StoreAsync(DicomNode node, ScuSettings settings, IReadOnlyList<string> files,
        Action<int, int, StoreItemResult>? progress = null, LogHandler? log = null, CancellationToken ct = default)
    {
        DicomSetup.Initialize();
        var results = new List<StoreItemResult>();
        var gate = new object();
        void Report(StoreItemResult r)
        {
            int done;
            lock (gate) { results.Add(r); done = results.Count; }
            progress?.Invoke(done, files.Count, r);
        }

        var requests = new List<(string Path, DicomCStoreRequest Rq)>();
        foreach (var path in files)
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                var file = await DicomFile.OpenAsync(path, FileReadOption.ReadLargeOnDemand).ConfigureAwait(false);
                if (!file.Dataset.Contains(DicomTag.SOPClassUID) || !file.Dataset.Contains(DicomTag.SOPInstanceUID))
                    throw new DicomToolException("SOP Class/Instance UID fehlt");
                var rq = new DicomCStoreRequest(file, DicomPriority.Medium);
                if (!Uncompressed.Contains(rq.TransferSyntax)) rq.AdditionalTransferSyntaxes = Uncompressed;
                requests.Add((path, rq));
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                Report(new StoreItemResult(path, null, "Parse-Fehler: " + DicomErrors.Describe(e), null));
            }
        }
        if (requests.Count == 0) return results;

        var s = Open(node, settings, log);
        var answered = new HashSet<DicomCStoreRequest>();
        foreach (var (path, rq) in requests)
        {
            var name = Path.GetFileName(path);
            var sop = rq.SOPInstanceUID?.UID;
            rq.OnResponseReceived = (q, rsp) =>
            {
                lock (gate) answered.Add(q);
                var code = rsp.Status.Code;
                string? error = DicomNames.IsSuccess(code) || DicomNames.IsWarning(code) ? null : DicomNames.Status(code);
                if (code == DicomStatus.SOPClassNotSupported.Code && !s.AcceptedSopClasses.Contains(q.SOPClassUID.UID))
                    error = $"Kein akzeptierter Presentation Context: {DicomNames.SopClass(q.SOPClassUID.UID)} / {DicomNames.TransferSyntax(rq.TransferSyntax.UID.UID)}";
                log?.Invoke($"C-STORE {name}: {error ?? DicomNames.Status(code)}");
                Report(new StoreItemResult(path, code, error, sop));
            };
            rq.OnTimeout = (_, _) =>
            {
                lock (gate) answered.Add(rq);
                Report(new StoreItemResult(path, null, "Zeitüberschreitung: keine Antwort", sop));
            };
            await s.Client.AddRequestAsync(rq).ConfigureAwait(false);
        }
        try
        {
            await SendAsync(s, ct).ConfigureAwait(false);
        }
        finally
        {
            // Anything without an answer (abort, rejection, cancel) is reported once.
            foreach (var (path, rq) in requests)
            {
                bool done;
                lock (gate) done = answered.Contains(rq);
                if (!done) Report(new StoreItemResult(path, null, ct.IsCancellationRequested ? "Abgebrochen" : "Nicht gesendet", rq.SOPInstanceUID?.UID));
            }
        }
        return results;
    }

    /// <summary>Recursively collects DICOM files from files and folders (folders: only files with DICM preamble).</summary>
    public static List<string> CollectFiles(IEnumerable<string> paths)
    {
        var result = new List<string>();
        foreach (var p in paths)
        {
            if (Directory.Exists(p))
            {
                IEnumerable<string> entries;
                try
                {
                    entries = Directory.EnumerateFiles(p, "*", new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.Hidden | FileAttributes.System });
                }
                catch { continue; }
                foreach (var f in entries.OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
                    if (!Path.GetFileName(f).Equals("DICOMDIR", StringComparison.OrdinalIgnoreCase) && IsDicomFile(f)) result.Add(f);
            }
            else if (File.Exists(p))
            {
                result.Add(p);
            }
        }
        return result;
    }

    public static bool IsDicomFile(string path)
    {
        try
        {
            using var fs = File.OpenRead(path);
            if (fs.Length < 132) return false;
            Span<byte> buf = stackalloc byte[4];
            fs.Seek(128, SeekOrigin.Begin);
            return fs.Read(buf) == 4 && buf.SequenceEqual("DICM"u8);
        }
        catch { return false; }
    }
}
