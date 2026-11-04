import Foundation
import Network

public typealias LogHandler = @Sendable (String) -> Void

/// Thin async wrapper around NWConnection with a receive buffer.
public final class DicomConnection: @unchecked Sendable {
    let conn: NWConnection
    private let queue = DispatchQueue(label: "dicom.connection")
    private var buffer = Data()
    private var timedOut = false
    public var timeout: TimeInterval

    public var remoteDescription: String {
        if case let .hostPort(host, port) = conn.endpoint { return "\(host):\(port)" }
        return "\(conn.endpoint)"
    }

    init(_ conn: NWConnection, timeout: TimeInterval) {
        self.conn = conn
        self.timeout = timeout
    }

    public static func connect(host: String, port: UInt16, timeout: TimeInterval) async throws -> DicomConnection {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = max(1, Int(timeout))
        tcp.noDelay = true
        guard let p = NWEndpoint.Port(rawValue: port) else { throw DicomError.protocolError("Ungültiger Port") }
        let c = NWConnection(host: NWEndpoint.Host(host), port: p, using: NWParameters(tls: nil, tcp: tcp))
        let dc = DicomConnection(c, timeout: timeout)
        try await dc.start()
        return dc
    }

    func start() async throws {
        let timeout = self.timeout
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            let finish: (Error?) -> Void = { err in
                guard !resumed else { return }
                resumed = true
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            }
            conn.stateUpdateHandler = { [conn] state in
                switch state {
                case .ready: finish(nil)
                case .failed(let e): finish(e)
                case .waiting(let e): finish(e); conn.cancel()
                case .cancelled: finish(DicomError.connectionClosed)
                default: break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout + 1) { [conn] in
                if !resumed { finish(DicomError.timeout); conn.cancel() }
            }
        }
    }

    public func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            })
        }
    }

    public func receive(exactly n: Int) async throws -> Data {
        while buffer.count < n {
            buffer.append(try await receiveChunk())
        }
        let out = buffer.sub(0, n)
        buffer = buffer.sub(n, buffer.count - n)
        return out
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let timer = DispatchWorkItem { [weak self] in
                self?.timedOut = true
                self?.conn.cancel()
            }
            if timeout > 0 { queue.asyncAfter(deadline: .now() + timeout, execute: timer) }
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
                timer.cancel()
                if let data, !data.isEmpty { cont.resume(returning: data); return }
                if self?.timedOut == true { cont.resume(throwing: DicomError.timeout); return }
                if let error { cont.resume(throwing: error); return }
                _ = isComplete
                cont.resume(throwing: DicomError.connectionClosed)
            }
        }
    }

    public func close() { conn.cancel() }
}

public struct DimseMessage {
    public var pcid: UInt8
    public var command: DataSet
    public var dataset: Data?
    public var commandField: UInt16 { command.uint16(.commandField) ?? 0 }
    public var status: UInt16 { command.uint16(.status) ?? 0xFFFF }
}

public final class Association: @unchecked Sendable {
    public let connection: DicomConnection
    public var peerMaxPDU: UInt32
    /// Accepted presentation contexts by id; `transferSyntaxes[0]` is the negotiated syntax.
    public private(set) var contexts: [UInt8: PresentationContext]
    public let callingAE: String
    public let calledAE: String
    public let peerImplementation: String
    private var messageID: UInt16 = 0

    init(connection: DicomConnection, peerMaxPDU: UInt32, contexts: [UInt8: PresentationContext],
         callingAE: String, calledAE: String, peerImplementation: String) {
        self.connection = connection
        self.peerMaxPDU = peerMaxPDU
        self.contexts = contexts
        self.callingAE = callingAE
        self.calledAE = calledAE
        self.peerImplementation = peerImplementation
    }

    public func nextMessageID() -> UInt16 {
        messageID &+= 1
        if messageID == 0 { messageID = 1 }
        return messageID
    }

    // MARK: SCU side

    public static func request(host: String, port: UInt16, callingAE: String, calledAE: String,
                               contexts: [PresentationContext], timeout: TimeInterval,
                               maxPDU: UInt32 = 65536, log: LogHandler? = nil) async throws -> Association {
        log?("Verbinde mit \(host):\(port) …")
        let conn = try await DicomConnection.connect(host: host, port: port, timeout: timeout)
        let rq = AssociatePDU(calledAE: calledAE, callingAE: callingAE, contexts: contexts, maxPDULength: maxPDU)
        log?("A-ASSOCIATE-RQ: \(callingAE) → \(calledAE), \(contexts.count) Presentation Context(s)")
        do {
            try await conn.send(rq.encode(type: PDUType.associateRQ))
            let (type, body) = try await readPDU(conn)
            switch type {
            case PDUType.associateAC:
                let ac = try AssociatePDU.decode(body)
                var accepted: [UInt8: PresentationContext] = [:]
                for pc in ac.contexts {
                    let asx = contexts.first { $0.id == pc.id }?.abstractSyntax ?? ""
                    log?("  PC \(pc.id) \(SOPClass.name(asx)): \(PresentationContext.resultText(pc.result))"
                         + (pc.result == 0 ? " – \(TransferSyntax.name(pc.transferSyntax))" : ""))
                    if pc.result == 0 {
                        accepted[pc.id] = PresentationContext(id: pc.id, abstractSyntax: asx, transferSyntaxes: [pc.transferSyntax])
                    }
                }
                log?("A-ASSOCIATE-AC erhalten (max. PDU \(ac.maxPDULength), Implementierung \(ac.implementationVersion.isEmpty ? ac.implementationClassUID : ac.implementationVersion))")
                return Association(connection: conn, peerMaxPDU: ac.maxPDULength, contexts: accepted,
                                   callingAE: callingAE, calledAE: calledAE,
                                   peerImplementation: ac.implementationVersion)
            case PDUType.associateRJ:
                conn.close()
                guard body.count >= 4 else { throw DicomError.protocolError("A-ASSOCIATE-RJ zu kurz") }
                throw DicomError.rejected(result: body.u8(1), source: body.u8(2), reason: body.u8(3))
            case PDUType.abort:
                conn.close()
                throw DicomError.aborted(source: body.count >= 4 ? body.u8(2) : 0, reason: body.count >= 4 ? body.u8(3) : 0)
            default:
                conn.close()
                throw DicomError.protocolError("Unerwartete PDU 0x\(String(type, radix: 16)) statt A-ASSOCIATE-AC")
            }
        } catch {
            conn.close()
            throw error
        }
    }

    public func context(for abstractSyntax: String, transferSyntax: String? = nil) -> PresentationContext? {
        contexts.values.sorted { $0.id < $1.id }.first {
            $0.abstractSyntax == abstractSyntax && (transferSyntax == nil || $0.transferSyntax == transferSyntax)
        }
    }

    // MARK: Messages

    public func send(command: DataSet, dataset: Data?, pcid: UInt8) async throws {
        var cmd = command
        cmd.setUInt16(.commandDataSetType, dataset == nil ? 0x0101 : 0x0000)
        cmd.remove(.commandGroupLength)
        let body = cmd.encoded(explicit: false)
        var cmdData = Data()
        cmdData.appendU16LE(0); cmdData.appendU16LE(0); cmdData.appendU32LE(4); cmdData.appendU32LE(UInt32(body.count))
        cmdData.append(body)
        try await sendPDVs(cmdData, pcid: pcid, isCommand: true)
        if let dataset { try await sendPDVs(dataset, pcid: pcid, isCommand: false) }
    }

    private func sendPDVs(_ data: Data, pcid: UInt8, isCommand: Bool) async throws {
        let limit = peerMaxPDU == 0 ? 65536 : Int(peerMaxPDU)
        let maxData = max(limit - 6, 256)
        var offset = 0
        repeat {
            let n = min(maxData, data.count - offset)
            let last = offset + n >= data.count
            var pdu = Data(capacity: n + 12)
            pdu.append(PDUType.pData); pdu.append(0)
            pdu.appendU32BE(UInt32(n + 6))
            pdu.appendU32BE(UInt32(n + 2))
            pdu.append(pcid)
            pdu.append((isCommand ? 1 : 0) | (last ? 2 : 0))
            pdu.append(data.sub(offset, n))
            try await connection.send(pdu)
            offset += n
        } while offset < data.count
    }

    public func receiveMessage() async throws -> DimseMessage {
        var cmdBuf = Data()
        var dsBuf = Data()
        var command: DataSet?
        while true {
            let (type, body) = try await Self.readPDU(connection)
            switch type {
            case PDUType.pData:
                var off = 0
                while off + 6 <= body.count {
                    let len = Int(body.u32be(off))
                    guard len >= 2, off + 4 + len <= body.count else { throw DicomError.protocolError("PDV-Länge ungültig") }
                    let pcid = body.u8(off + 4)
                    let mch = body.u8(off + 5)
                    let frag = body.sub(off + 6, len - 2)
                    off += 4 + len
                    if mch & 1 != 0 {
                        cmdBuf.append(frag)
                        if mch & 2 != 0 {
                            let cmd = try DataSet.parse(cmdBuf, explicit: false)
                            command = cmd
                            if cmd.uint16(.commandDataSetType) == 0x0101 {
                                return DimseMessage(pcid: pcid, command: cmd, dataset: nil)
                            }
                        }
                    } else {
                        guard let command else { throw DicomError.protocolError("Datensatz vor Kommando empfangen") }
                        dsBuf.append(frag)
                        if mch & 2 != 0 { return DimseMessage(pcid: pcid, command: command, dataset: dsBuf) }
                    }
                }
            case PDUType.releaseRQ:
                try? await connection.send(SimplePDU.releaseRP)
                connection.close()
                throw DicomError.peerReleased
            case PDUType.abort:
                connection.close()
                throw DicomError.aborted(source: body.count >= 4 ? body.u8(2) : 0, reason: body.count >= 4 ? body.u8(3) : 0)
            default:
                abort()
                throw DicomError.protocolError("Unerwartete PDU 0x\(String(type, radix: 16))")
            }
        }
    }

    public func release() async {
        do {
            try await connection.send(SimplePDU.releaseRQ)
            let (type, _) = try await Self.readPDU(connection)
            _ = type
        } catch {}
        connection.close()
    }

    public func abort() {
        let c = connection
        Task {
            try? await c.send(SimplePDU.abort())
            c.close()
        }
    }

    static func readPDU(_ conn: DicomConnection) async throws -> (UInt8, Data) {
        let header = try await conn.receive(exactly: 6)
        let len = Int(header.u32be(2))
        guard len < 512 * 1024 * 1024 else { throw DicomError.protocolError("PDU-Länge \(len) unplausibel") }
        let body = len > 0 ? try await conn.receive(exactly: len) : Data()
        return (header.u8(0), body)
    }
}
