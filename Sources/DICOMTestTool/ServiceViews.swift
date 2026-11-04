import SwiftUI
import AppKit
import DicomCore

// MARK: - Storage SCP

struct SCPView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: ReceivedObject.ID?
    private static let tf: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolHeader(title: "Storage SCP", subtitle: "Empfängt Bilder (C-STORE) und beantwortet C-ECHO – z. B. als Ziel für C-MOVE oder zum Test von Modalitäten")
            GroupBox {
                HStack(alignment: .bottom, spacing: 14) {
                    LabeledField(label: "AE-Titel", text: $state.scpAE, width: 140)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Port").font(.caption).foregroundStyle(.secondary)
                        TextField("", value: $state.scpPort, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speicherordner").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(state.scpDirectory.path).lineLimit(1).truncationMode(.middle).frame(maxWidth: 320, alignment: .leading)
                            Button("Ändern …") { if let u = chooseFolder() { state.scpDirectory = u } }
                        }
                    }
                    Toggle("Jeden Called AE akzeptieren", isOn: $state.scpAcceptAnyAE)
                    Spacer()
                }
                .disabled(state.scpRunning)
                .padding(6)
            }
            HStack {
                if state.scpRunning {
                    Button { state.stopSCP() } label: { Label("Stoppen", systemImage: "stop.fill") }
                    Label("Läuft auf Port \(state.scpPort) als \(state.scpAE)", systemImage: "circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button { state.startSCP() } label: { Label("Starten", systemImage: "play.fill") }
                    Text("Gestoppt").foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(state.received.count) empfangen").foregroundStyle(.secondary)
                Button("Ordner öffnen") {
                    try? FileManager.default.createDirectory(at: state.scpDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(state.scpDirectory)
                }
                Button("Liste leeren") { state.received.removeAll() }
            }
            Text("Hinweis: Damit andere Geräte senden können, muss die macOS-Firewall eingehende Verbindungen erlauben. Ports < 1024 (z. B. 104) erfordern Root-Rechte – verwenden Sie z. B. 11112.")
                .font(.caption).foregroundStyle(.secondary)
            Table(state.received, selection: $selection) {
                TableColumn("Zeit") { Text(Self.tf.string(from: $0.date)) }.width(60)
                TableColumn("Von") { Text("\($0.callingAE) (\($0.remote))") }
                TableColumn("Patient") { Text(formatPN($0.patientName)) }
                TableColumn("ID", value: \.patientID).width(min: 60, ideal: 90)
                TableColumn("Mod.", value: \.modality).width(44)
                TableColumn("SOP-Klasse") { Text(SOPClass.name($0.sopClassUID)) }
                TableColumn("Transfer Syntax") { Text(TransferSyntax.name($0.transferSyntax)) }
                TableColumn("Größe") { Text(ByteCountFormatter.string(fromByteCount: Int64($0.size), countStyle: .file)) }.width(70)
            }
            .contextMenu(forSelectionType: ReceivedObject.ID.self) { ids in
                if let o = state.received.first(where: { $0.id == ids.first }) {
                    Button("Im Viewer öffnen") { state.viewerURL = o.path; state.section = .viewer }
                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([o.path]) }
                }
            } primaryAction: { ids in
                if let o = state.received.first(where: { $0.id == ids.first }) { state.viewerURL = o.path; state.section = .viewer }
            }
        }
        .padding()
    }
}

// MARK: - Watchdog

struct WatchdogView: View {
    @EnvironmentObject var state: AppState
    private static let tf: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd.MM. HH:mm:ss"; return f }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolHeader(title: "Watchdog", subtitle: "Sendet regelmäßig C-ECHO an ausgewählte Knoten und meldet Ausfälle per macOS-Mitteilung")
            HStack {
                Text("Intervall:")
                TextField("", value: $state.watchInterval, format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                Text("Sekunden")
                Spacer()
                if state.watchRunning {
                    Label("Überwachung aktiv", systemImage: "circle.fill").foregroundStyle(.green)
                    Button { state.stopWatchdog() } label: { Label("Stoppen", systemImage: "stop.fill") }
                } else {
                    Button { state.startWatchdog() } label: { Label("Starten", systemImage: "play.fill") }
                        .disabled(state.watchNodeIDs.isEmpty)
                }
            }
            Table(state.nodes) {
                TableColumn("") { n in
                    Toggle("", isOn: Binding(
                        get: { state.watchNodeIDs.contains(n.id) },
                        set: { on in if on { state.watchNodeIDs.insert(n.id) } else { state.watchNodeIDs.remove(n.id) } }))
                    .labelsHidden()
                }.width(24)
                TableColumn("Knoten") { Text($0.name) }
                TableColumn("Adresse") { Text($0.summary) }
                TableColumn("Status") { n in
                    let s = state.watchStatus[n.id]
                    HStack {
                        Circle().fill(s?.ok == nil ? Color.gray : (s!.ok! ? Color.green : Color.red)).frame(width: 10, height: 10)
                        Text(s?.ok == nil ? "–" : (s!.ok! ? "OK" : "Ausfall"))
                    }
                }.width(90)
                TableColumn("Letzte Prüfung") { n in Text(state.watchStatus[n.id]?.lastCheck.map { Self.tf.string(from: $0) } ?? "") }.width(110)
                TableColumn("Antwortzeit") { n in Text(state.watchStatus[n.id]?.latencyMs.map { String(format: "%.0f ms", $0) } ?? "") }.width(80)
                TableColumn("Fehler in Folge") { n in Text("\(state.watchStatus[n.id]?.failures ?? 0)") }.width(90)
                TableColumn("Meldung") { n in Text(state.watchStatus[n.id]?.message ?? "") }
            }
        }
        .padding()
    }
}

// MARK: - Viewer

@MainActor
final class ViewerModel: ObservableObject {
    @Published var url: URL?
    @Published var file: DicomFile?
    @Published var rows: [TagRow] = []
    @Published var image: CGImage?
    @Published var imageError: String?
    @Published var center = 0.0
    @Published var width = 1.0
    @Published var frame = 0
    var dicomImage: DicomImage?

    func load(_ url: URL) {
        self.url = url
        image = nil; imageError = nil; dicomImage = nil; frame = 0
        do {
            let f = try DicomFile.read(url)
            file = f
            rows = TagRow.flatten(f.meta) + TagRow.flatten(f.dataset)
            if f.dataset[.pixelData] != nil {
                do {
                    let img = try DicomImage(file: f)
                    dicomImage = img
                    center = img.defaultCenter
                    width = img.defaultWidth
                    render()
                } catch {
                    imageError = error.localizedDescription
                }
            }
        } catch {
            file = nil
            rows = []
            imageError = error.localizedDescription
        }
    }

    func render() {
        guard let d = dicomImage else { return }
        do {
            image = try d.render(frame: frame, center: center, width: width)
            imageError = nil
        } catch {
            image = nil
            imageError = error.localizedDescription
        }
    }

    func resetWindow() {
        guard let d = dicomImage else { return }
        center = d.defaultCenter
        width = d.defaultWidth
        render()
    }

    func exportPNG() {
        guard let image else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.png]
        p.nameFieldStringValue = (url?.deletingPathExtension().lastPathComponent ?? "bild") + ".png"
        guard p.runModal() == .OK, let dest = p.url else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: dest)
    }
}

struct ViewerView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var model = ViewerModel()
    @State private var filter = ""
    @State private var dragStart: (Double, Double)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { if let u = chooseFiles(folders: false, multiple: false).first { model.load(u) } } label: {
                    Label("Datei öffnen …", systemImage: "folder")
                }
                if let u = model.url { Text(u.lastPathComponent).font(.headline).lineLimit(1) }
                if let f = model.file {
                    Text("· \(TransferSyntax.name(f.transferSyntax)) · \(SOPClass.name(f.sopClassUID ?? ""))").foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let u = model.url {
                    Button { state.storeQueue.append(u); state.section = .store } label: { Label("Senden …", systemImage: "paperplane") }
                }
            }
            Label("Bildanzeige nur zur technischen Kontrolle der übertragenen Daten – nicht für diagnostische Zwecke.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
            if let e = model.file?.parseError {
                Text("Warnung: \(e)").foregroundStyle(.orange).font(.callout)
            }
            HSplitView {
                imagePane.frame(minWidth: 300, idealWidth: 480)
                VStack(spacing: 4) {
                    TextField("Filter (Tag, Name oder Wert)", text: $filter).textFieldStyle(.roundedBorder)
                    TagTable(rows: filteredRows)
                }
                .frame(minWidth: 380)
            }
        }
        .padding()
        .dropDestination(for: URL.self) { urls, _ in
            if let u = urls.first { model.load(u) }
            return true
        }
        .onAppear { if let u = state.viewerURL { model.load(u); state.viewerURL = nil } }
        .onChange(of: state.viewerURL) { _, u in if let u { model.load(u); state.viewerURL = nil } }
    }

    private var filteredRows: [TagRow] {
        guard !filter.isEmpty else { return model.rows }
        let f = filter.lowercased()
        return model.rows.filter { $0.tag.lowercased().contains(f) || $0.name.lowercased().contains(f) || $0.value.lowercased().contains(f) }
    }

    @ViewBuilder private var imagePane: some View {
        VStack(spacing: 6) {
            ZStack {
                Color.black
                if let img = model.image {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else if let e = model.imageError {
                    Text(e).foregroundStyle(.white).padding()
                } else if model.url == nil {
                    Text("DICOM-Datei hierher ziehen").foregroundStyle(.gray)
                } else {
                    Text("Keine Bilddaten").foregroundStyle(.gray)
                }
            }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { g in
                    guard let d = model.dicomImage, d.isMonochrome, !d.isEncapsulated else { return }
                    if dragStart == nil { dragStart = (model.center, model.width) }
                    let (c0, w0) = dragStart!
                    let k = max(w0, 1) / 300
                    model.width = max(1, w0 + Double(g.translation.width) * k)
                    model.center = c0 + Double(g.translation.height) * k
                    model.render()
                }
                .onEnded { _ in dragStart = nil })
            if let d = model.dicomImage {
                HStack {
                    if d.isMonochrome && !d.isEncapsulated {
                        Text(String(format: "W: %.0f  L: %.0f", model.width, model.center)).font(.system(.caption, design: .monospaced))
                        Button("Zurücksetzen") { model.resetWindow() }.controlSize(.small)
                    }
                    Text("\(d.columns)×\(d.rows)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("PNG exportieren …") { model.exportPNG() }.controlSize(.small).disabled(model.image == nil)
                }
                if d.frameCount > 1 {
                    HStack {
                        Text("Frame \(model.frame + 1)/\(d.frameCount)").font(.caption)
                        Slider(value: Binding(get: { Double(model.frame) }, set: { model.frame = Int($0); model.render() }),
                               in: 0...Double(d.frameCount - 1), step: 1)
                    }
                }
                Text("Ziehen mit der Maus: horizontal = Fensterbreite, vertikal = Fensterlage").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
