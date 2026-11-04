import Foundation
import Network

public struct ReceivedObject: Sendable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var callingAE: String
    public var remote: String
    public var patientName: String
    public var patientID: String
    public var modality: String
    public var sopClassUID: String
    public var sopInstanceUID: String
    public var transferSyntax: String
    public var size: Int
    public var path: URL
}

/// Storage + Verification SCP. Stores received objects unchanged in the negotiated transfer syntax.
public final class StorageSCP: @unchecked Sendable {
    public let aeTitle: String
    public let port: UInt16
    public let storageDirectory: URL
    public let acceptAnyCalledAE: Bool
    public var log: LogHandler?
    public var onReceived: (@Sendable (ReceivedObject) -> Void)?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dicom.scp")

    public init(aeTitle: String, port: UInt16, storageDirectory: URL, acceptAnyCalledAE: Bool) {
        self.aeTitle = aeTitle
        self.port = port
        self.storageDirectory = storageDirectory
        self.acceptAnyCalledAE = acceptAnyCalledAE
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let p = NWEndpoint.Port(rawValue: port) else { throw DicomError.protocolError("Ungültiger Port") }
        let l = try NWListener(using: params, on: p)
        l.newConnectionHandler = { [weak self] nw in
            guard let self else { return }
            Task { await self.handle(nw) }
        }
        l.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.log?("SCP \(self.aeTitle) lauscht auf Port \(self.port)")
            case .failed(let e): self.log?("SCP-Fehler: \(e.localizedDescription)")
            case .cancelled: self.log?("SCP gestoppt")
            default: break
            }
        }
        l.start(queue: queue)
        listener = l
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    static let rejectedPrefixes = ["1.2.840.10008.5.1.4.1.2.", "1.2.840.10008.5.1.4.31", "1.2.840.10008.5.1.1.", "1.2.840.10008.3.1.2."]

    private func handle(_ nw: NWConnection) async {
        let conn = DicomConnection(nw, timeout: 120)
        do {
            try await conn.start()
        } catch {
            return
        }
        let remote = conn.remoteDescription
        do {
            let (type, body) = try await Association.readPDU(conn)
            guard type == PDUType.associateRQ else {
                try? await conn.send(SimplePDU.abort(source: 2, reason: 2))
                conn.close()
                return
            }
            let rq = try AssociatePDU.decode(body)
            log?("A-ASSOCIATE-RQ von \(rq.callingAE)@\(remote) an \(rq.calledAE)")
            if !acceptAnyCalledAE && rq.calledAE != aeTitle {
                log?("  abgelehnt: Called AE '\(rq.calledAE)' ≠ '\(aeTitle)'")
                try? await conn.send(SimplePDU.associateRJ(result: 1, source: 1, reason: 7))
                conn.close()
                return
            }
            var acContexts: [PresentationContext] = []
            var accepted: [UInt8: PresentationContext] = [:]
            for pc in rq.contexts {
                var result: UInt8 = 0
                var ts = ""
                if Self.rejectedPrefixes.contains(where: { pc.abstractSyntax.hasPrefix($0) }) {
                    result = 3
                } else if let chosen = [TransferSyntax.explicitLE, TransferSyntax.implicitLE].first(where: { pc.transferSyntaxes.contains($0) })
                            ?? pc.transferSyntaxes.first(where: { $0 != TransferSyntax.explicitBE }) {
                    ts = chosen
                } else {
                    result = 4
                }
                acContexts.append(PresentationContext(id: pc.id, abstractSyntax: pc.abstractSyntax,
                                                      transferSyntaxes: [ts.isEmpty ? TransferSyntax.implicitLE : ts], result: result))
                if result == 0 {
                    accepted[pc.id] = PresentationContext(id: pc.id, abstractSyntax: pc.abstractSyntax, transferSyntaxes: [ts])
                }
            }
            let ac = AssociatePDU(calledAE: rq.calledAE, callingAE: rq.callingAE, contexts: acContexts, maxPDULength: 65536)
            try await conn.send(ac.encode(type: PDUType.associateAC))
            log?("  A-ASSOCIATE-AC: \(accepted.count)/\(rq.contexts.count) Presentation Context(s) akzeptiert")
            let assoc = Association(connection: conn, peerMaxPDU: rq.maxPDULength, contexts: accepted,
                                    callingAE: rq.callingAE, calledAE: rq.calledAE, peerImplementation: rq.implementationVersion)
            var stored = 0
            while true {
                let msg: DimseMessage
                do {
                    msg = try await assoc.receiveMessage()
                } catch DicomError.peerReleased {
                    log?("Assoziation von \(rq.callingAE) beendet (\(stored) Objekt(e) empfangen)")
                    return
                }
                let cmd = msg.command
                let msgID = cmd.uint16(.messageID) ?? 0
                let sopClass = cmd.string(.affectedSOPClassUID) ?? ""
                var rsp = DataSet()
                rsp.set(.affectedSOPClassUID, sopClass)
                rsp.setUInt16(.messageIDBeingRespondedTo, msgID)
                switch msg.commandField {
                case 0x0030:
                    rsp.setUInt16(.commandField, 0x8030)
                    rsp.setUInt16(.status, 0)
                    log?("  C-ECHO von \(rq.callingAE) beantwortet")
                case 0x0001:
                    let sopInstance = cmd.string(.affectedSOPInstanceUID) ?? UIDGenerator.make()
                    rsp.setUInt16(.commandField, 0x8001)
                    rsp.set(.affectedSOPInstanceUID, sopInstance)
                    let ts = assoc.contexts[msg.pcid]?.transferSyntax ?? TransferSyntax.implicitLE
                    let status = save(dataset: msg.dataset ?? Data(), sopClass: sopClass, sopInstance: sopInstance,
                                      ts: ts, callingAE: rq.callingAE, remote: remote)
                    rsp.setUInt16(.status, status)
                    if status == 0 { stored += 1 }
                default:
                    rsp.setUInt16(.commandField, msg.commandField | 0x8000)
                    rsp.setUInt16(.status, 0x0211)
                    log?("  Nicht unterstütztes Kommando 0x\(String(msg.commandField, radix: 16))")
                }
                try await assoc.send(command: rsp, dataset: nil, pcid: msg.pcid)
            }
        } catch {
            log?("Verbindung \(remote): \(error.localizedDescription)")
            conn.close()
        }
    }

    private func save(dataset: Data, sopClass: String, sopInstance: String, ts: String, callingAE: String, remote: String) -> UInt16 {
        var ds = DataSet()
        if TransferSyntax.isUncompressedLE(ts) || (ts != TransferSyntax.deflatedLE && ts != TransferSyntax.explicitBE) {
            // Only the header attributes are needed; stop parsing before pixel data errors matter.
            var p = DataSetParser(data: dataset)
            let explicit = TransferSyntax.isExplicit(ts)
            while p.pos + 8 <= dataset.count, dataset.u16le(p.pos) < 0x7FE0 {
                guard let el = try? p.parseElement(explicit: explicit) else { break }
                ds[el.tag] = el
            }
        }
        let patientID = ds.string(.patientID).flatMap { $0.isEmpty ? nil : $0 } ?? "UNBEKANNT"
        let safeID = patientID.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let dir = storageDirectory.appendingPathComponent(safeID, isDirectory: true)
        let url = dir.appendingPathComponent(sopInstance + ".dcm")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try DicomFile.write(to: url, sopClass: sopClass, sopInstance: sopInstance, transferSyntax: ts,
                                datasetBytes: dataset, sourceAE: callingAE)
        } catch {
            log?("  Speichern fehlgeschlagen: \(error.localizedDescription)")
            return 0xA700
        }
        let obj = ReceivedObject(date: Date(), callingAE: callingAE, remote: remote,
                                 patientName: ds.string(.patientName) ?? "", patientID: patientID,
                                 modality: ds.string(.modality) ?? "", sopClassUID: sopClass, sopInstanceUID: sopInstance,
                                 transferSyntax: ts, size: dataset.count, path: url)
        log?("  C-STORE \(SOPClass.name(sopClass)) – \(obj.patientName) [\(patientID)] gespeichert")
        onReceived?(obj)
        return 0
    }
}
