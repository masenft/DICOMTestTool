import Foundation

public struct DicomElement {
    public var tag: Tag
    public var vr: VR
    public var data: Data
    public var items: [DataSet]?
    public var fragments: [Data]?

    public init(tag: Tag, vr: VR, data: Data = Data(), items: [DataSet]? = nil, fragments: [Data]? = nil) {
        self.tag = tag; self.vr = vr; self.data = data; self.items = items; self.fragments = fragments
    }

    public var stringValue: String? {
        guard items == nil, fragments == nil, vr.isString || vr == .UN else { return nil }
        return DicomString.decode(data)
    }

    /// Human readable value for tag dumps.
    public var displayValue: String {
        if let items { return "Sequenz mit \(items.count) Item(s)" }
        if let fragments { return "Encapsulated: \(max(fragments.count - 1, 0)) Fragment(e) + Offset-Tabelle" }
        if vr.isString {
            let s = DicomString.decode(data)
            return s.count > 256 ? String(s.prefix(256)) + "…" : s
        }
        func list<T>(_ size: Int, _ f: (Int) -> T) -> String {
            let n = data.count / size
            let shown = (0..<min(n, 16)).map { "\(f($0 * size))" }.joined(separator: "\\")
            return n > 16 ? shown + "\\… (\(n) Werte)" : shown
        }
        switch vr {
        case .US: return list(2) { data.u16le($0) }
        case .SS: return list(2) { Int16(bitPattern: data.u16le($0)) }
        case .UL: return list(4) { data.u32le($0) }
        case .SL: return list(4) { Int32(bitPattern: data.u32le($0)) }
        case .FL: return list(4) { Float(bitPattern: data.u32le($0)) }
        case .FD: return list(8) { o -> Double in
            Double(bitPattern: UInt64(data.u32le(o)) | UInt64(data.u32le(o + 4)) << 32)
        }
        case .AT: return list(4) { Tag(data.u16le($0), data.u16le($0 + 2)).description }
        default:
            let hex = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            return "<\(data.count) Bytes> \(hex)\(data.count > 16 ? " …" : "")"
        }
    }
}

public struct DataSet {
    public var elements: [Tag: DicomElement] = [:]
    public init() {}

    public var isEmpty: Bool { elements.isEmpty }
    public var sorted: [DicomElement] { elements.values.sorted { $0.tag < $1.tag } }

    public subscript(tag: Tag) -> DicomElement? {
        get { elements[tag] }
        set { elements[tag] = newValue }
    }

    public mutating func set(_ tag: Tag, _ value: String, vr: VR? = nil) {
        let v = vr ?? DicomDictionary.vr(for: tag)
        elements[tag] = DicomElement(tag: tag, vr: v, data: DicomString.encode(value, vr: v))
    }

    public mutating func setUInt16(_ tag: Tag, _ value: UInt16) {
        var d = Data(); d.appendU16LE(value)
        elements[tag] = DicomElement(tag: tag, vr: .US, data: d)
    }

    public mutating func setUInt32(_ tag: Tag, _ value: UInt32) {
        var d = Data(); d.appendU32LE(value)
        elements[tag] = DicomElement(tag: tag, vr: .UL, data: d)
    }

    public mutating func setSequence(_ tag: Tag, _ items: [DataSet]) {
        elements[tag] = DicomElement(tag: tag, vr: .SQ, items: items)
    }

    public mutating func remove(_ tag: Tag) { elements[tag] = nil }

    public func string(_ tag: Tag) -> String? { elements[tag]?.stringValue }

    public func uint16(_ tag: Tag) -> UInt16? {
        guard let e = elements[tag], e.data.count >= 2 else { return nil }
        return e.data.u16le(0)
    }

    public func int(_ tag: Tag) -> Int? {
        guard let e = elements[tag] else { return nil }
        switch e.vr {
        case .US: return e.data.count >= 2 ? Int(e.data.u16le(0)) : nil
        case .SS: return e.data.count >= 2 ? Int(Int16(bitPattern: e.data.u16le(0))) : nil
        case .UL: return e.data.count >= 4 ? Int(e.data.u32le(0)) : nil
        case .SL: return e.data.count >= 4 ? Int(Int32(bitPattern: e.data.u32le(0))) : nil
        default:
            guard let s = e.stringValue?.split(separator: "\\").first else { return nil }
            return Int(s.trimmingCharacters(in: .whitespaces))
        }
    }

    public func doubles(_ tag: Tag) -> [Double] {
        guard let s = string(tag) else { return [] }
        return s.split(separator: "\\").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    public func items(_ tag: Tag) -> [DataSet] { elements[tag]?.items ?? [] }

    // MARK: Encoding (little endian)

    public func encoded(explicit: Bool) -> Data {
        var out = Data()
        for el in sorted {
            if el.tag.element == 0x0000 && el.tag.group >= 0x0008 { continue } // stale group lengths
            DataSet.encode(el, into: &out, explicit: explicit)
        }
        return out
    }

    static func encode(_ el: DicomElement, into out: inout Data, explicit: Bool) {
        out.appendU16LE(el.tag.group)
        out.appendU16LE(el.tag.element)
        if let items = el.items {
            var body = Data()
            for item in items {
                let d = item.encoded(explicit: explicit)
                body.appendU16LE(0xFFFE); body.appendU16LE(0xE000); body.appendU32LE(UInt32(d.count))
                body.append(d)
            }
            writeHeader(&out, vr: .SQ, length: UInt32(body.count), explicit: explicit)
            out.append(body)
        } else if let frags = el.fragments {
            writeHeader(&out, vr: .OB, length: 0xFFFF_FFFF, explicit: explicit)
            for f in frags {
                var f = f
                if f.count % 2 == 1 { f.append(0) }
                out.appendU16LE(0xFFFE); out.appendU16LE(0xE000); out.appendU32LE(UInt32(f.count))
                out.append(f)
            }
            out.appendU16LE(0xFFFE); out.appendU16LE(0xE0DD); out.appendU32LE(0)
        } else {
            var v = el.data
            if v.count % 2 == 1 { v.append(el.vr.isString && el.vr != .UI ? 0x20 : 0x00) }
            var vr = el.vr
            if explicit && !vr.usesLongLength && v.count > 0xFFFF { vr = .UN }
            writeHeader(&out, vr: vr, length: UInt32(v.count), explicit: explicit)
            out.append(v)
        }
    }

    private static func writeHeader(_ out: inout Data, vr: VR, length: UInt32, explicit: Bool) {
        if explicit {
            out.appendASCII(vr.rawValue)
            if vr.usesLongLength {
                out.appendU16LE(0)
                out.appendU32LE(length)
            } else {
                out.appendU16LE(UInt16(length))
            }
        } else {
            out.appendU32LE(length)
        }
    }

    // MARK: Decoding

    public static func parse(_ data: Data, explicit: Bool) throws -> DataSet {
        var p = DataSetParser(data: data)
        return try p.parseDataSet(until: data.count, explicit: explicit)
    }
}

enum DicomString {
    static func decode(_ d: Data) -> String {
        let s = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) ?? ""
        var scalars = Substring(s)
        while let last = scalars.last, last == " " || last == "\0" { scalars = scalars.dropLast() }
        while let first = scalars.first, first == " " { scalars = scalars.dropFirst() }
        return String(scalars)
    }

    static func encode(_ s: String, vr: VR) -> Data {
        var d = s.data(using: .isoLatin1) ?? Data(s.utf8)
        if d.count % 2 == 1 { d.append(vr == .UI ? 0x00 : 0x20) }
        return d
    }
}

struct DataSetParser {
    let data: Data
    var pos = 0
    private static let undefined: UInt32 = 0xFFFF_FFFF

    init(data: Data, pos: Int = 0) {
        self.data = data
        self.pos = pos
    }

    private func need(_ n: Int) throws {
        if pos + n > data.count { throw DicomError.parse("Daten abgeschnitten bei Offset \(pos)") }
    }

    mutating func parseDataSet(until end: Int, explicit: Bool) throws -> DataSet {
        var ds = DataSet()
        while pos + 8 <= end {
            if data.u16le(pos) == 0xFFFE {
                let e = data.u16le(pos + 2)
                if e == 0xE00D || e == 0xE0DD { pos += 8; return ds }
            }
            let el = try parseElement(explicit: explicit)
            ds[el.tag] = el
        }
        if pos < end { pos = end }
        return ds
    }

    mutating func parseElement(explicit: Bool) throws -> DicomElement {
        try need(8)
        let tag = Tag(data.u16le(pos), data.u16le(pos + 2))
        pos += 4
        var vr: VR
        var length: UInt32
        if explicit, tag.group != 0xFFFE,
           let s = String(bytes: [data.u8(pos), data.u8(pos + 1)], encoding: .ascii), let v = VR(rawValue: s) {
            vr = v
            pos += 2
            if v.usesLongLength {
                try need(6)
                length = data.u32le(pos + 2)
                pos += 6
            } else {
                length = UInt32(data.u16le(pos))
                pos += 2
            }
        } else {
            vr = DicomDictionary.vr(for: tag)
            length = data.u32le(pos)
            pos += 4
        }

        if vr == .SQ || (length == Self.undefined && vr == .UN) {
            let items = try parseSequence(length: length, explicit: vr == .UN ? false : explicit)
            return DicomElement(tag: tag, vr: .SQ, items: items)
        }
        if length == Self.undefined {
            guard tag == .pixelData || vr == .OB || vr == .OW else {
                throw DicomError.parse("Undefinierte Länge bei \(tag)")
            }
            return DicomElement(tag: tag, vr: .OB, fragments: try parseFragments())
        }
        let n = Int(length)
        try need(n)
        let value = data.sub(pos, n)
        pos += n
        return DicomElement(tag: tag, vr: vr, data: value)
    }

    private mutating func parseSequence(length: UInt32, explicit: Bool) throws -> [DataSet] {
        var items: [DataSet] = []
        let end = length == Self.undefined ? data.count : pos + Int(length)
        while pos + 8 <= end {
            let g = data.u16le(pos), e = data.u16le(pos + 2), l = data.u32le(pos + 4)
            pos += 8
            guard g == 0xFFFE else { throw DicomError.parse("Item-Tag erwartet bei Offset \(pos - 8)") }
            if e == 0xE0DD { return items }
            guard e == 0xE000 else { continue }
            if l == Self.undefined {
                items.append(try parseDataSet(until: data.count, explicit: explicit))
            } else {
                let itemEnd = pos + Int(l)
                guard itemEnd <= data.count else { throw DicomError.parse("Item länger als Daten") }
                items.append(try parseDataSet(until: itemEnd, explicit: explicit))
                pos = itemEnd
            }
        }
        if length != Self.undefined { pos = end }
        return items
    }

    private mutating func parseFragments() throws -> [Data] {
        var frags: [Data] = []
        while pos + 8 <= data.count {
            let g = data.u16le(pos), e = data.u16le(pos + 2), l = Int(data.u32le(pos + 4))
            pos += 8
            guard g == 0xFFFE else { throw DicomError.parse("Fragment-Item erwartet") }
            if e == 0xE0DD { return frags }
            try need(l)
            frags.append(data.sub(pos, l))
            pos += l
        }
        return frags
    }
}

// MARK: - Part 10 files

public struct DicomFile {
    public var meta: DataSet
    public var dataset: DataSet
    public var transferSyntax: String
    public var datasetBytes: Data
    public var hasPart10Header: Bool
    public var parseError: String?

    public var sopClassUID: String? { meta.string(.mediaStorageSOPClassUID) ?? dataset.string(.sopClassUID) }
    public var sopInstanceUID: String? { meta.string(.mediaStorageSOPInstanceUID) ?? dataset.string(.sopInstanceUID) }

    public static func read(_ url: URL, parseDataset: Bool = true) throws -> DicomFile {
        try parse(try Data(contentsOf: url, options: .mappedIfSafe), parseDataset: parseDataset)
    }

    public static func isDicomFile(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "dcm" { return true }
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 132), d.count == 132 else { return false }
        return d.sub(128, 4) == Data("DICM".utf8)
    }

    public static func parse(_ data: Data, parseDataset: Bool = true) throws -> DicomFile {
        var meta = DataSet()
        var offset = 0
        var ts = TransferSyntax.implicitLE
        var part10 = false
        if data.count >= 132, data.sub(128, 4) == Data("DICM".utf8) {
            part10 = true
            var p = DataSetParser(data: data, pos: 132)
            while p.pos + 8 <= data.count, data.u16le(p.pos) == 0x0002 {
                let el = try p.parseElement(explicit: true)
                meta[el.tag] = el
            }
            offset = p.pos
            ts = meta.string(.transferSyntaxUID) ?? TransferSyntax.explicitLE
        } else if data.count >= 8,
                  let s = String(bytes: [data.u8(4), data.u8(5)], encoding: .ascii), VR(rawValue: s) != nil {
            ts = TransferSyntax.explicitLE
        } else if data.count < 8 {
            throw DicomError.parse("Datei zu kurz")
        }
        let dsBytes = data.sub(offset, data.count - offset)
        var file = DicomFile(meta: meta, dataset: DataSet(), transferSyntax: ts, datasetBytes: dsBytes,
                             hasPart10Header: part10, parseError: nil)
        let mustParse = parseDataset || meta.string(.mediaStorageSOPClassUID) == nil
        guard mustParse else { return file }
        if ts == TransferSyntax.deflatedLE || ts == TransferSyntax.explicitBE {
            file.parseError = "Transfer Syntax \(TransferSyntax.name(ts)) wird beim Lesen nicht unterstützt"
            return file
        }
        var p = DataSetParser(data: dsBytes)
        let explicit = TransferSyntax.isExplicit(ts)
        while p.pos + 8 <= dsBytes.count {
            do {
                let el = try p.parseElement(explicit: explicit)
                file.dataset[el.tag] = el
            } catch {
                file.parseError = error.localizedDescription
                break
            }
        }
        return file
    }

    public static func metaHeader(sopClass: String, sopInstance: String, transferSyntax: String, sourceAE: String?) -> Data {
        var m = DataSet()
        m[.fileMetaInformationVersion] = DicomElement(tag: .fileMetaInformationVersion, vr: .OB, data: Data([0, 1]))
        m.set(.mediaStorageSOPClassUID, sopClass)
        m.set(.mediaStorageSOPInstanceUID, sopInstance)
        m.set(.transferSyntaxUID, transferSyntax)
        m.set(.implementationClassUID, Implementation.classUID)
        m.set(.implementationVersionName, Implementation.versionName)
        if let sourceAE, !sourceAE.isEmpty { m.set(.sourceApplicationEntityTitle, sourceAE) }
        let body = m.encoded(explicit: true)
        var out = Data(count: 128)
        out.appendASCII("DICM")
        out.appendU16LE(0x0002); out.appendU16LE(0x0000); out.appendASCII("UL"); out.appendU16LE(4)
        out.appendU32LE(UInt32(body.count))
        out.append(body)
        return out
    }

    public static func write(to url: URL, sopClass: String, sopInstance: String, transferSyntax: String,
                             datasetBytes: Data, sourceAE: String? = nil) throws {
        var d = metaHeader(sopClass: sopClass, sopInstance: sopInstance, transferSyntax: transferSyntax, sourceAE: sourceAE)
        d.append(datasetBytes)
        try d.write(to: url, options: .atomic)
    }

    /// Dataset bytes in the requested (uncompressed) transfer syntax.
    public func datasetBytes(in target: String) throws -> Data {
        if target == transferSyntax { return datasetBytes }
        guard TransferSyntax.isUncompressedLE(target), TransferSyntax.isUncompressedLE(transferSyntax) else {
            throw DicomError.unsupported("Konvertierung \(TransferSyntax.name(transferSyntax)) → \(TransferSyntax.name(target))")
        }
        let ds = dataset.isEmpty ? try DataSet.parse(datasetBytes, explicit: TransferSyntax.isExplicit(transferSyntax)) : dataset
        return ds.encoded(explicit: TransferSyntax.isExplicit(target))
    }
}
