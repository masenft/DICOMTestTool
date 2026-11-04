import AppKit
import SwiftUI
import DicomCore

/// Test hook for website screenshots: renders the main window into PNG files without needing
/// screen-recording permission. Only active when DICOMTESTTOOL_SNAPSHOT=<output folder> is set.
/// DICOMTESTTOOL_SNAPSHOT_SHOTS lists the shots (default: watchdog,viewer; also store, worklist).
/// DICOMTESTTOOL_SNAPSHOT_FILE=<DICOM file> is opened in the viewer.
/// Worklist entries are fictitious demo data, injected directly into the table.
@MainActor
enum SnapshotHook {
    static let storeSend = Notification.Name("SnapshotHook.storeSend")
    static let worklistRows = Notification.Name("SnapshotHook.worklistRows")

    static func runIfRequested(_ state: AppState) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["DICOMTESTTOOL_SNAPSHOT"] else { return }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        let file = env["DICOMTESTTOOL_SNAPSHOT_FILE"].map { URL(fileURLWithPath: $0) }
        let shots = (env["DICOMTESTTOOL_SNAPSHOT_SHOTS"] ?? "watchdog,viewer").split(separator: ",").map(String.init)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            let theme = AppTheme(rawValue: env["DICOMTESTTOOL_SNAPSHOT_THEME"] ?? "") ?? .clinicalDark
            UserDefaults.standard.set(theme.rawValue, forKey: AppTheme.storageKey)
            try? await Task.sleep(for: .milliseconds(500))
            // Standard follows the system; DICOMTESTTOOL_SNAPSHOT_APPEARANCE=light|dark forces one look.
            let dark = theme == .clinicalDark || env["DICOMTESTTOOL_SNAPSHOT_APPEARANCE"] != "light"
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            state.notificationsEnabled = false
            if let w = mainWindow, let screen = w.screen?.visibleFrame {
                let size = NSSize(width: min(1300, screen.width), height: min(900, screen.height))
                w.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height), display: true)
            }
            for shot in shots {
                state.log.removeAll()
                switch shot {
                case "watchdog": await watchdog(state)
                case "viewer": await viewer(state, file: file)
                case "store": await store(state)
                case "worklist": await worklist(state)
                default: continue
                }
                state.log.removeAll { $0.text.contains("Mitteilung") }
                try? await Task.sleep(for: .seconds(1))
                capture(out.appendingPathComponent("\(shot).png"))
                if state.watchRunning { state.stopWatchdog() }
            }
            NSApp.terminate(nil)
        }
    }

    private static func watchdog(_ state: AppState) async {
        state.watchNodeIDs = Set(state.nodes.map(\.id))
        state.watchInterval = 10
        state.section = .watchdog
        state.startWatchdog()
        try? await Task.sleep(for: .seconds(5))
    }

    private static func viewer(_ state: AppState, file: URL?) async {
        state.section = .viewer
        try? await Task.sleep(for: .seconds(1))
        if let file { state.viewerURL = file }
        try? await Task.sleep(for: .seconds(2))
    }

    private static func store(_ state: AppState) async {
        var o = TestImageOptions()
        o.patientName = "MUSTERMANN^ERIKA"
        o.patientID = "DEMO0042"
        o.birthDate = "19820314"
        o.sex = "F"
        o.accessionNumber = "ACC260042"
        o.count = 8
        let dir = URL(fileURLWithPath: "/tmp/DICOM-Testbilder", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        if let urls = try? TestImageGenerator.generate(o, into: dir) {
            state.append("Store", "\(urls.count) Testbild(er) erzeugt")
            state.storeQueue = urls
        }
        state.selectedNodeID = state.nodes.first?.id
        state.section = .store
        try? await Task.sleep(for: .seconds(1))
        NotificationCenter.default.post(name: storeSend, object: nil)
        try? await Task.sleep(for: .seconds(4))
    }

    private static func worklist(_ state: AppState) async {
        state.selectedNodeID = state.nodes.first { $0.name.contains("RIS") }?.id ?? state.nodes.first?.id
        state.section = .worklist
        try? await Task.sleep(for: .seconds(1))
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        let today = f.string(from: Date())
        let entries: [[String]] = [
            ["MUSTERMANN^ERIKA", "DEMO0042", "19820314", "F", "ACC260042", "Thorax p.a. und seitlich", "CR", "080000", "CR_RAUM1"],
            ["BEISPIEL^JONAS", "DEMO0043", "19750921", "M", "ACC260043", "Kniegelenk links in 2 Ebenen", "CR", "083000", "CR_RAUM1"],
            ["TESTFALL^LENA", "DEMO0044", "19910602", "F", "ACC260044", "CT Schädel nativ", "CT", "090000", "CT_SCANNER"],
            ["PROBE^MAX", "DEMO0045", "19680117", "M", "ACC260045", "MRT LWS", "MR", "094500", "MR_1_5T"],
            ["MUSTERFRAU^ANNA", "DEMO0046", "20010830", "F", "ACC260046", "Sonographie Abdomen", "US", "103000", "US_RAUM3"],
            ["DEMO^PAUL", "DEMO0047", "19590405", "M", "ACC260047", "CT Thorax mit KM", "CT", "111500", "CT_SCANNER"],
        ]
        let datasets: [DataSet] = entries.map { e in
            var ds = DataSet()
            ds.set(.patientName, e[0]); ds.set(.patientID, e[1]); ds.set(.patientBirthDate, e[2]); ds.set(.patientSex, e[3])
            ds.set(.accessionNumber, e[4]); ds.set(.requestedProcedureDescription, e[5])
            var sps = DataSet()
            sps.set(.modality, e[6]); sps.set(.scheduledProcedureStepStartDate, today); sps.set(.scheduledProcedureStepStartTime, e[7])
            sps.set(.scheduledStationAETitle, e[8])
            ds.setSequence(.scheduledProcedureStepSequence, [sps])
            return ds
        }
        NotificationCenter.default.post(name: worklistRows, object: datasets)
        try? await Task.sleep(for: .seconds(1))
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(AppInfo.mainWindowID) == true && $0.isVisible }
    }

    private static func capture(_ url: URL) {
        guard let window = mainWindow, let view = window.contentView?.superview else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        view.display()
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
