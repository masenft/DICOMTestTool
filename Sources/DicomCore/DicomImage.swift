import Foundation
import CoreGraphics
import ImageIO

/// Decodes pixel data for display. Supports uncompressed monochrome/RGB and
/// encapsulated formats ImageIO can read (JPEG baseline/extended, JPEG 2000).
public final class DicomImage {
    public let rows: Int
    public let columns: Int
    public let frameCount: Int
    public let isMonochrome: Bool
    public private(set) var defaultCenter: Double = 128
    public private(set) var defaultWidth: Double = 256

    private let ds: DataSet
    private let transferSyntax: String
    private var cachedFrame = -1
    private var values: [Float] = []
    private var minValue: Float = 0
    private var maxValue: Float = 1

    public init(file: DicomFile) throws {
        ds = file.dataset
        transferSyntax = file.transferSyntax
        guard ds[.pixelData] != nil else { throw DicomError.unsupported("Keine Pixeldaten vorhanden") }
        rows = ds.int(.rows) ?? 0
        columns = ds.int(.columns) ?? 0
        guard rows > 0, columns > 0 else { throw DicomError.parse("Rows/Columns fehlen") }
        frameCount = max(1, ds.int(.numberOfFrames) ?? 1)
        isMonochrome = (ds.string(.photometricInterpretation) ?? "MONOCHROME2").hasPrefix("MONOCHROME")
        if let c = ds.doubles(.windowCenter).first, let w = ds.doubles(.windowWidth).first, w > 0 {
            defaultCenter = c; defaultWidth = w
        } else if isMonochrome, ds[.pixelData]?.fragments == nil {
            try loadFrame(0)
            defaultCenter = Double(minValue + maxValue) / 2
            defaultWidth = max(1, Double(maxValue - minValue))
        }
    }

    public var isEncapsulated: Bool { ds[.pixelData]?.fragments != nil }

    public func render(frame: Int, center: Double, width: Double) throws -> CGImage {
        let f = min(max(frame, 0), frameCount - 1)
        if let frags = ds[.pixelData]?.fragments { return try decodeEncapsulated(frags, frame: f) }
        let samples = ds.int(.samplesPerPixel) ?? 1
        if samples == 3 { return try renderRGB(frame: f) }
        try loadFrame(f)
        let lo = Float(center - 0.5 - (width - 1) / 2)
        let range = Float(max(width - 1, 1))
        let invert = ds.string(.photometricInterpretation) == "MONOCHROME1"
        var out = [UInt8](repeating: 0, count: rows * columns)
        values.withUnsafeBufferPointer { src in
            for i in 0..<src.count {
                var v = (src[i] - lo) / range * 255
                v = v < 0 ? 0 : (v > 255 ? 255 : v)
                out[i] = invert ? 255 - UInt8(v) : UInt8(v)
            }
        }
        return try makeImage(out, components: 1)
    }

    private func frameBytes(_ frame: Int, bytesPerFrame: Int) throws -> Data {
        guard let pd = ds[.pixelData]?.data else { throw DicomError.unsupported("Keine Pixeldaten") }
        let offset = frame * bytesPerFrame
        guard offset + bytesPerFrame <= pd.count else { throw DicomError.parse("Pixeldaten zu kurz") }
        return pd.sub(offset, bytesPerFrame)
    }

    private func loadFrame(_ frame: Int) throws {
        guard frame != cachedFrame else { return }
        guard transferSyntax != TransferSyntax.explicitBE else { throw DicomError.unsupported("Big Endian") }
        let bits = ds.int(.bitsAllocated) ?? 16
        let stored = ds.int(.bitsStored) ?? bits
        let signed = (ds.int(.pixelRepresentation) ?? 0) == 1
        let slope = Float(ds.doubles(.rescaleSlope).first ?? 1)
        let intercept = Float(ds.doubles(.rescaleIntercept).first ?? 0)
        let n = rows * columns
        let bytesPer = bits <= 8 ? 1 : (bits <= 16 ? 2 : 4)
        let d = try frameBytes(frame, bytesPerFrame: n * bytesPer)
        var vals = [Float](repeating: 0, count: n)
        var mn = Float.greatestFiniteMagnitude, mx = -Float.greatestFiniteMagnitude
        let mask = stored >= 32 ? UInt32.max : (UInt32(1) << UInt32(stored)) - 1
        let signBit = stored >= 32 ? UInt32(0) : UInt32(1) << UInt32(stored - 1)
        d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<n {
                var u: UInt32
                switch bytesPer {
                case 1: u = UInt32(raw[i])
                case 2: u = UInt32(raw[i * 2]) | UInt32(raw[i * 2 + 1]) << 8
                default: u = UInt32(raw[i * 4]) | UInt32(raw[i * 4 + 1]) << 8 | UInt32(raw[i * 4 + 2]) << 16 | UInt32(raw[i * 4 + 3]) << 24
                }
                u &= mask
                var v: Float
                if signed && (u & signBit) != 0 { v = Float(Int64(u) - Int64(mask) - 1) } else { v = Float(u) }
                v = v * slope + intercept
                vals[i] = v
                if v < mn { mn = v }
                if v > mx { mx = v }
            }
        }
        values = vals
        minValue = mn; maxValue = mx
        cachedFrame = frame
    }

    private func renderRGB(frame: Int) throws -> CGImage {
        let n = rows * columns
        let planar = (ds.int(.planarConfiguration) ?? 0) == 1
        let d = try frameBytes(frame, bytesPerFrame: n * 3)
        var out = [UInt8](repeating: 255, count: n * 4)
        for i in 0..<n {
            for c in 0..<3 { out[i * 4 + c] = planar ? d.u8(c * n + i) : d.u8(i * 3 + c) }
        }
        return try makeImage(out, components: 4)
    }

    private func decodeEncapsulated(_ frags: [Data], frame: Int) throws -> CGImage {
        let payload = frags.dropFirst() // first item is the basic offset table
        let data: Data
        if payload.count == frameCount {
            data = payload[payload.startIndex + frame]
        } else if frameCount == 1 {
            data = payload.reduce(Data(), +)
        } else {
            data = payload.first ?? Data()
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw DicomError.unsupported("Kompression \(TransferSyntax.name(transferSyntax)) kann nicht angezeigt werden")
        }
        return img
    }

    private func makeImage(_ bytes: [UInt8], components: Int) throws -> CGImage {
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { throw DicomError.parse("Bild konnte nicht erzeugt werden") }
        let gray = components == 1
        guard let img = CGImage(width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 8 * components,
                                bytesPerRow: columns * components,
                                space: gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw DicomError.parse("Bild konnte nicht erzeugt werden")
        }
        return img
    }
}
