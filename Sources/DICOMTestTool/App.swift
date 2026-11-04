import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import DicomCore

@main
struct DICOMTestToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    // Not observed here: MenuBarExtra writes its isInserted binding back on every scene update,
    // which would loop endlessly if the scene re-evaluated on each AppState change.
    private let state = AppState.shared
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        Window(AppInfo.name, id: AppInfo.mainWindowID) {
            ContentView()
                .environmentObject(state)
                .environmentObject(state.updater)
                .frame(minWidth: 1050, minHeight: 720)
                .themedRoot()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("Über \(AppInfo.name)") { state.section = .about }
            }
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") { state.updater.check(userInitiated: true) }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Einstellungen …") { state.section = .general }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .help) { TourMenuButton() }
        }

        Window("Einführung", id: AppInfo.tourWindowID) {
            TourView()
                .environmentObject(state)
                .themedRoot()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra(isInserted: Binding(get: { showMenuBarIcon },
                                         set: { if $0 != state.showMenuBarIcon { state.showMenuBarIcon = $0 } })) {
            MenuBarMenu()
                .environmentObject(state)
        } label: {
            MenuBarLabel(state: state)
        }
    }
}

/// Opens a window and brings it to the current Space – also when another app is in full-screen mode,
/// where a normal window would otherwise stay on its own desktop and seem not to open.
@MainActor func presentWindow(id: String, using openWindow: OpenWindowAction) {
    openWindow(id: id)
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async {
        for w in NSApp.windows where w.identifier?.rawValue == id || w.identifier?.rawValue.hasPrefix(id + "-") == true {
            w.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor func openTour(_ openWindow: OpenWindowAction) {
    presentWindow(id: AppInfo.tourWindowID, using: openWindow)
}

struct TourMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Einführung – Tour durch die Werkzeuge …") { openTour(openWindow) }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    var body: some View {
        Image(systemName: state.watchHasFailure ? "exclamationmark.triangle.fill" : "waveform.path.ecg.rectangle")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        AppTheme.current.applyToApp()
        NSApp.activate(ignoringOtherApps: true)
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
        Task { @MainActor in AppState.shared.didFinishLaunching() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // With the menu bar icon the app keeps running in the background (SCP, Watchdog).
        !(UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        FileLogger.shared.write("App", "Beendet")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum AppInfo {
    static let name = "DICOM Test Tool"
    static let mainWindowID = "main"
    static let tourWindowID = "tour"
    static let developer = "Martin Senft"
    static let location = "Brakel, Deutschland"
    static let defaultRepository = "masenft/DICOMTestTool"
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0-dev" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev" }
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "de.martinsenft.dicomtesttool" }

    static var dataDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var logDirectory: URL {
        let dir = dataDirectory.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case nodes, echo, store, find, worklist, scp, watchdog, viewer
    case general, about
    var id: String { rawValue }

    static let tools: [AppSection] = [.nodes, .echo, .store, .find, .worklist, .scp, .watchdog, .viewer]
    static let app: [AppSection] = [.general, .about]

    var title: String {
        switch self {
        case .nodes: return "Knoten & Einstellungen"
        case .echo: return "Echo (Verification)"
        case .store: return "Store (Senden)"
        case .find: return "Query / Retrieve"
        case .worklist: return "Worklist"
        case .scp: return "Storage SCP (Empfang)"
        case .watchdog: return "Watchdog"
        case .viewer: return "Viewer / Tag-Dump"
        case .general: return "Allgemein"
        case .about: return "Über"
        }
    }
    var icon: String {
        switch self {
        case .nodes: return "server.rack"
        case .echo: return "dot.radiowaves.left.and.right"
        case .store: return "paperplane"
        case .find: return "magnifyingglass"
        case .worklist: return "list.clipboard"
        case .scp: return "tray.and.arrow.down"
        case .watchdog: return "heart.text.square"
        case .viewer: return "photo.on.rectangle"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }
    /// Tool views share the bottom protocol pane; app pages do not.
    var showsLog: Bool { AppSection.tools.contains(self) }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let source: String
    let text: String
    var isError: Bool
}

struct WatchStatus {
    var ok: Bool?
    var lastCheck: Date?
    var latencyMs: Double?
    var failures = 0
    var message = ""
}

/// Appends protocol lines to a daily log file in the app data folder.
final class FileLogger: @unchecked Sendable {
    static let shared = FileLogger()
    private let queue = DispatchQueue(label: "dicomtesttool.filelog")
    private let lineFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f }()
    private let dayFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    static let retentionDays = 30

    func write(_ source: String, _ text: String, error: Bool = false) {
        let now = Date()
        queue.async { [self] in
            let url = AppInfo.logDirectory.appendingPathComponent("dicomtesttool-\(dayFormat.string(from: now)).log")
            let line = "\(lineFormat.string(from: now)) \(error ? "FEHLER" : "INFO  ") [\(source)] \(text)\n"
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    func logFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: AppInfo.logDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func pruneOldFiles() {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86400)
        for f in logFiles() {
            if let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d < cutoff {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var section: AppSection = .echo
    @Published var nodes: [DicomNode] = [] { didSet { save() } }
    @Published var selectedNodeID: UUID?
    @Published var callingAE = "DICOMTEST_SCU" { didSet { save() } }
    @Published var timeout: Double = 15 { didSet { save() } }
    @Published var log: [LogEntry] = []

    // General
    @Published var notificationsEnabled = true { didSet { save() } }
    @Published var notifyWatchdog = true { didSet { save() } }
    @Published var notifySCP = false { didSet { save() } }
    @Published var showMenuBarIcon = true { didSet { save(); if !showMenuBarIcon && !showInDock { showInDock = true } } }
    @Published var showInDock = true {
        didSet {
            save()
            guard !loading else { return }
            if !showInDock && !showMenuBarIcon { showMenuBarIcon = true }
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
            if !showInDock { NSApp.activate(ignoringOtherApps: true) }
        }
    }
    @Published var autoStartSCP = false { didSet { save() } }
    @Published var autoStartWatchdog = false { didSet { save() } }
    @Published var notificationPermission = "unbekannt"

    // Storage SCP
    @Published var scpAE = "DICOMTEST" { didSet { save() } }
    @Published var scpPort = 11112 { didSet { save() } }
    @Published var scpDirectory = AppState.defaultStorageDirectory { didSet { save() } }
    @Published var scpAcceptAnyAE = true { didSet { save() } }
    @Published var scpRunning = false
    @Published var received: [ReceivedObject] = []
    private var scp: StorageSCP?

    // Watchdog
    @Published var watchNodeIDs: Set<UUID> = [] { didSet { save() } }
    @Published var watchInterval: Double = 60 { didSet { save() } }
    @Published var watchRunning = false
    @Published var watchStatus: [UUID: WatchStatus] = [:]
    private var watchTask: Task<Void, Never>?

    // Viewer / Store hand-over
    @Published var viewerURL: URL?
    @Published var storeQueue: [URL] = []

    let updater = Updater()
    private let defaults = UserDefaults.standard
    private var loading = false

    static var defaultStorageDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("DICOM Empfang")
    }

    private init() {
        load()
        updater.log = { [weak self] msg, isError in self?.append("Update", msg, error: isError) }
        updater.notify = { [weak self] title, body in self?.notify(title: title, body: body) }
    }

    func didFinishLaunching() {
        FileLogger.shared.pruneOldFiles()
        append("App", "\(AppInfo.name) \(AppInfo.version) gestartet")
        refreshNotificationPermission()
        if autoStartSCP { startSCP() }
        if autoStartWatchdog && !watchNodeIDs.isEmpty { startWatchdog() }
        updater.startAutomaticChecks()
        if ProcessInfo.processInfo.environment["DICOMTESTTOOL_NOTIFY_TEST"] == "1" { sendTestNotification() } // test hook
    }

    // MARK: Persistence

    private func load() {
        loading = true
        defer { loading = false }
        if let d = defaults.data(forKey: "nodes"), let n = try? JSONDecoder().decode([DicomNode].self, from: d) {
            nodes = n
        } else {
            nodes = [DicomNode(name: "Lokaler SCP", aeTitle: "DICOMTEST", host: "127.0.0.1", port: 11112)]
        }
        callingAE = defaults.string(forKey: "callingAE") ?? "DICOMTEST_SCU"
        timeout = defaults.object(forKey: "timeout") as? Double ?? 15
        scpAE = defaults.string(forKey: "scpAE") ?? "DICOMTEST"
        scpPort = defaults.object(forKey: "scpPort") as? Int ?? 11112
        scpAcceptAnyAE = defaults.object(forKey: "scpAnyAE") as? Bool ?? true
        scpDirectory = defaults.url(forKey: "scpDir") ?? Self.defaultStorageDirectory
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        notifyWatchdog = defaults.object(forKey: "notifyWatchdog") as? Bool ?? true
        notifySCP = defaults.object(forKey: "notifySCP") as? Bool ?? false
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        autoStartSCP = defaults.bool(forKey: "autoStartSCP")
        autoStartWatchdog = defaults.bool(forKey: "autoStartWatchdog")
        watchInterval = defaults.object(forKey: "watchInterval") as? Double ?? 60
        watchNodeIDs = Set((defaults.stringArray(forKey: "watchNodeIDs") ?? []).compactMap(UUID.init(uuidString:)))
        selectedNodeID = nodes.first?.id
    }

    private func save() {
        guard !loading else { return }
        if let d = try? JSONEncoder().encode(nodes) { defaults.set(d, forKey: "nodes") }
        defaults.set(callingAE, forKey: "callingAE")
        defaults.set(timeout, forKey: "timeout")
        defaults.set(scpAE, forKey: "scpAE")
        defaults.set(scpPort, forKey: "scpPort")
        defaults.set(scpAcceptAnyAE, forKey: "scpAnyAE")
        defaults.set(scpDirectory, forKey: "scpDir")
        defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        defaults.set(notifyWatchdog, forKey: "notifyWatchdog")
        defaults.set(notifySCP, forKey: "notifySCP")
        defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        defaults.set(showInDock, forKey: "showInDock")
        defaults.set(autoStartSCP, forKey: "autoStartSCP")
        defaults.set(autoStartWatchdog, forKey: "autoStartWatchdog")
        defaults.set(watchInterval, forKey: "watchInterval")
        defaults.set(watchNodeIDs.map(\.uuidString), forKey: "watchNodeIDs")
    }

    /// Stops all services and restores every setting (nodes included) to its default.
    func resetToDefaults() {
        stopSCP()
        stopWatchdog()
        if launchAtLogin { setLaunchAtLogin(false) }
        defaults.removePersistentDomain(forName: AppInfo.bundleID)
        for key in defaults.dictionaryRepresentation().keys where Self.ownKeys.contains(key) { defaults.removeObject(forKey: key) }
        load()
        updater.reload()
        received.removeAll()
        watchStatus.removeAll()
        NSApp.setActivationPolicy(.regular)
        append("App", "Alle Einstellungen wurden auf Standard zurückgesetzt")
    }

    private static let ownKeys: Set<String> = Set([
        "nodes", "callingAE", "timeout", "scpAE", "scpPort", "scpAnyAE", "scpDir", "notificationsEnabled", "notifyWatchdog",
        "notifySCP", "showMenuBarIcon", "showInDock", "autoStartSCP", "autoStartWatchdog", "watchInterval", "watchNodeIDs",
        TourPage.shownKey,
    ]).union(Updater.keys)

    var settings: SCUSettings { SCUSettings(callingAE: callingAE, timeout: timeout) }
    var selectedNode: DicomNode? { nodes.first { $0.id == selectedNodeID } ?? nodes.first }

    // MARK: Log

    func append(_ source: String, _ text: String, error: Bool = false) {
        log.append(LogEntry(source: source, text: text, isError: error))
        if log.count > 5000 { log.removeFirst(log.count - 5000) }
        FileLogger.shared.write(source, text, error: error)
    }

    nonisolated func logger(_ source: String) -> LogHandler {
        { [weak self] msg in Task { @MainActor in self?.append(source, msg) } }
    }

    func logText() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return log.map { "\(f.string(from: $0.date)) \($0.isError ? "FEHLER" : "INFO  ") [\($0.source)] \($0.text)" }.joined(separator: "\n") + "\n"
    }

    // MARK: Launch at login

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    var launchAtLoginStatus: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "aktiv"
        case .notRegistered: return "nicht aktiv"
        case .requiresApproval: return "Freigabe in Systemeinstellungen › Allgemein › Anmeldeobjekte nötig"
        case .notFound: return "nicht verfügbar (App bitte nach /Programme kopieren)"
        @unknown default: return "unbekannt"
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            append("App", on ? "Start bei Anmeldung aktiviert" : "Start bei Anmeldung deaktiviert")
        } catch {
            append("App", "Start bei Anmeldung: \(error.localizedDescription)", error: true)
        }
        objectWillChange.send()
    }

    // MARK: Windows

    func open(_ s: AppSection) {
        section = s
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue == AppInfo.mainWindowID || $0.title == AppInfo.name }?.makeKeyAndOrderFront(nil)
    }

    // MARK: Quick echo (menu bar)

    func quickEcho(_ node: DicomNode) {
        let settings = self.settings, log = logger("Echo")
        Task {
            do {
                let r = try await DicomSCU.echo(node: node, settings: settings, log: log)
                let msg = String(format: "%@: %@ (%.0f ms)", node.name, DimseStatus.text(r.status), r.totalTime * 1000)
                append("Echo", msg, error: r.status != 0)
                notify(title: r.status == 0 ? "Echo erfolgreich" : "Echo fehlgeschlagen", body: msg, force: true)
            } catch {
                append("Echo", "\(node.name): \(error.localizedDescription)", error: true)
                notify(title: "Echo fehlgeschlagen", body: "\(node.name): \(error.localizedDescription)", force: true)
            }
        }
    }

    // MARK: SCP

    func startSCP() {
        guard !scpRunning, let port = UInt16(exactly: scpPort) else { return }
        let s = StorageSCP(aeTitle: scpAE, port: port, storageDirectory: scpDirectory, acceptAnyCalledAE: scpAcceptAnyAE)
        s.log = logger("SCP")
        s.onReceived = { [weak self] obj in
            Task { @MainActor in
                guard let self else { return }
                self.received.insert(obj, at: 0)
                if self.notifySCP {
                    self.notify(title: "DICOM empfangen", body: "\(formatPN(obj.patientName)) [\(obj.patientID)] von \(obj.callingAE)")
                }
            }
        }
        do {
            try s.start()
            scp = s
            scpRunning = true
        } catch {
            append("SCP", "Start fehlgeschlagen: \(error.localizedDescription)", error: true)
        }
    }

    func stopSCP() {
        scp?.stop()
        scp = nil
        scpRunning = false
    }

    // MARK: Watchdog

    var watchHasFailure: Bool { watchRunning && watchStatus.values.contains { $0.ok == false } }

    var watchSummary: String {
        let watched = nodes.filter { watchNodeIDs.contains($0.id) }
        let ok = watched.filter { watchStatus[$0.id]?.ok == true }.count
        return "\(ok)/\(watched.count) erreichbar"
    }

    func startWatchdog() {
        guard !watchRunning else { return }
        watchRunning = true
        requestNotificationPermission(interactive: false)
        append("Watchdog", "Überwachung gestartet (\(Int(watchInterval)) s)")
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let targets = self.nodes.filter { self.watchNodeIDs.contains($0.id) }
                let settings = self.settings
                await withTaskGroup(of: (UUID, Bool, Double?, String).self) { group in
                    for node in targets {
                        group.addTask {
                            do {
                                let r = try await DicomSCU.echo(node: node, settings: settings)
                                return (node.id, r.status == 0, r.totalTime * 1000, DimseStatus.text(r.status))
                            } catch {
                                return (node.id, false, nil, error.localizedDescription)
                            }
                        }
                    }
                    for await (id, ok, ms, msg) in group { self.updateWatch(id, ok: ok, ms: ms, msg: msg) }
                }
                try? await Task.sleep(nanoseconds: UInt64(max(5, self.watchInterval) * 1_000_000_000))
            }
        }
    }

    func stopWatchdog() {
        guard watchRunning else { return }
        watchTask?.cancel()
        watchTask = nil
        watchRunning = false
        append("Watchdog", "Überwachung gestoppt")
    }

    private func updateWatch(_ id: UUID, ok: Bool, ms: Double?, msg: String) {
        var s = watchStatus[id] ?? WatchStatus()
        let previous = s.ok
        s.ok = ok
        s.lastCheck = Date()
        s.latencyMs = ms
        s.failures = ok ? 0 : s.failures + 1
        s.message = msg
        watchStatus[id] = s
        let name = nodes.first { $0.id == id }?.name ?? "?"
        if previous != ok {
            append("Watchdog", ok ? "\(name) erreichbar" : "\(name) NICHT erreichbar: \(msg)", error: !ok)
            if (previous != nil || !ok) && notifyWatchdog {
                notify(title: ok ? "DICOM-Knoten wieder erreichbar" : "DICOM-Knoten nicht erreichbar", body: "\(name): \(msg)")
            }
        }
    }

    // MARK: Notifications

    private var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// Asks macOS for permission. If it was already denied, macOS shows no dialog again –
    /// then the user is told so and System Settings is offered.
    func requestNotificationPermission(interactive: Bool = true, then: (@MainActor (Bool) -> Void)? = nil) {
        guard notificationsAvailable else { then?(false); return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                let state = AppState.shared
                switch status {
                case .authorized, .provisional:
                    if interactive && then == nil { state.append("App", "Mitteilungen sind bereits erlaubt") }
                    state.refreshNotificationPermission()
                    then?(true)
                case .denied:
                    state.refreshNotificationPermission()
                    if interactive {
                        state.append("App", "Mitteilungen sind in den Systemeinstellungen abgelehnt", error: true)
                        state.showNotificationsDeniedAlert()
                    }
                    then?(false)
                default:
                    NSApp.activate(ignoringOtherApps: true)
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                        Task { @MainActor in
                            if let error {
                                state.append("App", "Berechtigung für Mitteilungen: \(error.localizedDescription)", error: true)
                            } else {
                                state.append("App", granted ? "Mitteilungen erlaubt" : "Mitteilungen wurden nicht erlaubt", error: !granted)
                            }
                            state.refreshNotificationPermission()
                            if !granted && interactive { state.showNotificationsDeniedAlert() }
                            then?(granted)
                        }
                    }
                }
            }
        }
    }

    func sendTestNotification() {
        requestNotificationPermission { granted in
            guard granted else { return }
            self.notify(title: AppInfo.name, body: "So sehen Popup-Hinweise aus, z. B. wenn der Watchdog einen Ausfall meldet.", force: true)
            self.append("App", "Test-Mitteilung gesendet")
        }
    }

    func openNotificationSettings() {
        let id = AppInfo.bundleID
        let urls = ["x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
                    "x-apple.systempreferences:com.apple.Notifications-Settings.extension"]
        for u in urls { if let url = URL(string: u), NSWorkspace.shared.open(url) { return } }
    }

    private func showNotificationsDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Mitteilungen sind nicht erlaubt"
        alert.informativeText = "macOS zeigt die Anfrage nur einmal an. Bitte erlauben Sie Mitteilungen für „\(AppInfo.name)“ unter Systemeinstellungen › Mitteilungen. Wird nichts angezeigt, prüfen Sie auch, ob ein Fokus (z. B. „Nicht stören“) aktiv ist."
        alert.addButton(withTitle: "Systemeinstellungen öffnen")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openNotificationSettings() }
    }

    func refreshNotificationPermission() {
        guard notificationsAvailable else { notificationPermission = "nicht verfügbar (App nicht als Bundle gestartet)"; return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let text: String
            switch s.authorizationStatus {
            case .authorized, .provisional:
                text = s.alertSetting == .enabled ? "erlaubt" : "erlaubt, aber Hinweisstil „Ohne“ – bitte in den Systemeinstellungen „Banner“ wählen"
            case .denied: text = "abgelehnt – bitte in Systemeinstellungen › Mitteilungen erlauben"
            case .notDetermined: text = "noch nicht angefragt"
            default: text = "unbekannt"
            }
            Task { @MainActor in AppState.shared.notificationPermission = text }
        }
    }

    /// `force` bypasses the global switch for notifications the user explicitly triggered (menu bar echo).
    func notify(title: String, body: String, force: Bool = false) {
        guard notificationsAvailable, notificationsEnabled || force else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)) { error in
            if let error {
                Task { @MainActor in AppState.shared.append("App", "Mitteilung konnte nicht angezeigt werden: \(error.localizedDescription)", error: true) }
            }
        }
    }
}
