import Foundation

public struct TestImageOptions: Sendable {
    public var patientName = "TEST^PATIENT"
    public var patientID = "TEST0001"
    public var birthDate = "19700101"
    public var sex = "O"
    public var accessionNumber = ""
    public var modality = "OT"
    public var studyDescription = "DICOM Test Tool"
    public var count = 1
    public var size = 512

    public init() {}
}

/// Generates Secondary Capture test images (16 bit, 12 bit stored) in one study/series.
public enum TestImageGenerator {
    public static func generate(_ o: TestImageOptions, into dir: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let study = UIDGenerator.make(), series = UIDGenerator.make()
        let now = Date()
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyyMMdd"
        let tf = DateFormatter(); tf.locale = Locale(identifier: "en_US_POSIX"); tf.dateFormat = "HHmmss"
        var urls: [URL] = []
        for i in 1...max(1, o.count) {
            let sop = UIDGenerator.make()
            var ds = DataSet()
            ds.set(.specificCharacterSet, "ISO_IR 100")
            ds.set(.imageType, "DERIVED\\SECONDARY")
            ds.set(.sopClassUID, SOPClass.secondaryCapture)
            ds.set(.sopInstanceUID, sop)
            ds.set(.studyDate, df.string(from: now)); ds.set(.studyTime, tf.string(from: now))
            ds.set(.contentDate, df.string(from: now)); ds.set(.contentTime, tf.string(from: now))
            ds.set(.accessionNumber, o.accessionNumber)
            ds.set(.modality, o.modality)
            ds.set(.conversionType, "WSD")
            ds.set(.manufacturer, "DICOM Test Tool")
            ds.set(.referringPhysicianName, "")
            ds.set(.studyDescription, o.studyDescription)
            ds.set(.seriesDescription, "Testbild")
            ds.set(.patientName, o.patientName)
            ds.set(.patientID, o.patientID)
            ds.set(.patientBirthDate, o.birthDate)
            ds.set(.patientSex, o.sex)
            ds.set(.studyInstanceUID, study)
            ds.set(.seriesInstanceUID, series)
            ds.set(.studyID, "1")
            ds.set(.seriesNumber, "1")
            ds.set(.instanceNumber, String(i))
            ds.setUInt16(.samplesPerPixel, 1)
            ds.set(.photometricInterpretation, "MONOCHROME2")
            ds.setUInt16(.rows, UInt16(o.size))
            ds.setUInt16(.columns, UInt16(o.size))
            ds.setUInt16(.bitsAllocated, 16)
            ds.setUInt16(.bitsStored, 12)
            ds.setUInt16(.highBit, 11)
            ds.setUInt16(.pixelRepresentation, 0)
            ds.set(.windowCenter, "2048")
            ds.set(.windowWidth, "4096")
            ds[.pixelData] = DicomElement(tag: .pixelData, vr: .OW, data: pixels(size: o.size, index: i))
            let url = dir.appendingPathComponent("TEST_\(i).dcm")
            try DicomFile.write(to: url, sopClass: SOPClass.secondaryCapture, sopInstance: sop,
                                transferSyntax: TransferSyntax.explicitLE, datasetBytes: ds.encoded(explicit: true))
            urls.append(url)
        }
        return urls
    }

    static func pixels(size n: Int, index: Int) -> Data {
        var buf = [UInt16](repeating: 0, count: n * n)
        let c = Double(n) / 2
        for y in 0..<n {
            for x in 0..<n {
                var v = Double(x + y) / Double(2 * n) * 3000 + 200
                let r = ((Double(x) - c) * (Double(x) - c) + (Double(y) - c) * (Double(y) - c)).squareRoot()
                if abs(r - Double(n) * 0.35) < 3 { v = 4000 }
                if x % 64 == 0 || y % 64 == 0 { v = 1500 }
                buf[y * n + x] = UInt16(min(4095, max(0, v)))
            }
        }
        // Instance marker: one bright square per image number (up to 20) in the top-left corner.
        for k in 0..<min(index, 20) {
            let ox = 8 + (k % 10) * 14, oy = 8 + (k / 10) * 14
            for y in oy..<min(n, oy + 10) { for x in ox..<min(n, ox + 10) { buf[y * n + x] = 4095 } }
        }
        var d = Data(capacity: n * n * 2)
        for v in buf { d.appendU16LE(v) }
        return d
    }
}
