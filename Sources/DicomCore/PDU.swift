import Foundation

public struct PresentationContext: Sendable {
    public var id: UInt8
    public var abstractSyntax: String
    public var transferSyntaxes: [String]
    public var result: UInt8 = 0

    public init(id: UInt8, abstractSyntax: String, transferSyntaxes: [String], result: UInt8 = 0) {
        self.id = id; self.abstractSyntax = abstractSyntax; self.transferSyntaxes = transferSyntaxes; self.result = result
    }

    public var transferSyntax: String { transferSyntaxes.first ?? TransferSyntax.implicitLE }

    public static func resultText(_ r: UInt8) -> String {
        switch r {
        case 0: return "akzeptiert"
        case 1: return "abgelehnt (User)"
        case 2: return "abgelehnt (kein Grund)"
        case 3: return "abgelehnt (Abstract Syntax nicht unterstützt)"
        case 4: return "abgelehnt (Transfer Syntax nicht unterstützt)"
        default: return "Ergebnis \(r)"
        }
    }
}

enum PDUType {
    static let associateRQ: UInt8 = 0x01
    static let associateAC: UInt8 = 0x02
    static let associateRJ: UInt8 = 0x03
    static let pData: UInt8 = 0x04
    static let releaseRQ: UInt8 = 0x05
    static let releaseRP: UInt8 = 0x06
    static let abort: UInt8 = 0x07
}

let applicationContextName = "1.2.840.10008.3.1.1.1"

/// A-ASSOCIATE-RQ and -AC share the same layout.
public struct AssociatePDU {
    public var calledAE: String
    public var callingAE: String
    public var contexts: [PresentationContext]
    public var maxPDULength: UInt32 = 65536
    public var implementationClassUID = Implementation.classUID
    public var implementationVersion = Implementation.versionName

    public func encode(type: UInt8) -> Data {
        var body = Data()
        body.appendU16BE(1)
        body.appendU16BE(0)
        body.append(Self.aeField(calledAE))
        body.append(Self.aeField(callingAE))
        body.append(Data(count: 32))
        Self.appendItem(&body, 0x10, Data(applicationContextName.utf8))
        for pc in contexts {
            var sub = Data([pc.id, 0, type == PDUType.associateAC ? pc.result : 0, 0])
            if type == PDUType.associateRQ {
                Self.appendItem(&sub, 0x30, Data(pc.abstractSyntax.utf8))
                for ts in pc.transferSyntaxes { Self.appendItem(&sub, 0x40, Data(ts.utf8)) }
            } else {
                Self.appendItem(&sub, 0x40, Data(pc.transferSyntax.utf8))
            }
            Self.appendItem(&body, type == PDUType.associateRQ ? 0x20 : 0x21, sub)
        }
        var user = Data()
        var maxLen = Data(); maxLen.appendU32BE(maxPDULength)
        Self.appendItem(&user, 0x51, maxLen)
        Self.appendItem(&user, 0x52, Data(implementationClassUID.utf8))
        Self.appendItem(&user, 0x55, Data(implementationVersion.utf8))
        Self.appendItem(&body, 0x50, user)
        return Self.pdu(type, body)
    }

    public static func decode(_ body: Data) throws -> AssociatePDU {
        guard body.count >= 68 else { throw DicomError.protocolError("A-ASSOCIATE zu kurz") }
        var pdu = AssociatePDU(calledAE: aeString(body.sub(4, 16)), callingAE: aeString(body.sub(20, 16)), contexts: [])
        pdu.implementationClassUID = ""
        pdu.implementationVersion = ""
        var off = 68
        while off + 4 <= body.count {
            let type = body.u8(off)
            let len = Int(body.u16be(off + 2))
            guard off + 4 + len <= body.count else { throw DicomError.protocolError("Item-Länge ungültig") }
            let v = body.sub(off + 4, len)
            off += 4 + len
            switch type {
            case 0x20, 0x21:
                guard v.count >= 4 else { continue }
                var pc = PresentationContext(id: v.u8(0), abstractSyntax: "", transferSyntaxes: [], result: v.u8(2))
                forEachItem(v, from: 4) { t, d in
                    if t == 0x30 { pc.abstractSyntax = uidString(d) }
                    if t == 0x40 { pc.transferSyntaxes.append(uidString(d)) }
                }
                pdu.contexts.append(pc)
            case 0x50:
                forEachItem(v, from: 0) { t, d in
                    if t == 0x51, d.count >= 4 { pdu.maxPDULength = d.u32be(0) }
                    if t == 0x52 { pdu.implementationClassUID = uidString(d) }
                    if t == 0x55 { pdu.implementationVersion = uidString(d) }
                }
            default: break
            }
        }
        return pdu
    }

    static func forEachItem(_ d: Data, from start: Int, _ f: (UInt8, Data) -> Void) {
        var o = start
        while o + 4 <= d.count {
            let t = d.u8(o), l = Int(d.u16be(o + 2))
            guard o + 4 + l <= d.count else { return }
            f(t, d.sub(o + 4, l))
            o += 4 + l
        }
    }

    static func appendItem(_ out: inout Data, _ type: UInt8, _ value: Data) {
        out.append(type); out.append(0)
        out.appendU16BE(UInt16(value.count))
        out.append(value)
    }

    static func pdu(_ type: UInt8, _ body: Data) -> Data {
        var d = Data([type, 0])
        d.appendU32BE(UInt32(body.count))
        d.append(body)
        return d
    }

    static func aeField(_ s: String) -> Data {
        var d = Data(s.prefix(16).utf8)
        while d.count < 16 { d.append(0x20) }
        return d
    }

    static func aeString(_ d: Data) -> String { uidString(d) }

    static func uidString(_ d: Data) -> String {
        (String(data: d, encoding: .ascii) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
    }
}

enum SimplePDU {
    static func associateRJ(result: UInt8, source: UInt8, reason: UInt8) -> Data {
        AssociatePDU.pdu(PDUType.associateRJ, Data([0, result, source, reason]))
    }
    static var releaseRQ: Data { AssociatePDU.pdu(PDUType.releaseRQ, Data(count: 4)) }
    static var releaseRP: Data { AssociatePDU.pdu(PDUType.releaseRP, Data(count: 4)) }
    static func abort(source: UInt8 = 0, reason: UInt8 = 0) -> Data {
        AssociatePDU.pdu(PDUType.abort, Data([0, 0, source, reason]))
    }
}
