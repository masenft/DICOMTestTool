import Foundation

public struct DicomNode: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var aeTitle: String
    public var host: String
    public var port: UInt16

    public init(id: UUID = UUID(), name: String, aeTitle: String, host: String, port: UInt16) {
        self.id = id; self.name = name; self.aeTitle = aeTitle; self.host = host; self.port = port
    }

    public var summary: String { "\(aeTitle)@\(host):\(port)" }
}

public struct SCUSettings: Sendable {
    public var callingAE: String
    public var timeout: TimeInterval
    public var maxPDU: UInt32

    public init(callingAE: String, timeout: TimeInterval = 15, maxPDU: UInt32 = 65536) {
        self.callingAE = callingAE; self.timeout = timeout; self.maxPDU = maxPDU
    }
}

public struct EchoResult: Sendable {
    public var status: UInt16
    public var associationTime: TimeInterval
    public var echoTime: TimeInterval
    public var totalTime: TimeInterval
}

public struct MoveProgress: Sendable {
    public var status: UInt16
    public var remaining: Int
    public var completed: Int
    public var failed: Int
    public var warning: Int
}

public struct StoreItemResult: Sendable {
    public var url: URL
    public var status: UInt16?
    public var error: String?
    public var sopInstanceUID: String?
    public var ok: Bool { error == nil && (status.map { DimseStatus.isSuccess($0) || DimseStatus.isWarning($0) } ?? false) }
}

public enum DicomSCU {
    static let uncompressed = [TransferSyntax.explicitLE, TransferSyntax.implicitLE]

    private static func open(_ node: DicomNode, _ s: SCUSettings, _ contexts: [PresentationContext], _ log: LogHandler?) async throws -> Association {
        try await Association.request(host: node.host, port: node.port, callingAE: s.callingAE, calledAE: node.aeTitle,
                                      contexts: contexts, timeout: s.timeout, maxPDU: s.maxPDU, log: log)
    }

    // MARK: C-ECHO

    public static func echo(node: DicomNode, settings: SCUSettings, log: LogHandler? = nil) async throws -> EchoResult {
        let t0 = Date()
        let assoc = try await open(node, settings, [PresentationContext(id: 1, abstractSyntax: SOPClass.verification, transferSyntaxes: uncompressed)], log)
        let t1 = Date()
        guard let pc = assoc.context(for: SOPClass.verification) else {
            assoc.abort()
            throw DicomError.noPresentationContext("Verification wurde nicht akzeptiert")
        }
        var cmd = DataSet()
        cmd.set(.affectedSOPClassUID, SOPClass.verification)
        cmd.setUInt16(.commandField, 0x0030)
        cmd.setUInt16(.messageID, assoc.nextMessageID())
        log?("C-ECHO-RQ gesendet")
        do {
            try await assoc.send(command: cmd, dataset: nil, pcid: pc.id)
            let rsp = try await assoc.receiveMessage()
            let t2 = Date()
            log?("C-ECHO-RSP: \(DimseStatus.text(rsp.status))")
            await assoc.release()
            log?("Assoziation freigegeben")
            return EchoResult(status: rsp.status, associationTime: t1.timeIntervalSince(t0),
                              echoTime: t2.timeIntervalSince(t1), totalTime: Date().timeIntervalSince(t0))
        } catch {
            assoc.abort()
            throw error
        }
    }

    // MARK: C-FIND

    @discardableResult
    public static func find(node: DicomNode, settings: SCUSettings, sopClass: String, query: DataSet,
                            log: LogHandler? = nil, onResult: (DataSet) -> Void) async throws -> UInt16 {
        let assoc = try await open(node, settings, [PresentationContext(id: 1, abstractSyntax: sopClass, transferSyntaxes: uncompressed)], log)
        guard let pc = assoc.context(for: sopClass) else {
            assoc.abort()
            throw DicomError.noPresentationContext("\(SOPClass.name(sopClass)) wurde nicht akzeptiert")
        }
        let explicit = TransferSyntax.isExplicit(pc.transferSyntax)
        var cmd = DataSet()
        cmd.set(.affectedSOPClassUID, sopClass)
        cmd.setUInt16(.commandField, 0x0020)
        cmd.setUInt16(.messageID, assoc.nextMessageID())
        cmd.setUInt16(.priority, 0)
        do {
            try await assoc.send(command: cmd, dataset: query.encoded(explicit: explicit), pcid: pc.id)
            log?("C-FIND-RQ gesendet (\(SOPClass.name(sopClass)))")
            var count = 0
            while true {
                if Task.isCancelled { assoc.abort(); throw DicomError.cancelled }
                let rsp = try await assoc.receiveMessage()
                if DimseStatus.isPending(rsp.status) {
                    count += 1
                    if let d = rsp.dataset { onResult(try DataSet.parse(d, explicit: explicit)) }
                } else {
                    var msg = "C-FIND abgeschlossen: \(DimseStatus.text(rsp.status)), \(count) Treffer"
                    if let c = rsp.command.string(.errorComment), !c.isEmpty { msg += " – \(c)" }
                    log?(msg)
                    await assoc.release()
                    return rsp.status
                }
            }
        } catch {
            assoc.abort()
            throw error
        }
    }

    // MARK: C-MOVE

    @discardableResult
    public static func move(node: DicomNode, settings: SCUSettings, sopClass: String, query: DataSet, destination: String,
                            log: LogHandler? = nil, progress: (MoveProgress) -> Void) async throws -> MoveProgress {
        let assoc = try await open(node, settings, [PresentationContext(id: 1, abstractSyntax: sopClass, transferSyntaxes: uncompressed)], log)
        guard let pc = assoc.context(for: sopClass) else {
            assoc.abort()
            throw DicomError.noPresentationContext("\(SOPClass.name(sopClass)) wurde nicht akzeptiert")
        }
        var cmd = DataSet()
        cmd.set(.affectedSOPClassUID, sopClass)
        cmd.setUInt16(.commandField, 0x0021)
        cmd.setUInt16(.messageID, assoc.nextMessageID())
        cmd.setUInt16(.priority, 0)
        cmd.set(.moveDestination, destination)
        do {
            try await assoc.send(command: cmd, dataset: query.encoded(explicit: TransferSyntax.isExplicit(pc.transferSyntax)), pcid: pc.id)
            log?("C-MOVE-RQ gesendet, Ziel: \(destination)")
            while true {
                if Task.isCancelled { assoc.abort(); throw DicomError.cancelled }
                let rsp = try await assoc.receiveMessage()
                let c = rsp.command
                let p = MoveProgress(status: rsp.status,
                                     remaining: c.int(.remainingSubops) ?? 0, completed: c.int(.completedSubops) ?? 0,
                                     failed: c.int(.failedSubops) ?? 0, warning: c.int(.warningSubops) ?? 0)
                progress(p)
                if !DimseStatus.isPending(rsp.status) {
                    var msg = "C-MOVE abgeschlossen: \(DimseStatus.text(rsp.status)) – erfolgreich \(p.completed), fehlgeschlagen \(p.failed), Warnung \(p.warning)"
                    if let e = c.string(.errorComment), !e.isEmpty { msg += " – \(e)" }
                    log?(msg)
                    await assoc.release()
                    return p
                }
            }
        } catch {
            assoc.abort()
            throw error
        }
    }

    // MARK: C-STORE

    struct StoreCandidate {
        var url: URL
        var sopClass: String
        var sopInstance: String
        var transferSyntax: String
    }

    public static func store(node: DicomNode, settings: SCUSettings, files: [URL], log: LogHandler? = nil,
                             progress: (Int, Int, StoreItemResult) -> Void) async throws -> [StoreItemResult] {
        var results: [StoreItemResult] = []
        var candidates: [StoreCandidate] = []
        for url in files {
            do {
                let f = try DicomFile.read(url, parseDataset: false)
                guard let sc = f.sopClassUID, let si = f.sopInstanceUID else {
                    throw DicomError.parse("SOP Class/Instance UID fehlt")
                }
                candidates.append(StoreCandidate(url: url, sopClass: sc, sopInstance: si, transferSyntax: f.transferSyntax))
            } catch {
                let r = StoreItemResult(url: url, status: nil, error: error.localizedDescription)
                results.append(r)
                progress(results.count, files.count, r)
            }
        }
        guard !candidates.isEmpty else { return results }

        // One context per (SOP class, compressed TS) plus one uncompressed context per SOP class.
        var contexts: [PresentationContext] = []
        var seen = Set<String>()
        func add(_ asx: String, _ ts: [String]) {
            let key = asx + "|" + ts.joined(separator: ",")
            guard !seen.contains(key) else { return }
            seen.insert(key)
            contexts.append(PresentationContext(id: UInt8(contexts.count * 2 + 1), abstractSyntax: asx, transferSyntaxes: ts))
        }
        for c in candidates {
            if !TransferSyntax.isUncompressedLE(c.transferSyntax) { add(c.sopClass, [c.transferSyntax]) }
            add(c.sopClass, uncompressed)
        }
        guard contexts.count <= 128 else {
            throw DicomError.unsupported("Mehr als 128 Presentation Contexts nötig (\(contexts.count)). Bitte weniger unterschiedliche SOP-Klassen pro Sendung.")
        }

        let assoc = try await open(node, settings, contexts, log)
        do {
            for c in candidates {
                if Task.isCancelled { assoc.abort(); throw DicomError.cancelled }
                var r = StoreItemResult(url: c.url, status: nil, error: nil, sopInstanceUID: c.sopInstance)
                do {
                    let pc: PresentationContext
                    if let exact = assoc.context(for: c.sopClass, transferSyntax: c.transferSyntax) {
                        pc = exact
                    } else if TransferSyntax.isUncompressedLE(c.transferSyntax), let any = assoc.context(for: c.sopClass),
                              TransferSyntax.isUncompressedLE(any.transferSyntax) {
                        pc = any
                    } else {
                        throw DicomError.noPresentationContext("\(SOPClass.name(c.sopClass)) / \(TransferSyntax.name(c.transferSyntax))")
                    }
                    let file = try DicomFile.read(c.url, parseDataset: false)
                    let bytes = try file.datasetBytes(in: pc.transferSyntax)
                    var cmd = DataSet()
                    cmd.set(.affectedSOPClassUID, c.sopClass)
                    cmd.setUInt16(.commandField, 0x0001)
                    cmd.setUInt16(.messageID, assoc.nextMessageID())
                    cmd.setUInt16(.priority, 0)
                    cmd.set(.affectedSOPInstanceUID, c.sopInstance)
                    try await assoc.send(command: cmd, dataset: bytes, pcid: pc.id)
                    let rsp = try await assoc.receiveMessage()
                    r.status = rsp.status
                    if !DimseStatus.isSuccess(rsp.status) {
                        r.error = DimseStatus.isWarning(rsp.status) ? nil : DimseStatus.text(rsp.status)
                    }
                    log?("C-STORE \(c.url.lastPathComponent): \(DimseStatus.text(rsp.status))")
                } catch let e as DicomError {
                    switch e {
                    case .noPresentationContext, .unsupported, .parse:
                        r.error = e.localizedDescription
                        log?("C-STORE \(c.url.lastPathComponent): \(e.localizedDescription)")
                    default: throw e
                    }
                }
                results.append(r)
                progress(results.count, files.count, r)
            }
            await assoc.release()
            log?("Assoziation freigegeben")
        } catch {
            assoc.abort()
            throw error
        }
        return results
    }

    /// Recursively collects DICOM files from files and folders.
    public static func collectFiles(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let f = e?.nextObject() as? URL {
                    if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                       f.lastPathComponent.uppercased() != "DICOMDIR", DicomFile.isDicomFile(f) {
                        out.append(f)
                    }
                }
            } else {
                out.append(url)
            }
        }
        return out
    }
}
