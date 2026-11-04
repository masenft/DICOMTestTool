import SwiftUI
import AppKit
import DicomCore

// MARK: - Allgemein

struct GeneralView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.standard.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ToolHeader(title: "Allgemein", subtitle: "Startverhalten, Darstellung und Mitteilungen")
            GroupBox("Start") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("App bei Anmeldung öffnen", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                    Text("Status: \(state.launchAtLoginStatus)").font(.caption).foregroundStyle(.secondary)
                    Toggle("Storage SCP beim Start automatisch starten", isOn: $state.autoStartSCP)
                    Toggle("Watchdog beim Start automatisch starten", isOn: $state.autoStartWatchdog)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("Darstellung") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Farbschema", selection: $themeRaw) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.radioGroup)
                    Text((AppTheme(rawValue: themeRaw) ?? .standard).summary + " Die Umstellung wirkt sofort und lässt sich jederzeit zurücknehmen.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Toggle("Symbol in der Menüleiste anzeigen", isOn: $state.showMenuBarIcon)
                    Toggle("Symbol im Dock anzeigen", isOn: $state.showInDock)
                    Text("Mit Menüleisten-Symbol läuft die App nach dem Schließen des Fensters im Hintergrund weiter (SCP und Watchdog bleiben aktiv). Mindestens eines der beiden Symbole bleibt immer sichtbar.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("Popup-Hinweise (macOS-Mitteilungen)") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Mitteilungen aktivieren", isOn: $state.notificationsEnabled)
                        .onChange(of: state.notificationsEnabled) { _, on in if on { state.requestNotificationPermission() } }
                        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in state.refreshNotificationPermission() }
                    Group {
                        Toggle("Watchdog: Ausfall und Wiederherstellung eines Knotens melden", isOn: $state.notifyWatchdog)
                        Toggle("Storage SCP: jedes empfangene Objekt melden", isOn: $state.notifySCP)
                    }
                    .padding(.leading, 18)
                    .disabled(!state.notificationsEnabled)
                    HStack {
                        Text("Berechtigung: \(state.notificationPermission)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Berechtigung anfragen") { state.requestNotificationPermission() }
                        Button("Test-Mitteilung") { state.sendTestNotification() }
                        Button("Systemeinstellungen …") { state.openNotificationSettings() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
        }
        .padding()
        .onAppear { state.refreshNotificationPermission() }
    }
}

// MARK: - Protokolle & Ordner (aus „Über“ › Daten & Zurücksetzen)

struct LogBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var state: AppState
    @State private var logFiles: [URL] = []
    @State private var selectedLog: URL?
    @State private var logContent = ""
    @State private var confirmDeleteLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ToolHeader(title: "Protokolle & Ordner", subtitle: "Log-Dateien der App und Speicherorte")
                Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            GroupBox("Ordner") {
                VStack(alignment: .leading, spacing: 8) {
                    folderRow("App-Datenordner", AppInfo.dataDirectory)
                    folderRow("Log-Dateien", AppInfo.logDirectory)
                    folderRow("Empfangsordner (SCP)", state.scpDirectory)
                }
                .padding(6)
            }
            GroupBox("Log-Dateien (werden \(FileLogger.retentionDays) Tage aufbewahrt)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("Datei", selection: $selectedLog) {
                            ForEach(logFiles, id: \.self) { f in Text("\(f.lastPathComponent)  (\(size(f)))").tag(Optional(f)) }
                        }
                        .frame(maxWidth: 420)
                        Button { reloadLogs() } label: { Image(systemName: "arrow.clockwise") }.help("Aktualisieren")
                        Spacer()
                        Button("In Konsole öffnen") { if let f = selectedLog { openInConsole(f) } }.disabled(selectedLog == nil)
                        Button("Im Finder zeigen") { if let f = selectedLog { NSWorkspace.shared.activateFileViewerSelecting([f]) } }
                            .disabled(selectedLog == nil)
                        Button("Alle löschen …", role: .destructive) { confirmDeleteLogs = true }.disabled(logFiles.isEmpty)
                    }
                    ScrollView {
                        Text(logContent.isEmpty ? "Keine Einträge" : logContent)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(height: 260)
                    .background(Color(nsColor: .textBackgroundColor))
                    .border(Color.secondary.opacity(0.3))
                }
                .padding(6)
            }
        }
        .padding(20)
        .frame(width: 820, height: 600)
        .onAppear { reloadLogs() }
        .onChange(of: selectedLog) { _, f in loadContent(f) }
        .confirmationDialog("Alle Log-Dateien löschen?", isPresented: $confirmDeleteLogs) {
            Button("Löschen", role: .destructive) {
                for f in logFiles { try? FileManager.default.removeItem(at: f) }
                reloadLogs()
            }
        }
    }

    private func folderRow(_ title: String, _ url: URL) -> some View {
        HStack {
            Text(title).frame(width: 170, alignment: .leading)
            Text(url.path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer()
            Button("Öffnen") {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func size(_ f: URL) -> String {
        let s = (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file)
    }

    private func reloadLogs() {
        logFiles = FileLogger.shared.logFiles()
        if selectedLog == nil || !logFiles.contains(selectedLog!) { selectedLog = logFiles.first }
        loadContent(selectedLog)
    }

    private func loadContent(_ f: URL?) {
        guard let f, let h = try? FileHandle(forReadingFrom: f) else { logContent = ""; return }
        defer { try? h.close() }
        let limit: UInt64 = 200_000
        let end = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: end > limit ? end - limit : 0)
        let text = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
        logContent = (end > limit ? "… (nur die letzten 200 KB)\n" : "") + text
    }

    private func openInConsole(_ f: URL) {
        let console = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.open([f], withApplicationAt: console, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Über (inkl. Updates, Einführung, Daten & Zurücksetzen)

struct AboutView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var updater: Updater
    @Environment(\.openWindow) private var openWindow
    @State private var showLogs = false
    @State private var confirmReset = false
    @State private var showRepository = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            Divider()
            updatesCard
            Divider()
            AppCard(icon: "sparkles", title: "Einführung",
                    subtitle: "Die geführte Tour durch die Werkzeuge von \(AppInfo.name) noch einmal ansehen.") {
                Button { openTour(openWindow) } label: { Label("Tour anzeigen", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } content: { EmptyView() }
            Divider()
            privacyCard
            Divider()
            intendedUseCard
            Divider()
            dataSection
        }
        .padding(24)
        .sheet(isPresented: $showLogs) { LogBrowserSheet() }
        .confirmationDialog("Alle Einstellungen zurücksetzen?", isPresented: $confirmReset) {
            Button("Zurücksetzen", role: .destructive) { state.resetToDefaults() }
        } message: {
            Text("Gespeicherte Knoten und Einstellungen gehen verloren. SCP und Watchdog werden gestoppt.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppInfo.name).font(.largeTitle.bold())
                Text("Version \(AppInfo.version) (Build \(AppInfo.build))").foregroundStyle(.secondary)
                Text("Testen und Fehlersuche von DICOM-Verbindungen: Echo, Store, Query/Retrieve, Worklist, Storage SCP, Watchdog und Viewer.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Label("\(AppInfo.developer) – Entwickler, \(AppInfo.location)", systemImage: "person.crop.circle")
                    if let u = updater.repositoryURL { Link("Quellcode auf GitHub", destination: u) }
                }
                .font(.callout).padding(.top, 2)
                Text("Privates, nicht-kommerzielles Open-Source-Projekt unter MIT-Lizenz · Werkzeug für IT und Verbindungstests – nicht für diagnostische Zwecke.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var updatesCard: some View {
        AppCard(icon: "arrow.down.circle", title: "Updates", subtitle: updateSubtitle) {
            HStack {
                if updater.isChecking || updater.isInstalling { ProgressView().controlSize(.small) }
                Button("Nach Updates suchen …") { updater.check(userInitiated: true) }
                    .controlSize(.large)
                    .disabled(updater.isChecking || !updater.isRepositoryConfigured)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if let r = updater.available {
                    HStack {
                        Label("Version \(r.version) ist verfügbar", systemImage: "arrow.down.circle.fill").foregroundStyle(.blue).bold()
                        Spacer()
                        Button("Neuerungen anzeigen und installieren …") { updater.showReleaseSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if !updater.statusText.isEmpty {
                    Text(updater.statusText).font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Text("Update-Kanal")
                    Picker("", selection: $updater.includePrereleases) {
                        Text("Stabil").tag(false)
                        Text("Vorabversionen").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                }
                Text(updater.includePrereleases
                     ? "Auch Beta-Versionen werden angeboten. Beim Wechsel zurück zu Stabil bleibt Ihre Version; das nächste Update kommt, sobald Stabil neuer ist."
                     : "Nur freigegebene, stabile Versionen werden angeboten.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Automatisch nach Updates suchen", isOn: $updater.autoCheck).toggleStyle(.switch)
                Toggle("Updates im Hintergrund herunterladen", isOn: $updater.autoDownload).toggleStyle(.switch)
                    .disabled(!updater.autoCheck)
                Text("Wenn eine neue Version erscheint, sehen Sie ein Fenster mit den Neuerungen. Installiert wird erst, wenn Sie auf „Installieren und neu starten“ klicken.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !updater.skippedVersion.isEmpty {
                    HStack {
                        Text("Übersprungene Version: \(updater.skippedVersion)").font(.callout)
                        Button("Wieder anbieten") { updater.skippedVersion = "" }.controlSize(.small)
                    }
                }
                DisclosureGroup("GitHub-Repository", isExpanded: $showRepository) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("github.com/")
                            TextField("owner/repository", text: $updater.repository).textFieldStyle(.roundedBorder).frame(width: 280)
                            if let u = updater.repositoryURL { Link("Öffnen", destination: u) }
                        }
                        Text("Abgefragt wird die GitHub Releases API. Ein Release muss ein ZIP mit „\(AppInfo.name).app“ enthalten, optional mit .sha256-Prüfsumme.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 6)
                }
                if !updater.isRepositoryConfigured {
                    Text("Kein GitHub-Repository eingetragen – Updates sind deaktiviert.").font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .onAppear { if !updater.isRepositoryConfigured { showRepository = true } }
    }

    private var updateSubtitle: String {
        var s = "Version \(AppInfo.version) (Build \(AppInfo.build))"
        if let d = updater.lastCheck {
            let f = RelativeDateTimeFormatter()
            f.locale = Locale(identifier: "de_DE")
            s += " · zuletzt geprüft \(f.localizedString(for: d, relativeTo: Date()))"
        }
        return s
    }

    private var privacyCard: some View {
        AppCard(icon: "lock.shield", title: "Datenschutz",
                subtitle: "Keine Telemetrie, keine Werbung, kein Konto – Ihre Daten bleiben auf diesem Mac.") {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                InfoRow(icon: "chart.bar.xaxis", title: "Keine Nutzungsdaten",
                        text: "Die App erhebt keine Statistiken, verwendet keine Analyse- oder Tracking-Dienste und sendet nichts an den Entwickler.")
                InfoRow(icon: "network", title: "Netzwerkverbindungen",
                        text: "Verbindungen entstehen nur zu den DICOM-Knoten, die Sie selbst eintragen, sowie für die Update-Prüfung zu GitHub (api.github.com, github.com). Dabei sieht GitHub Ihre IP-Adresse; es gilt die Datenschutzerklärung von GitHub. Die automatische Update-Suche lässt sich oben unter „Updates“ abschalten.")
                InfoRow(icon: "internaldrive", title: "Lokale Speicherung",
                        text: "Einstellungen und Knoten liegen in den macOS-Einstellungen, Protokolle im App-Datenordner (30 Tage). Empfangene DICOM-Dateien speichert der Storage SCP nur im von Ihnen gewählten Ordner.")
                InfoRow(icon: "person.text.rectangle", title: "Patientendaten",
                        text: "DICOM-Objekte, Protokolle und Log-Dateien können Patientendaten enthalten (z. B. Name, ID, Geburtsdatum). Bitte behandeln Sie sie entsprechend den Vorgaben Ihrer Einrichtung und entfernen Sie Patientendaten, bevor Sie Protokolle weitergeben oder in einer Fehlermeldung veröffentlichen. Für Tests eignen sich die Testbilder unter „Store“.")
                InfoRow(icon: "bell", title: "Mitteilungen und Absturzberichte",
                        text: "Popup-Hinweise erzeugt macOS lokal. Absturzberichte sammelt nur macOS selbst, sofern Sie das in den Systemeinstellungen erlaubt haben; die App sendet keine eigenen Berichte.")
            }
        }
    }

    private var intendedUseCard: some View {
        AppCard(icon: "exclamationmark.shield", title: "Zweckbestimmung & rechtliche Hinweise",
                subtitle: "Ein Werkzeug für die IT – kein Medizinprodukt.") {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                InfoRow(icon: "wrench.and.screwdriver", title: "Wofür die App gedacht ist",
                        text: "Für Administratorinnen und Administratoren, Medizintechnik und IT-Support: zum Einrichten, Testen und zur Fehlersuche von DICOM-Verbindungen zwischen PACS, RIS, Modalitäten und Arbeitsplätzen.")
                InfoRow(icon: "cross.case", title: "Nicht für diagnostische Zwecke", tint: .orange,
                        text: "Die App ist kein Medizinprodukt im Sinne der Verordnung (EU) 2017/745 (MDR). Sie darf nicht zur Befundung, Diagnose, Therapieplanung oder für andere medizinische Entscheidungen verwendet werden. Die Bildanzeige im Viewer dient nur der technischen Kontrolle übertragener Daten.")
                InfoRow(icon: "checkmark.seal", title: "Keine Zertifizierung",
                        text: "Die App ist weder von der NEMA noch von einer anderen Stelle zertifiziert oder geprüft und erhebt keinen Anspruch auf vollständige DICOM-Konformität. Ein DICOM Conformance Statement liegt nicht vor.")
                InfoRow(icon: "c.circle", title: "Marken",
                        text: "DICOM® ist eine eingetragene Marke der National Electrical Manufacturers Association (NEMA) für ihre Normen zur digitalen Kommunikation medizinischer Informationen. Die Nennung erfolgt nur beschreibend; es besteht keine Verbindung zur NEMA. macOS ist eine Marke von Apple Inc.")
                InfoRow(icon: "doc.plaintext", title: "Lizenz und Haftung",
                        text: "Privates, nicht-kommerzielles Open-Source-Projekt unter der MIT-Lizenz. Die Software wird ohne jede Gewährleistung bereitgestellt; die Nutzung erfolgt auf eigene Verantwortung.")
            }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Daten & Zurücksetzen", systemImage: "arrow.counterclockwise")
                .font(.title.bold()).labelStyle(TintedIconLabelStyle())
            Text("Setzt die App in den Ausgangszustand zurück: Alle Einstellungen, Knoten, SCP-, Watchdog- und Update-Optionen werden auf Standard gesetzt. Empfangene DICOM-Dateien und Log-Dateien bleiben erhalten.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button { NSWorkspace.shared.open(AppInfo.dataDirectory) } label: { Label("App-Datenordner öffnen", systemImage: "folder") }
                Button {
                    try? FileManager.default.createDirectory(at: state.scpDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(state.scpDirectory)
                } label: { Label("Empfangsordner öffnen", systemImage: "tray.and.arrow.down") }
                Button { showLogs = true } label: { Label("Protokolle anzeigen", systemImage: "doc.text.magnifyingglass") }
                Button(role: .destructive) { confirmReset = true } label: { Text("Alles auf Standard zurücksetzen").foregroundStyle(.red) }
            }
            .controlSize(.large)
        }
    }
}

/// Icon, bold title and explanatory text – used in the information cards on the About page.
struct InfoRow: View {
    let icon: String
    let title: String
    var tint: Color = .accentColor
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 22).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct TintedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.foregroundStyle(Color.accentColor)
            configuration.title
        }
    }
}

/// Rounded settings card: icon, title and subtitle on top, an accessory on the right, optional content below.
struct AppCard<Accessory: View, Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Color.accentColor).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
                Spacer()
                accessory()
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.panelBorder))
    }
}

struct ReleaseNotesSheet: View {
    @EnvironmentObject var updater: Updater
    private static let df: DateFormatter = { let f = DateFormatter(); f.dateStyle = .long; return f }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let r = updater.available {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Eine neue Version von \(AppInfo.name) ist verfügbar").font(.title3.bold())
                        Text("Version \(r.version) – installiert ist \(AppInfo.version)").foregroundStyle(.secondary)
                        if let d = r.published_at { Text("Veröffentlicht am \(Self.df.string(from: d))").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Text(r.title).font(.headline)
                ScrollView {
                    MarkdownText(text: r.body ?? "Keine Release Notes vorhanden.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color.secondary.opacity(0.3))
                if !updater.statusText.isEmpty { Text(updater.statusText).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("Diese Version überspringen") { updater.skip() }
                    Link("Auf GitHub ansehen", destination: r.html_url)
                    Spacer()
                    Button("Später") { updater.showReleaseSheet = false }.keyboardShortcut(.cancelAction)
                    Button {
                        updater.install()
                    } label: {
                        if updater.isInstalling { ProgressView().controlSize(.small) } else { Text("Installieren und neu starten") }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(updater.isInstalling || r.zipAsset == nil)
                }
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }
}

/// Minimal Markdown for release notes: headings, bullet lists and inline formatting.
struct MarkdownText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    Text(inline(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                        .font(line.hasPrefix("###") ? .subheadline.bold() : .headline).padding(.top, 4)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(inline(String(line.dropFirst(2))))
                    }
                } else if !line.isEmpty {
                    Text(inline(line))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
