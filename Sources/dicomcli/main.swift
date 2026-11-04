import Foundation
import DicomCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Command line companion for scripting and quick checks.
// Usage:
//   dicomcli echo  <host> <port> <calledAE> [callingAE]
//   dicomcli store <host> <port> <calledAE> <file|folder>...
//   dicomcli find  <host> <port> <calledAE> [patientName]        (Study Root, STUDY level)
//   dicomcli mwl   <host> <port> <calledAE> [patientName]        (Modality Worklist)
//   dicomcli scp   <port> <aeTitle> <folder>
//   dicomcli testimage <folder> [count]
//   dicomcli dump  <file>
//   dicomcli png   <file> <out.png>

let args = Array(CommandLine.arguments.dropFirst())
let log: LogHandler = { print("  " + $0) }
let callingAE = ProcessInfo.processInfo.environment["DICOM_AET"] ?? "DICOMCLI"

func usage() -> Never {
    print("""
    dicomcli echo  <host> <port> <calledAE>
    dicomcli store <host> <port> <calledAE> <file|folder>...
    dicomcli find  <host> <port> <calledAE> [patientName]
    dicomcli mwl   <host> <port> <calledAE> [patientName]
    dicomcli move  <host> <port> <calledAE> <destAE> <studyUID>
    dicomcli scp   <port> <aeTitle> <folder>
    dicomcli testimage <folder> [count]
    dicomcli dump  <file>
    dicomcli png   <file> <out.png>
    (Calling AE über Umgebungsvariable DICOM_AET, Standard DICOMCLI)
    """)
    exit(2)
}

func node(_ a: [String]) -> DicomNode {
    guard a.count >= 4, let port = UInt16(a[2]) else { usage() }
    return DicomNode(name: a[3], aeTitle: a[3], host: a[1], port: port)
}

func dump(_ ds: DataSet, indent: String = "") {
    for el in ds.sorted {
        print("\(indent)\(el.tag) \(el.vr.rawValue) \(el.tag.name.padding(toLength: 34, withPad: " ", startingAt: 0)) \(el.displayValue)")
        if let items = el.items {
            for (i, item) in items.enumerated() {
                print("\(indent)  > Item \(i + 1)")
                dump(item, indent: indent + "    ")
            }
        }
    }
}

let settings = SCUSettings(callingAE: callingAE)
guard let cmd = args.first else { usage() }

do {
    switch cmd {
    case "echo":
        let r = try await DicomSCU.echo(node: node(args), settings: settings, log: log)
        print(String(format: "Echo: %@ (gesamt %.0f ms)", DimseStatus.text(r.status), r.totalTime * 1000))
        exit(r.status == 0 ? 0 : 1)
    case "store":
        let files = DicomSCU.collectFiles(args.dropFirst(4).map { URL(fileURLWithPath: $0) })
        let results = try await DicomSCU.store(node: node(args), settings: settings, files: files, log: log) { _, _, _ in }
        let ok = results.filter(\.ok).count
        print("Gesendet: \(ok)/\(results.count)")
        exit(ok == results.count ? 0 : 1)
    case "find", "mwl":
        var q = DataSet()
        let name = args.count > 4 ? args[4] : ""
        let sop: String
        if cmd == "find" {
            sop = SOPClass.studyRootFind
            q.set(.queryRetrieveLevel, "STUDY")
            for t in [Tag.studyDate, .accessionNumber, .modalitiesInStudy, .studyDescription, .patientID, .patientBirthDate, .studyInstanceUID, .numberOfStudyRelatedInstances] { q.set(t, "") }
        } else {
            sop = SOPClass.modalityWorklistFind
            for t in [Tag.patientID, .patientBirthDate, .patientSex, .accessionNumber, .requestedProcedureDescription, .requestedProcedureID, .studyInstanceUID] { q.set(t, "") }
            var sps = DataSet()
            for t in [Tag.modality, .scheduledStationAETitle, .scheduledProcedureStepStartDate, .scheduledProcedureStepStartTime, .scheduledProcedureStepDescription, .scheduledProcedureStepID] { sps.set(t, "") }
            q.setSequence(.scheduledProcedureStepSequence, [sps])
        }
        q.set(.patientName, name)
        var n = 0
        try await DicomSCU.find(node: node(args), settings: settings, sopClass: sop, query: q, log: log) { ds in
            n += 1
            print("--- Treffer \(n)")
            dump(ds, indent: "  ")
        }
    case "move":
        guard args.count >= 6 else { usage() }
        var q = DataSet()
        q.set(.queryRetrieveLevel, "STUDY")
        q.set(.studyInstanceUID, args[5])
        try await DicomSCU.move(node: node(args), settings: settings, sopClass: SOPClass.studyRootMove, query: q,
                                destination: args[4], log: log) { p in
            print("  Status \(DimseStatus.text(p.status)): verbleibend \(p.remaining), ok \(p.completed), Fehler \(p.failed)")
        }
    case "scp":
        guard args.count >= 4, let port = UInt16(args[1]) else { usage() }
        let scp = StorageSCP(aeTitle: args[2], port: port, storageDirectory: URL(fileURLWithPath: args[3]), acceptAnyCalledAE: true)
        scp.log = { print($0) }
        try scp.start()
        while true { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
    case "testimage":
        guard args.count >= 2 else { usage() }
        var o = TestImageOptions()
        o.count = args.count > 2 ? Int(args[2]) ?? 1 : 1
        for u in try TestImageGenerator.generate(o, into: URL(fileURLWithPath: args[1])) { print(u.path) }
    case "png":
        guard args.count >= 3 else { usage() }
        let img = try DicomImage(file: try DicomFile.read(URL(fileURLWithPath: args[1])))
        let cg = try img.render(frame: 0, center: img.defaultCenter, width: img.defaultWidth)
        guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil) else { usage() }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
        print("PNG geschrieben: \(args[2])")
    case "dump":
        guard args.count >= 2 else { usage() }
        let f = try DicomFile.read(URL(fileURLWithPath: args[1]))
        print("Transfer Syntax: \(TransferSyntax.name(f.transferSyntax))")
        dump(f.meta)
        dump(f.dataset)
        if let e = f.parseError { print("WARNUNG: \(e)") }
    default:
        usage()
    }
} catch {
    print("Fehler: \(error.localizedDescription)")
    exit(1)
}
