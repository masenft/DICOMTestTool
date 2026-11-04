import SwiftUI
import AppKit
import DicomCore

// MARK: - Nodes

struct NodesView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolHeader(title: "Knoten & Einstellungen", subtitle: "Entfernte DICOM-Gegenstellen (PACS, Modalitäten, Worklist-Server) und lokale Einstellungen")
            GroupBox("Lokal") {
                HStack(spacing: 20) {
                    LabeledField(label: "Eigener AE-Titel (Calling AE)", text: $state.callingAE)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Timeout (Sekunden)").font(.caption).foregroundStyle(.secondary)
                        TextField("", value: $state.timeout, format: .number).textFieldStyle(.roundedBorder).frame(width: 80)
                    }
                    Spacer()
                }
                .padding(6)
            }
            HStack {
                Text("Gegenstellen").font(.headline)
                Spacer()
                Button {
                    let n = DicomNode(name: "Neuer Knoten", aeTitle: "ANY-SCP", host: "192.168.1.10", port: 104)
                    state.nodes.append(n)
                    selection = n.id
                } label: { Label("Hinzufügen", systemImage: "plus") }
                Button {
                    if let n = state.nodes.first(where: { $0.id == selection }) {
                        var c = n; c.id = UUID(); c.name += " (Kopie)"
                        state.nodes.append(c); selection = c.id
                    }
                } label: { Label("Duplizieren", systemImage: "plus.square.on.square") }.disabled(selection == nil)
                Button(role: .destructive) {
                    state.nodes.removeAll { $0.id == selection }
                    selection = nil
                } label: { Label("Löschen", systemImage: "trash") }.disabled(selection == nil)
            }
            Table(state.nodes, selection: $selection) {
                TableColumn("Name", value: \.name)
                TableColumn("AE-Titel", value: \.aeTitle)
                TableColumn("Host", value: \.host)
                TableColumn("Port") { Text(String($0.port)) }.width(60)
            }
            .frame(minHeight: 140)
            if let idx = state.nodes.firstIndex(where: { $0.id == selection }) {
                GroupBox("Bearbeiten") {
                    HStack(alignment: .bottom, spacing: 14) {
                        LabeledField(label: "Name", text: $state.nodes[idx].name)
                        LabeledField(label: "AE-Titel (Called AE)", text: $state.nodes[idx].aeTitle, width: 150)
                        LabeledField(label: "Host / IP", text: $state.nodes[idx].host)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Port").font(.caption).foregroundStyle(.secondary)
                            TextField("", value: $state.nodes[idx].port, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder).frame(width: 80)
                        }
                        Button("Echo testen") {
                            state.selectedNodeID = state.nodes[idx].id
                            let node = state.nodes[idx]
                            let settings = state.settings
                            let log = state.logger("Echo")
                            Task {
                                do {
                                    let r = try await DicomSCU.echo(node: node, settings: settings, log: log)
                                    state.append("Echo", String(format: "%@: %@ (%.0f ms)", node.name, DimseStatus.text(r.status), r.totalTime * 1000))
                                } catch {
                                    state.append("Echo", "\(node.name): \(error.localizedDescription)", error: true)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(6)
                }
                if state.nodes[idx].aeTitle.count > 16 {
                    Text("AE-Titel dürfen max. 16 Zeichen lang sein.").foregroundStyle(.red).font(.callout)
                }
            }
        }
        .padding()
    }
}

// MARK: - Echo

struct EchoView: View {
    @EnvironmentObject var state: AppState
    @State private var repeatCount = 1
    @State private var running = false
    @State private var results: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolHeader(title: "C-ECHO", subtitle: "Prüft Netzwerkverbindung, AE-Titel und Assoziationsaufbau (Verification SOP Class)")
            NodePicker()
            HStack {
                Stepper("Wiederholungen: \(repeatCount)", value: $repeatCount, in: 1...100)
                Button {
                    run()
                } label: { Label("Echo senden", systemImage: "dot.radiowaves.left.and.right") }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(running || state.selectedNode == nil)
                if running { ProgressView().controlSize(.small) }
                Spacer()
            }
            List(results.reversed(), id: \.self) { Text($0).font(.system(.body, design: .monospaced)) }
        }
        .padding()
    }

    private func run() {
        guard let node = state.selectedNode else { return }
        running = true
        let settings = state.settings, log = state.logger("Echo"), n = repeatCount
        Task {
            var ok = 0
            for i in 1...n {
                do {
                    let r = try await DicomSCU.echo(node: node, settings: settings, log: log)
                    if r.status == 0 { ok += 1 }
                    results.append(String(format: "#%d %@ – %@  (Assoziation %.0f ms, Echo %.0f ms, gesamt %.0f ms)",
                                          i, node.aeTitle, DimseStatus.text(r.status), r.associationTime * 1000, r.echoTime * 1000, r.totalTime * 1000))
                } catch {
                    results.append("#\(i) \(node.aeTitle) – FEHLER: \(error.localizedDescription)")
                    state.append("Echo", error.localizedDescription, error: true)
                }
            }
            if n > 1 { results.append("Ergebnis: \(ok)/\(n) erfolgreich") }
            running = false
        }
    }
}

// MARK: - Store

struct StoreFileRow: Identifiable {
    let id = UUID()
    let url: URL
    var status = "bereit"
    var ok: Bool?
}

struct StoreView: View {
    @EnvironmentObject var state: AppState
    @State private var files: [StoreFileRow] = []
    @State private var running = false
    @State private var progress = 0.0
    @State private var options = TestImageOptions()
    @State private var task: Task<Void, Never>?
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolHeader(title: "C-STORE", subtitle: "Sendet DICOM-Dateien oder ganze Ordner an die Gegenstelle (Dateien hierher ziehen)")
            NodePicker()
            GroupBox("Testbilder erzeugen (Secondary Capture, 512×512, 12 Bit)") {
                HStack(alignment: .bottom, spacing: 12) {
                    LabeledField(label: "Patientenname (NACHNAME^VORNAME)", text: $options.patientName, width: 200)
                    LabeledField(label: "Patienten-ID", text: $options.patientID, width: 110)
                    DateField(label: "Geburtsdatum", text: $options.birthDate, width: 100)
                    LabeledField(label: "Accession", text: $options.accessionNumber, width: 100)
                    LabeledField(label: "Modalität", text: $options.modality, width: 50)
                    Stepper("Anzahl: \(options.count)", value: $options.count, in: 1...500)
                    Button("Erzeugen") { generate() }
                    Spacer()
                }
                .padding(6)
            }
            HStack {
                Button { add(chooseFiles()) } label: { Label("Dateien / Ordner hinzufügen …", systemImage: "plus") }
                Button("Liste leeren") { files.removeAll() }.disabled(running)
                Spacer()
                Text("\(files.count) Datei(en)").foregroundStyle(.secondary)
                if running {
                    ProgressView(value: progress).frame(width: 160)
                    Button("Abbrechen") { task?.cancel() }
                } else {
                    Button { send() } label: { Label("Senden", systemImage: "paperplane.fill") }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(files.isEmpty || state.selectedNode == nil)
                }
            }
            Table(files) {
                TableColumn("") { r in
                    Image(systemName: r.ok == nil ? "circle" : (r.ok! ? "checkmark.circle.fill" : "xmark.octagon.fill"))
                        .foregroundStyle(r.ok == nil ? Color.secondary : (r.ok! ? Color.green : Color.red))
                }.width(22)
                TableColumn("Datei") { Text($0.url.lastPathComponent) }
                TableColumn("Ordner") { Text($0.url.deletingLastPathComponent().path).foregroundStyle(.secondary) }
                TableColumn("Status", value: \.status)
            }
            .overlay {
                if files.isEmpty {
                    Text("DICOM-Dateien oder Ordner hierher ziehen").foregroundStyle(.secondary)
                }
            }
            .border(dropTargeted ? Color.accentColor : Color.clear, width: 2)
            .dropDestination(for: URL.self) { urls, _ in add(urls); return true } isTargeted: { dropTargeted = $0 }
        }
        .padding()
        .onAppear {
            if !state.storeQueue.isEmpty { add(state.storeQueue); state.storeQueue = [] }
        }
        .onReceive(NotificationCenter.default.publisher(for: SnapshotHook.storeSend)) { _ in send() } // screenshot hook
    }

    private func add(_ urls: [URL]) {
        let found = DicomSCU.collectFiles(urls)
        let existing = Set(files.map(\.url))
        files += found.filter { !existing.contains($0) }.map { StoreFileRow(url: $0) }
        if found.isEmpty && !urls.isEmpty { state.append("Store", "Keine DICOM-Dateien gefunden", error: true) }
    }

    private func generate() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DICOMTestTool/\(UUID().uuidString)")
        do {
            var o = options
            o.birthDate = DicomDateInput.normalize(o.birthDate, allowsRange: false)
            let urls = try TestImageGenerator.generate(o, into: dir)
            add(urls)
            state.append("Store", "\(urls.count) Testbild(er) erzeugt")
        } catch {
            state.append("Store", "Testbild: \(error.localizedDescription)", error: true)
        }
    }

    private func send() {
        guard let node = state.selectedNode else { return }
        running = true
        progress = 0
        for i in files.indices { files[i].status = "wartet"; files[i].ok = nil }
        let urls = files.map(\.url), settings = state.settings, log = state.logger("Store")
        let start = Date()
        task = Task {
            do {
                let results = try await DicomSCU.store(node: node, settings: settings, files: urls, log: log) { done, total, r in
                    Task { @MainActor in
                        progress = Double(done) / Double(max(total, 1))
                        if let i = files.firstIndex(where: { $0.url == r.url }) {
                            files[i].ok = r.ok
                            files[i].status = r.error ?? (r.status.map { DimseStatus.text($0) } ?? "")
                        }
                    }
                }
                let ok = results.filter(\.ok).count
                state.append("Store", String(format: "Fertig: %d/%d erfolgreich in %.1f s", ok, results.count, Date().timeIntervalSince(start)),
                             error: ok != results.count)
            } catch {
                state.append("Store", error.localizedDescription, error: true)
            }
            running = false
        }
    }
}
