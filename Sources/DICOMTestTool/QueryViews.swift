import SwiftUI
import DicomCore

// MARK: - Query / Retrieve

enum QueryModel: String, CaseIterable, Identifiable {
    case study = "Study Root", patient = "Patient Root"
    var id: String { rawValue }
    var findUID: String { self == .study ? SOPClass.studyRootFind : SOPClass.patientRootFind }
    var moveUID: String { self == .study ? SOPClass.studyRootMove : SOPClass.patientRootMove }
}

enum QueryLevel: String, CaseIterable, Identifiable {
    case patient = "PATIENT", study = "STUDY", series = "SERIES", image = "IMAGE"
    var id: String { rawValue }
}

struct FindRow: Identifiable {
    let id = UUID()
    let level: QueryLevel
    let dataset: DataSet
    var name: String { formatPN(dataset.string(.patientName)) }
    var patientID: String { dataset.string(.patientID) ?? "" }
    var birthDate: String { formatDA(dataset.string(.patientBirthDate)) }
    var date: String { formatDA(dataset.string(.studyDate) ?? dataset.string(.seriesDate) ?? dataset.string(.contentDate)) }
    var modality: String { dataset.string(.modalitiesInStudy) ?? dataset.string(.modality) ?? "" }
    var accession: String { dataset.string(.accessionNumber) ?? "" }
    var studyUID: String { dataset.string(.studyInstanceUID) ?? "" }
    var seriesUID: String { dataset.string(.seriesInstanceUID) ?? "" }
    var sopUID: String { dataset.string(.sopInstanceUID) ?? "" }
    var description: String {
        switch level {
        case .patient: return ""
        case .study: return dataset.string(.studyDescription) ?? ""
        case .series: return "#\(dataset.string(.seriesNumber) ?? "") \(dataset.string(.seriesDescription) ?? "")"
        case .image: return "Bild \(dataset.string(.instanceNumber) ?? "") – \(SOPClass.name(dataset.string(.sopClassUID) ?? ""))"
        }
    }
    var count: String {
        let t: Tag
        switch level {
        case .patient: t = .numberOfPatientRelatedStudies
        case .study: t = .numberOfStudyRelatedInstances
        case .series: t = .numberOfSeriesRelatedInstances
        case .image: return ""
        }
        return dataset.string(t) ?? ""
    }
}

struct FindView: View {
    @EnvironmentObject var state: AppState
    @State private var model: QueryModel = .study
    @State private var level: QueryLevel = .study
    @State private var patientName = ""
    @State private var patientID = ""
    @State private var birthDate = ""
    @State private var studyDate = ""
    @State private var accession = ""
    @State private var modality = ""
    @State private var studyUID = ""
    @State private var seriesUID = ""
    @State private var moveDestination = ""
    @State private var rows: [FindRow] = []
    @State private var selection = Set<FindRow.ID>()
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var detail: FindRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolHeader(title: "C-FIND / C-MOVE", subtitle: "Suche im PACS und Abruf zu einem Ziel-AE. Platzhalter * und ? sowie Datumsbereiche (20260101-20261231) sind erlaubt.")
            NodePicker()
            HStack(spacing: 16) {
                Picker("Modell", selection: $model) { ForEach(QueryModel.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 220)
                Picker("Ebene", selection: $level) {
                    ForEach(QueryLevel.allCases) { l in
                        if model == .patient || l != .patient { Text(l.rawValue).tag(l) }
                    }
                }.frame(width: 200)
                Spacer()
            }
            .onChange(of: model) { _, m in if m == .study && level == .patient { level = .study } }
            HStack(alignment: .bottom, spacing: 10) {
                LabeledField(label: "Patientenname", text: $patientName, prompt: "MUSTER*", width: 160)
                LabeledField(label: "Patienten-ID", text: $patientID, width: 110)
                DateField(label: "Geburtsdatum", text: $birthDate, width: 100)
                if level != .patient {
                    DateField(label: "Studiendatum", text: $studyDate, allowsRange: true)
                    LabeledField(label: "Accession", text: $accession, width: 100)
                    LabeledField(label: "Modalität", text: $modality, prompt: "CT", width: 50)
                }
            }
            if level == .series || level == .image {
                HStack(spacing: 10) {
                    LabeledField(label: "Study Instance UID (Pflicht)", text: $studyUID, width: 330)
                    if level == .image { LabeledField(label: "Series Instance UID (Pflicht)", text: $seriesUID, width: 330) }
                }
            }
            HStack {
                if running {
                    ProgressView().controlSize(.small)
                    Button("Abbrechen") { task?.cancel() }
                } else {
                    Button { find() } label: { Label("Suchen", systemImage: "magnifyingglass") }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(state.selectedNode == nil)
                }
                Button("Felder leeren") {
                    patientName = ""; patientID = ""; birthDate = ""; studyDate = ""; accession = ""; modality = ""; studyUID = ""; seriesUID = ""
                }
                Text("\(rows.count) Treffer").foregroundStyle(.secondary)
                Spacer()
                LabeledField(label: "Move-Ziel (AE)", text: $moveDestination, prompt: state.scpAE, width: 130)
                Button { move() } label: { Label("C-MOVE", systemImage: "arrow.down.doc") }
                    .disabled(selection.isEmpty || running || level == .patient && model == .study)
            }
            Table(rows, selection: $selection) {
                TableColumn("Patient", value: \.name)
                TableColumn("ID", value: \.patientID).width(min: 60, ideal: 90)
                TableColumn("Geb.", value: \.birthDate).width(80)
                TableColumn("Datum", value: \.date).width(80)
                TableColumn("Mod.", value: \.modality).width(50)
                TableColumn("Beschreibung", value: \.description)
                TableColumn("Accession", value: \.accession).width(min: 60, ideal: 90)
                TableColumn("Anz.", value: \.count).width(40)
            }
            .contextMenu(forSelectionType: FindRow.ID.self) { ids in
                if let r = rows.first(where: { ids.first == $0.id }) {
                    Button("Details …") { detail = r }
                    if r.level == .patient { Button("Studien anzeigen") { drill(r, to: .study) } }
                    if r.level == .study { Button("Serien anzeigen") { drill(r, to: .series) } }
                    if r.level == .series { Button("Bilder anzeigen") { drill(r, to: .image) } }
                    Button("C-MOVE an \(moveTarget)") { selection = ids; move() }
                    Button("UID kopieren") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(r.sopUID.isEmpty ? (r.seriesUID.isEmpty ? r.studyUID : r.seriesUID) : r.sopUID, forType: .string)
                    }
                }
            } primaryAction: { ids in
                if let r = rows.first(where: { ids.first == $0.id }) {
                    switch r.level {
                    case .patient: drill(r, to: .study)
                    case .study: drill(r, to: .series)
                    case .series: drill(r, to: .image)
                    case .image: detail = r
                    }
                }
            }
        }
        .padding()
        .sheet(item: $detail) { r in DatasetDumpView(dataset: r.dataset, title: "C-FIND-Antwort (\(r.level.rawValue))") }
    }

    private var moveTarget: String { moveDestination.isEmpty ? state.scpAE : moveDestination }

    private func drill(_ r: FindRow, to l: QueryLevel) {
        if l == .study { patientID = r.patientID; patientName = "" }
        if l == .series { studyUID = r.studyUID }
        if l == .image { studyUID = r.studyUID; seriesUID = r.seriesUID }
        level = l
        find()
    }

    private func buildQuery() -> DataSet {
        var q = DataSet()
        q.set(.queryRetrieveLevel, level.rawValue)
        if patientName.contains(where: { !$0.isASCII }) { q.set(.specificCharacterSet, "ISO_IR 100") }
        switch level {
        case .patient:
            q.set(.patientName, patientName); q.set(.patientID, patientID); q.set(.patientBirthDate, DicomDateInput.normalize(birthDate, allowsRange: false))
            q.set(.patientSex, ""); q.set(.numberOfPatientRelatedStudies, "")
        case .study:
            q.set(.patientName, patientName); q.set(.patientID, patientID); q.set(.patientBirthDate, DicomDateInput.normalize(birthDate, allowsRange: false))
            q.set(.patientSex, "")
            q.set(.studyDate, DicomDateInput.normalize(studyDate, allowsRange: true)); q.set(.studyTime, ""); q.set(.accessionNumber, accession)
            q.set(.modalitiesInStudy, modality); q.set(.studyDescription, ""); q.set(.studyID, "")
            q.set(.referringPhysicianName, ""); q.set(.studyInstanceUID, studyUID)
            q.set(.numberOfStudyRelatedSeries, ""); q.set(.numberOfStudyRelatedInstances, "")
        case .series:
            if model == .patient { q.set(.patientID, patientID) }
            q.set(.studyInstanceUID, studyUID)
            q.set(.seriesInstanceUID, ""); q.set(.modality, modality); q.set(.seriesNumber, "")
            q.set(.seriesDescription, ""); q.set(.seriesDate, ""); q.set(.numberOfSeriesRelatedInstances, "")
        case .image:
            if model == .patient { q.set(.patientID, patientID) }
            q.set(.studyInstanceUID, studyUID); q.set(.seriesInstanceUID, seriesUID)
            q.set(.sopInstanceUID, ""); q.set(.sopClassUID, ""); q.set(.instanceNumber, ""); q.set(.contentDate, "")
        }
        return q
    }

    private func find() {
        guard let node = state.selectedNode else { return }
        if (level == .series || level == .image) && studyUID.isEmpty {
            state.append("Find", "Für die Ebene \(level.rawValue) ist eine Study Instance UID nötig", error: true); return
        }
        rows = []
        selection = []
        running = true
        let q = buildQuery(), lvl = level, sop = model.findUID, settings = state.settings, log = state.logger("Find")
        task = Task {
            do {
                try await DicomSCU.find(node: node, settings: settings, sopClass: sop, query: q, log: log) { ds in
                    let row = FindRow(level: lvl, dataset: ds)
                    Task { @MainActor in rows.append(row) }
                }
            } catch {
                state.append("Find", error.localizedDescription, error: true)
            }
            running = false
        }
    }

    private func move() {
        guard let node = state.selectedNode else { return }
        let selected = rows.filter { selection.contains($0.id) }
        guard !selected.isEmpty else { return }
        let dest = moveTarget, sop = model.moveUID, pm = model, settings = state.settings, log = state.logger("Move")
        running = true
        task = Task {
            for r in selected {
                var q = DataSet()
                q.set(.queryRetrieveLevel, r.level.rawValue)
                if pm == .patient || r.level == .patient { q.set(.patientID, r.patientID) }
                if r.level != .patient { q.set(.studyInstanceUID, r.studyUID) }
                if r.level == .series || r.level == .image { q.set(.seriesInstanceUID, r.seriesUID) }
                if r.level == .image { q.set(.sopInstanceUID, r.sopUID) }
                do {
                    try await DicomSCU.move(node: node, settings: settings, sopClass: sop, query: q, destination: dest, log: log) { p in
                        if DimseStatus.isPending(p.status) {
                            log("  … \(p.completed) übertragen, \(p.remaining) verbleibend, \(p.failed) Fehler")
                        }
                    }
                } catch {
                    state.append("Move", error.localizedDescription, error: true)
                }
            }
            running = false
        }
    }
}

// MARK: - Worklist

struct WorklistRow: Identifiable {
    let id = UUID()
    let dataset: DataSet
    private var sps: DataSet { dataset.items(.scheduledProcedureStepSequence).first ?? DataSet() }
    var name: String { formatPN(dataset.string(.patientName)) }
    var patientID: String { dataset.string(.patientID) ?? "" }
    var birthDate: String { formatDA(dataset.string(.patientBirthDate)) }
    var sex: String { dataset.string(.patientSex) ?? "" }
    var accession: String { dataset.string(.accessionNumber) ?? "" }
    var procedure: String { dataset.string(.requestedProcedureDescription) ?? sps.string(.scheduledProcedureStepDescription) ?? "" }
    var modality: String { sps.string(.modality) ?? "" }
    var scheduled: String { "\(formatDA(sps.string(.scheduledProcedureStepStartDate))) \(formatTM(sps.string(.scheduledProcedureStepStartTime)))" }
    var station: String { sps.string(.scheduledStationAETitle) ?? "" }
}

struct WorklistView: View {
    @EnvironmentObject var state: AppState
    @State private var patientName = ""
    @State private var patientID = ""
    @State private var accession = ""
    @State private var modality = ""
    @State private var stationAE = ""
    @State private var date = dicomDate()
    @State private var rows: [WorklistRow] = []
    @State private var selection: WorklistRow.ID?
    @State private var running = false
    @State private var detail: WorklistRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolHeader(title: "Modality Worklist (MWL)", subtitle: "Fragt geplante Untersuchungen vom RIS/Worklist-Server ab, wie es eine Modalität tun würde")
            NodePicker()
            HStack(alignment: .bottom, spacing: 10) {
                LabeledField(label: "Patientenname", text: $patientName, prompt: "MUSTER*", width: 150)
                LabeledField(label: "Patienten-ID", text: $patientID, width: 100)
                LabeledField(label: "Accession", text: $accession, width: 100)
                LabeledField(label: "Modalität", text: $modality, prompt: "CR", width: 50)
                LabeledField(label: "Station AE", text: $stationAE, width: 110)
                DateField(label: "Datum", text: $date, allowsRange: true)
                Button("Heute") { date = dicomDate() }
                Button("Alle") { date = "" }
            }
            HStack {
                Button { query() } label: { Label("Worklist abfragen", systemImage: "list.clipboard") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(running || state.selectedNode == nil)
                if running { ProgressView().controlSize(.small) }
                Text("\(rows.count) Einträge").foregroundStyle(.secondary)
                Spacer()
            }
            Table(rows, selection: $selection) {
                TableColumn("Patient", value: \.name)
                TableColumn("ID", value: \.patientID).width(min: 60, ideal: 90)
                TableColumn("Geb.", value: \.birthDate).width(80)
                TableColumn("G.", value: \.sex).width(24)
                TableColumn("Accession", value: \.accession).width(min: 60, ideal: 90)
                TableColumn("Prozedur", value: \.procedure)
                TableColumn("Mod.", value: \.modality).width(44)
                TableColumn("Termin", value: \.scheduled).width(115)
                TableColumn("Station", value: \.station).width(min: 60, ideal: 90)
            }
            .contextMenu(forSelectionType: WorklistRow.ID.self) { ids in
                if let r = rows.first(where: { $0.id == ids.first }) { Button("Details …") { detail = r } }
            } primaryAction: { ids in
                detail = rows.first { $0.id == ids.first }
            }
        }
        .padding()
        .sheet(item: $detail) { r in DatasetDumpView(dataset: r.dataset, title: "Worklist-Eintrag") }
        .onReceive(NotificationCenter.default.publisher(for: SnapshotHook.worklistRows)) { n in // screenshot hook
            rows = (n.object as? [DataSet] ?? []).map(WorklistRow.init(dataset:))
        }
    }

    private func query() {
        guard let node = state.selectedNode else { return }
        var q = DataSet()
        if patientName.contains(where: { !$0.isASCII }) { q.set(.specificCharacterSet, "ISO_IR 100") }
        q.set(.patientName, patientName); q.set(.patientID, patientID); q.set(.patientBirthDate, ""); q.set(.patientSex, "")
        q.set(.accessionNumber, accession); q.set(.referringPhysicianName, "")
        q.set(.requestedProcedureDescription, ""); q.set(.requestedProcedureID, ""); q.set(.studyInstanceUID, "")
        var sps = DataSet()
        sps.set(.modality, modality); sps.set(.scheduledStationAETitle, stationAE)
        sps.set(.scheduledProcedureStepStartDate, DicomDateInput.normalize(date, allowsRange: true)); sps.set(.scheduledProcedureStepStartTime, "")
        sps.set(.scheduledPerformingPhysicianName, ""); sps.set(.scheduledProcedureStepDescription, "")
        sps.set(.scheduledProcedureStepID, ""); sps.set(.scheduledStationName, "")
        q.setSequence(.scheduledProcedureStepSequence, [sps])
        rows = []
        running = true
        let settings = state.settings, log = state.logger("MWL")
        Task {
            do {
                try await DicomSCU.find(node: node, settings: settings, sopClass: SOPClass.modalityWorklistFind, query: q, log: log) { ds in
                    let row = WorklistRow(dataset: ds)
                    Task { @MainActor in rows.append(row) }
                }
            } catch {
                state.append("MWL", error.localizedDescription, error: true)
            }
            running = false
        }
    }
}
