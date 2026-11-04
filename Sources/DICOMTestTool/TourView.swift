import SwiftUI

/// Guided introduction: one page per tool with purpose, setup steps and a tip.
struct TourView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private let pages = TourPage.all

    var body: some View {
        // Clamped: a held arrow key can fire the "Zurück" shortcut again while the button is still fading out.
        let index = min(max(self.index, 0), pages.count - 1)
        let page = pages[index]
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(Color.accentColor.gradient)
                    if let icon = page.icon {
                        Image(systemName: icon).font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
                    } else {
                        Image(nsImage: NSApp.applicationIconImage).resizable().padding(6)
                    }
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 12) {
                    Text(index == 0 || index == pages.count - 1 ? " " : "Schritt \(index) von \(pages.count - 2)")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text(page.title).font(.largeTitle.bold())
                    Text(.init(page.summary)).font(.title3).fixedSize(horizontal: false, vertical: true)
                    if !page.steps.isEmpty {
                        Text("So richten Sie es ein").font(.headline).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(Array(page.steps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                                        .frame(width: 18, height: 18).background(Circle().fill(Color.accentColor))
                                    Text(.init(step)).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    if let tip = page.tip {
                        Label { Text(.init(tip)).fixedSize(horizontal: false, vertical: true) } icon: {
                            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 32).padding(.top, 36).padding(.bottom, 16)
            .id(index)
            .transition(.opacity)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Circle().fill(i == index ? Color.accentColor : Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                            .onTapGesture { go(to: i) }
                    }
                }
                Spacer()
                if let section = page.section {
                    Button("Werkzeug öffnen") {
                        state.section = section
                        presentWindow(id: AppInfo.mainWindowID, using: openWindow)
                    }
                }
                if index > 0 {
                    Button("Zurück") { go(to: index - 1) }.keyboardShortcut(.leftArrow, modifiers: [])
                }
                if index < pages.count - 1 {
                    Button(index == 0 ? "Tour starten" : "Weiter") { go(to: index + 1) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Los geht’s") {
                        dismiss()
                        presentWindow(id: AppInfo.mainWindowID, using: openWindow)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 760, height: 560)
        .onAppear { WindowOpener.action = WindowOpener.action ?? openWindow; self.index = 0; UserDefaults.standard.set(true, forKey: TourPage.shownKey) }
    }

    private func go(to target: Int) {
        let clamped = min(max(target, 0), pages.count - 1)
        guard clamped != index else { return }
        withAnimation { index = clamped }
    }
}

struct TourPage {
    var icon: String?
    var title: String
    var summary: String
    var steps: [String] = []
    var tip: String?
    var section: AppSection?

    static let shownKey = "tourShown"

    static let all: [TourPage] = [
        TourPage(icon: nil, title: "Willkommen beim \(AppInfo.name)",
                 summary: "Mit dieser App prüfen Sie DICOM-Verbindungen zu PACS, RIS, Modalitäten und Befundstationen – vom einfachen Verbindungstest bis zum Senden, Abfragen und Empfangen von Bildern. Die Tour zeigt in wenigen Schritten, was jedes Werkzeug kann und wie Sie es einstellen.",
                 tip: "Alle Aktionen landen im **Protokoll** unten im Fenster – inklusive ausgehandelter Presentation Contexts. Über „Exportieren …“ speichern Sie es als TXT für den Support."),
        TourPage(icon: AppSection.nodes.icon, title: "Knoten & Einstellungen",
                 summary: "Hier legen Sie die Gegenstellen an, mit denen Sie kommunizieren wollen, und wie sich die App selbst im Netzwerk meldet.",
                 steps: ["Unter **Lokal** den eigenen *Calling AE-Titel* eintragen – so, wie er beim PACS freigeschaltet ist.",
                         "Mit **Hinzufügen** einen Knoten anlegen: Name, *Called AE-Titel*, Hostname bzw. IP-Adresse und Port (meist 104 oder 11112).",
                         "Bei langsamen Verbindungen den *Timeout* erhöhen."],
                 tip: "Ein Knoten muss den Calling AE der App meist auch auf seiner Seite kennen, sonst lehnt er die Assoziation ab.",
                 section: .nodes),
        TourPage(icon: AppSection.echo.icon, title: "Echo (Verification)",
                 summary: "Der „DICOM-Ping“: Ein C-ECHO prüft, ob die Gegenstelle erreichbar ist und die AE-Titel akzeptiert. Gemessen werden Aufbau der Assoziation, Echo und Gesamtzeit.",
                 steps: ["Oben den **Ziel-Knoten** auswählen.",
                         "Optional die Anzahl der **Wiederholungen** einstellen, um Schwankungen zu sehen.",
                         "Auf **Echo senden** klicken und das Ergebnis im Protokoll prüfen."],
                 tip: "Schnell geht es auch über das Menüleisten-Symbol: **Echo senden an** › Knoten.",
                 section: .echo),
        TourPage(icon: AppSection.store.icon, title: "Store (Senden)",
                 summary: "Sendet DICOM-Dateien per C-STORE an einen Knoten – einzeln, als Ordner oder als erzeugte Testbilder. Die Transfer-Syntax wird bei Bedarf automatisch umgewandelt.",
                 steps: ["Ziel-Knoten wählen.",
                         "Dateien oder Ordner per **Drag & Drop** in die Liste ziehen oder über **Dateien / Ordner hinzufügen …** auswählen.",
                         "Alternativ unter **Testbilder erzeugen** auf **Erzeugen** klicken, wenn keine echten Daten verwendet werden sollen.",
                         "Auf **Senden** klicken – pro Datei wird der Status angezeigt."],
                 tip: "Für Tests ohne Patientendaten eignen sich die Testbilder (Secondary Capture) ideal.",
                 section: .store),
        TourPage(icon: AppSection.find.icon, title: "Query / Retrieve",
                 summary: "Sucht per C-FIND im PACS nach Patienten, Studien, Serien und Bildern und holt Treffer per C-MOVE zu einem Ziel – zum Beispiel zum eingebauten Storage SCP.",
                 steps: ["Ziel-Knoten wählen, *Informationsmodell* (Study oder Patient Root) und *Ebene* festlegen.",
                         "Suchkriterien eintragen: Name mit Platzhalter (z. B. `MUSTER*`), ID, Datum – ein Klick ins Datumsfeld öffnet den Kalender.",
                         "**Suchen** – per Doppelklick auf einen Treffer geht es eine Ebene tiefer.",
                         "Für Retrieve den **Ziel-AE** eintragen und **C-MOVE** starten."],
                 tip: "Das PACS muss den Ziel-AE kennen (AE-Titel, IP und Port des Empfängers). Nutzen Sie den Storage SCP dieser App als Ziel.",
                 section: .find),
        TourPage(icon: AppSection.worklist.icon, title: "Worklist",
                 summary: "Fragt die Modality Worklist (MWL) beim RIS ab – genau so, wie es eine Modalität tun würde. Ideal, um Aufträge und Zuordnungen zu prüfen.",
                 steps: ["Worklist-Server als Ziel-Knoten wählen.",
                         "Filter setzen: Modalität, Station AE oder Datum (Kalender, **Heute** oder **Alle**).",
                         "**Worklist abfragen** – ein Klick auf einen Auftrag zeigt alle Tags."],
                 tip: "Viele RIS liefern nur Aufträge für die passende *Station AE* oder Modalität – leere Felder bedeuten „beliebig“.",
                 section: .worklist),
        TourPage(icon: AppSection.scp.icon, title: "Storage SCP (Empfang)",
                 summary: "Macht den Mac zum DICOM-Empfänger: Er nimmt C-STORE und C-ECHO an und speichert die Bilder sortiert nach Patienten-ID.",
                 steps: ["Eigenen **AE-Titel** und **Port** festlegen (Ports unter 1024 benötigen Administratorrechte – 11112 ist üblich).",
                         "Den **Speicherordner** wählen.",
                         "Festlegen, ob **jeder Called AE** akzeptiert wird.",
                         "**Starten** – empfangene Objekte erscheinen sofort in der Liste."],
                 tip: "Läuft auch im Hintergrund weiter, wenn das Fenster geschlossen ist – gesteuert über die Menüleiste.",
                 section: .scp),
        TourPage(icon: AppSection.watchdog.icon, title: "Watchdog",
                 summary: "Überwacht Knoten dauerhaft per C-ECHO und meldet sich mit einem Popup-Hinweis, wenn ein Knoten ausfällt oder wieder erreichbar ist.",
                 steps: ["Die zu überwachenden **Knoten anhaken**.",
                         "Das **Intervall** in Sekunden einstellen.",
                         "**Starten** – der Status erscheint in der Liste und am Menüleisten-Symbol (Warndreieck bei Ausfall).",
                         "Unter **Allgemein › Popup-Hinweise** die Mitteilungen erlauben."],
                 tip: "Mit „Watchdog beim Start automatisch starten“ und „App bei Anmeldung öffnen“ läuft die Überwachung nach jedem Neustart.",
                 section: .watchdog),
        TourPage(icon: AppSection.viewer.icon, title: "Viewer / Tag-Dump",
                 summary: "Zeigt alle Tags einer DICOM-Datei inklusive Sequenzen und das Bild mit Fensterung an.",
                 steps: ["Über **Datei öffnen …** eine Datei laden oder sie ins Fenster ziehen.",
                         "Tags über das **Filterfeld** durchsuchen.",
                         "Im Bild mit gedrückter Maustaste ziehen, um **Fensterbreite und -mitte** zu ändern.",
                         "Bei Bedarf über **PNG exportieren …** speichern oder über **Senden …** direkt an Store übergeben."],
                 section: .viewer),
        TourPage(icon: "menubar.rectangle", title: "Menüleiste & Einstellungen",
                 summary: "Das Symbol oben rechts in der Menüleiste ist der Schnellzugriff: SCP und Watchdog starten oder stoppen, Echo senden und jedes Werkzeug öffnen – auch wenn andere Programme im Vollbild laufen.",
                 steps: ["Unter **Allgemein** einstellen, ob die App bei der Anmeldung startet und ob Dock- und Menüleisten-Symbol angezeigt werden.",
                         "**Popup-Hinweise** aktivieren und mit *Test-Mitteilung* prüfen.",
                         "Unter **Über** finden Sie Updates, diese Einführung sowie Datenordner, Protokolle und das Zurücksetzen."],
                 section: .general),
        TourPage(icon: "checkmark.seal.fill", title: "Alles bereit",
                 summary: "Legen Sie als Erstes Ihre Knoten an und prüfen Sie die Verbindung mit einem Echo. Diese Tour finden Sie jederzeit wieder im Menüleisten-Menü unter **Einführung …** und unter **Über**.",
                 tip: "Die App ist ein Testwerkzeug und nicht für diagnostische Zwecke bestimmt."),
    ]
}
