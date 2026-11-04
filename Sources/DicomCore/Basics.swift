import Foundation

// MARK: - Byte helpers

extension Data {
    @inline(__always) func u8(_ o: Int) -> UInt8 { self[startIndex + o] }
    @inline(__always) func u16le(_ o: Int) -> UInt16 { UInt16(u8(o)) | UInt16(u8(o + 1)) << 8 }
    @inline(__always) func u32le(_ o: Int) -> UInt32 { UInt32(u16le(o)) | UInt32(u16le(o + 2)) << 16 }
    @inline(__always) func u16be(_ o: Int) -> UInt16 { UInt16(u8(o)) << 8 | UInt16(u8(o + 1)) }
    @inline(__always) func u32be(_ o: Int) -> UInt32 { UInt32(u16be(o)) << 16 | UInt32(u16be(o + 2)) }
    func sub(_ o: Int, _ n: Int) -> Data { subdata(in: (startIndex + o)..<(startIndex + o + n)) }

    mutating func appendU16LE(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func appendU32LE(_ v: UInt32) { appendU16LE(UInt16(v & 0xFFFF)); appendU16LE(UInt16(v >> 16)) }
    mutating func appendU16BE(_ v: UInt16) { append(UInt8(v >> 8)); append(UInt8(v & 0xFF)) }
    mutating func appendU32BE(_ v: UInt32) { appendU16BE(UInt16(v >> 16)); appendU16BE(UInt16(v & 0xFFFF)) }
    mutating func appendASCII(_ s: String) { append(contentsOf: Array(s.utf8)) }
}

// MARK: - Tag / VR

public struct Tag: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let group: UInt16
    public let element: UInt16
    public init(_ group: UInt16, _ element: UInt16) { self.group = group; self.element = element }
    public init(raw: UInt32) { group = UInt16(raw >> 16); element = UInt16(raw & 0xFFFF) }
    public var raw: UInt32 { UInt32(group) << 16 | UInt32(element) }
    public static func < (a: Tag, b: Tag) -> Bool { a.raw < b.raw }
    public var description: String { String(format: "(%04X,%04X)", group, element) }
    public var isPrivate: Bool { group % 2 == 1 }
    public var name: String { DicomDictionary.name(for: self) }
}

public enum VR: String, Sendable, CaseIterable {
    case AE, AS, AT, CS, DA, DS, DT, FL, FD, IS, LO, LT, OB, OD, OF, OL, OV, OW, PN, SH, SL, SQ, SS, ST, SV, TM, UC, UI, UL, UN, UR, US, UT, UV

    public var usesLongLength: Bool {
        switch self {
        case .OB, .OD, .OF, .OL, .OV, .OW, .SQ, .UC, .UN, .UR, .UT, .SV, .UV: return true
        default: return false
        }
    }

    public var isString: Bool {
        switch self {
        case .AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .PN, .SH, .ST, .TM, .UC, .UI, .UR, .UT: return true
        default: return false
        }
    }
}

// MARK: - Errors

public enum DicomError: LocalizedError {
    case parse(String)
    case connectionClosed
    case timeout
    case rejected(result: UInt8, source: UInt8, reason: UInt8)
    case aborted(source: UInt8, reason: UInt8)
    case protocolError(String)
    case noPresentationContext(String)
    case peerReleased
    case unsupported(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .parse(let m): return "Parse-Fehler: \(m)"
        case .connectionClosed: return "Verbindung wurde geschlossen"
        case .timeout: return "Zeitüberschreitung"
        case .rejected(let r, let s, let reason):
            return "Assoziation abgelehnt (\(r == 1 ? "permanent" : "vorübergehend")): \(Self.rejectReason(source: s, reason: reason))"
        case .aborted(let s, let r): return "Assoziation abgebrochen (A-ABORT, Quelle \(s), Grund \(r))"
        case .protocolError(let m): return "Protokollfehler: \(m)"
        case .noPresentationContext(let m): return "Kein akzeptierter Presentation Context: \(m)"
        case .peerReleased: return "Gegenstelle hat die Assoziation beendet"
        case .unsupported(let m): return "Nicht unterstützt: \(m)"
        case .cancelled: return "Abgebrochen"
        }
    }

    static func rejectReason(source: UInt8, reason: UInt8) -> String {
        switch (source, reason) {
        case (1, 1): return "kein Grund angegeben (Service-User)"
        case (1, 2): return "Application Context nicht unterstützt"
        case (1, 3): return "Calling AE-Titel nicht erkannt"
        case (1, 7): return "Called AE-Titel nicht erkannt"
        case (2, 1): return "kein Grund angegeben (Service-Provider ACSE)"
        case (2, 2): return "Protokollversion nicht unterstützt"
        case (3, 1): return "temporäre Überlastung"
        case (3, 2): return "lokales Limit überschritten"
        default: return "Quelle \(source), Grund \(reason)"
        }
    }
}

// MARK: - UIDs

public enum Implementation {
    public static let classUID = "2.25.287369152410984711452391287430987123"
    public static let versionName = "DICOMTEST_1.0"
}

public enum UIDGenerator {
    /// UUID-derived UID under the 2.25 root (ISO/IEC 9834-8).
    public static func make() -> String {
        let u = UUID().uuid
        let bytes = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
        var hi: UInt64 = 0, lo: UInt64 = 0
        for i in 0..<8 { hi = hi << 8 | UInt64(bytes[i]) }
        for i in 8..<16 { lo = lo << 8 | UInt64(bytes[i]) }
        if hi == 0 && lo == 0 { return "2.25.0" }
        var digits: [Character] = []
        while hi != 0 || lo != 0 {
            let (qHi, rHi) = hi.quotientAndRemainder(dividingBy: 10)
            let (qLo, r) = UInt64(10).dividingFullWidth((high: rHi, low: lo))
            hi = qHi; lo = qLo
            digits.append(Character(String(r)))
        }
        return "2.25." + String(digits.reversed())
    }
}

public enum TransferSyntax {
    public static let implicitLE = "1.2.840.10008.1.2"
    public static let explicitLE = "1.2.840.10008.1.2.1"
    public static let deflatedLE = "1.2.840.10008.1.2.1.99"
    public static let explicitBE = "1.2.840.10008.1.2.2"

    public static let names: [String: String] = [
        implicitLE: "Implicit VR Little Endian",
        explicitLE: "Explicit VR Little Endian",
        deflatedLE: "Deflated Explicit VR Little Endian",
        explicitBE: "Explicit VR Big Endian",
        "1.2.840.10008.1.2.4.50": "JPEG Baseline (Process 1)",
        "1.2.840.10008.1.2.4.51": "JPEG Extended (Process 2 & 4)",
        "1.2.840.10008.1.2.4.57": "JPEG Lossless (Process 14)",
        "1.2.840.10008.1.2.4.70": "JPEG Lossless SV1",
        "1.2.840.10008.1.2.4.80": "JPEG-LS Lossless",
        "1.2.840.10008.1.2.4.81": "JPEG-LS Near-Lossless",
        "1.2.840.10008.1.2.4.90": "JPEG 2000 Lossless",
        "1.2.840.10008.1.2.4.91": "JPEG 2000",
        "1.2.840.10008.1.2.4.100": "MPEG2 Main Profile",
        "1.2.840.10008.1.2.4.102": "MPEG-4 AVC/H.264",
        "1.2.840.10008.1.2.4.201": "HTJ2K Lossless",
        "1.2.840.10008.1.2.4.203": "HTJ2K",
        "1.2.840.10008.1.2.5": "RLE Lossless",
    ]

    public static func name(_ uid: String) -> String { names[uid] ?? uid }
    public static func isExplicit(_ uid: String) -> Bool { uid != implicitLE }
    public static func isUncompressedLE(_ uid: String) -> Bool { uid == implicitLE || uid == explicitLE }
}

public enum SOPClass {
    public static let verification = "1.2.840.10008.1.1"
    public static let patientRootFind = "1.2.840.10008.5.1.4.1.2.1.1"
    public static let patientRootMove = "1.2.840.10008.5.1.4.1.2.1.2"
    public static let studyRootFind = "1.2.840.10008.5.1.4.1.2.2.1"
    public static let studyRootMove = "1.2.840.10008.5.1.4.1.2.2.2"
    public static let modalityWorklistFind = "1.2.840.10008.5.1.4.31"
    public static let secondaryCapture = "1.2.840.10008.5.1.4.1.1.7"

    public static let names: [String: String] = [
        verification: "Verification",
        patientRootFind: "Patient Root Q/R – FIND",
        patientRootMove: "Patient Root Q/R – MOVE",
        studyRootFind: "Study Root Q/R – FIND",
        studyRootMove: "Study Root Q/R – MOVE",
        modalityWorklistFind: "Modality Worklist – FIND",
        "1.2.840.10008.5.1.4.1.1.1": "CR Image Storage",
        "1.2.840.10008.5.1.4.1.1.1.1": "Digital X-Ray Image Storage – Presentation",
        "1.2.840.10008.5.1.4.1.1.1.1.1": "Digital X-Ray Image Storage – Processing",
        "1.2.840.10008.5.1.4.1.1.1.2": "Digital Mammography Image Storage – Presentation",
        "1.2.840.10008.5.1.4.1.1.1.3": "Digital Intra-Oral X-Ray Image Storage – Presentation",
        "1.2.840.10008.5.1.4.1.1.2": "CT Image Storage",
        "1.2.840.10008.5.1.4.1.1.2.1": "Enhanced CT Image Storage",
        "1.2.840.10008.5.1.4.1.1.3.1": "Ultrasound Multi-frame Image Storage",
        "1.2.840.10008.5.1.4.1.1.4": "MR Image Storage",
        "1.2.840.10008.5.1.4.1.1.4.1": "Enhanced MR Image Storage",
        "1.2.840.10008.5.1.4.1.1.6.1": "Ultrasound Image Storage",
        secondaryCapture: "Secondary Capture Image Storage",
        "1.2.840.10008.5.1.4.1.1.7.4": "Multi-frame True Color SC Image Storage",
        "1.2.840.10008.5.1.4.1.1.11.1": "Grayscale Softcopy Presentation State",
        "1.2.840.10008.5.1.4.1.1.12.1": "X-Ray Angiographic Image Storage",
        "1.2.840.10008.5.1.4.1.1.13.1.3": "Breast Tomosynthesis Image Storage",
        "1.2.840.10008.5.1.4.1.1.20": "Nuclear Medicine Image Storage",
        "1.2.840.10008.5.1.4.1.1.77.1.4": "VL Photographic Image Storage",
        "1.2.840.10008.5.1.4.1.1.77.1.5.1": "Ophthalmic Photography 8 Bit Image Storage",
        "1.2.840.10008.5.1.4.1.1.88.11": "Basic Text SR",
        "1.2.840.10008.5.1.4.1.1.88.22": "Enhanced SR",
        "1.2.840.10008.5.1.4.1.1.88.33": "Comprehensive SR",
        "1.2.840.10008.5.1.4.1.1.88.59": "Key Object Selection Document",
        "1.2.840.10008.5.1.4.1.1.104.1": "Encapsulated PDF Storage",
        "1.2.840.10008.5.1.4.1.1.128": "PET Image Storage",
        "1.2.840.10008.5.1.4.1.1.481.1": "RT Image Storage",
        "1.2.840.10008.5.1.4.1.1.481.2": "RT Dose Storage",
        "1.2.840.10008.5.1.4.1.1.481.3": "RT Structure Set Storage",
        "1.2.840.10008.5.1.4.1.1.481.5": "RT Plan Storage",
    ]

    public static func name(_ uid: String) -> String { names[uid] ?? uid }
}

public enum DimseStatus {
    public static func isPending(_ s: UInt16) -> Bool { s == 0xFF00 || s == 0xFF01 }
    public static func isSuccess(_ s: UInt16) -> Bool { s == 0x0000 }
    public static func isWarning(_ s: UInt16) -> Bool { s == 0x0001 || (s & 0xF000) == 0xB000 || s == 0x0107 || s == 0x0116 }

    public static func text(_ s: UInt16) -> String {
        let hex = String(format: "0x%04X", s)
        switch s {
        case 0x0000: return "\(hex) Erfolg"
        case 0xFF00: return "\(hex) Ausstehend (Pending)"
        case 0xFF01: return "\(hex) Ausstehend (optionale Keys nicht unterstützt)"
        case 0xFE00: return "\(hex) Abgebrochen (Cancel)"
        case 0x0105: return "\(hex) Attribut nicht erkannt"
        case 0x0107: return "\(hex) Warnung: Attributliste fehlerhaft"
        case 0x0110: return "\(hex) Verarbeitungsfehler"
        case 0x0111: return "\(hex) Doppelte SOP Instance"
        case 0x0112: return "\(hex) Keine solche SOP Instance"
        case 0x0116: return "\(hex) Warnung: Attributwert außerhalb des Bereichs"
        case 0x0117: return "\(hex) Ungültige SOP Instance"
        case 0x0118: return "\(hex) Keine solche SOP-Klasse"
        case 0x0122: return "\(hex) SOP-Klasse nicht unterstützt"
        case 0x0124: return "\(hex) Nicht autorisiert"
        case 0x0211: return "\(hex) Operation nicht erkannt"
        case 0x0212: return "\(hex) Fehlerhafter Typ"
        case 0xA700...0xA7FF: return "\(hex) Fehler: Ressourcen erschöpft"
        case 0xA801: return "\(hex) Fehler: Move-Ziel unbekannt"
        case 0xA900...0xA9FF: return "\(hex) Fehler: Datensatz passt nicht zur SOP-Klasse"
        case 0xB000: return "\(hex) Warnung: Sub-Operationen mit Fehlern"
        case 0xB000...0xBFFF: return "\(hex) Warnung"
        case 0xC000...0xCFFF: return "\(hex) Fehler: kann nicht verarbeitet werden"
        default: return hex
        }
    }
}
