import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DicomCore

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var updater: Updater
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { state.section }, set: { if let s = $0 { state.section = s } })) {
                Section("Werkzeuge") {
                    ForEach(AppSection.tools) { s in sidebarLabel(s) }
                }
                Section("App") {
                    ForEach(AppSection.app) { s in sidebarLabel(s) }
                }
            }
            .themeBackground(theme.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            Group {
                if state.section.showsLog {
                    VSplitView {
                        toolView.frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                        LogView().frame(minHeight: 110, idealHeight: 170, maxHeight: 400)
                    }
                } else {
                    ScrollView { toolView.frame(maxWidth: .infinity, alignment: .topLeading) }
                }
            }
            .background(theme.background ?? Color.clear)
            .navigationTitle(state.section.title)
        }
        .sheet(isPresented: $updater.showReleaseSheet) { ReleaseNotesSheet() }
        .onAppear {
            // First launch: show the guided tour once.
            if !UserDefaults.standard.bool(forKey: TourPage.shownKey) { openTour(openWindow) }
        }
    }

    @ViewBuilder private func sidebarLabel(_ s: AppSection) -> some View {
        HStack {
            Label(s.title, systemImage: s.icon)
            Spacer()
            if s == .scp && state.scpRunning { Circle().fill(.green).frame(width: 7, height: 7) }
            if s == .watchdog && state.watchRunning { Circle().fill(state.watchHasFailure ? .red : .green).frame(width: 7, height: 7) }
            if s == .about && updater.available != nil { Text("neu").font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal, 5).background(Capsule().fill(.blue)) }
        }
        .tag(s)
    }

    @ViewBuilder private var toolView: some View {
        switch state.section {
        case .nodes: NodesView()
        case .echo: EchoView()
        case .store: StoreView()
        case .find: FindView()
        case .worklist: WorklistView()
        case .scp: SCPView()
        case .watchdog: WatchdogView()
        case .viewer: ViewerView()
        case .general: GeneralView()
        case .about: AboutView()
        }
    }
}

// MARK: - Shared components

struct NodePicker: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack {
            Picker("Ziel", selection: $state.selectedNodeID) {
                ForEach(state.nodes) { n in
                    Text("\(n.name)  –  \(n.summary)").tag(Optional(n.id))
                }
            }
            .frame(maxWidth: 480)
            Button {
                state.section = .nodes
            } label: { Image(systemName: "pencil") }
            .help("Knoten bearbeiten")
            Spacer()
            Text("Calling AE: \(state.callingAE)").foregroundStyle(.secondary).font(.callout)
        }
    }
}

struct ToolHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    var width: CGFloat = 180
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: $text).textFieldStyle(.roundedBorder).frame(width: width)
        }
    }
}

struct LogView: View {
    @EnvironmentObject var state: AppState
    private static let tf: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Protokoll").font(.headline)
                Spacer()
                Button("Kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.logText(), forType: .string)
                }
                Button { exportLog() } label: { Label("Exportieren …", systemImage: "square.and.arrow.up") }
                    .disabled(state.log.isEmpty)
                Button("Leeren") { state.log.removeAll() }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(state.log) { e in
                            Text("\(Self.tf.string(from: e.date))  [\(e.source)]  \(e.text)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(e.isError ? Color.red : Color.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(e.id)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                }
                .onChange(of: state.log.count) { _, _ in
                    if let last = state.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func exportLog() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.plainText]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm"
        p.nameFieldStringValue = "DICOM-Protokoll_\(f.string(from: Date())).txt"
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            try state.logText().write(to: url, atomically: true, encoding: .utf8)
            state.append("App", "Protokoll exportiert: \(url.path)")
        } catch {
            state.append("App", "Export fehlgeschlagen: \(error.localizedDescription)", error: true)
        }
    }
}

struct DatasetDumpView: View {
    let dataset: DataSet
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Schließen") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            TagTable(rows: TagRow.flatten(dataset))
        }
        .padding()
        .frame(minWidth: 800, minHeight: 500)
    }
}

struct TagRow: Identifiable {
    let id = UUID()
    let depth: Int
    let tag: String
    let vr: String
    let name: String
    let length: String
    let value: String

    static func flatten(_ ds: DataSet, depth: Int = 0) -> [TagRow] {
        var rows: [TagRow] = []
        let indent = String(repeating: "    ", count: depth)
        for el in ds.sorted {
            let len = el.items != nil ? "" : (el.fragments != nil ? "undef." : "\(el.data.count)")
            rows.append(TagRow(depth: depth, tag: indent + el.tag.description, vr: el.vr.rawValue,
                               name: el.tag.name, length: len, value: el.displayValue))
            if let items = el.items {
                for (i, item) in items.enumerated() {
                    rows.append(TagRow(depth: depth + 1, tag: indent + "  > Item \(i + 1)", vr: "", name: "", length: "", value: ""))
                    rows += flatten(item, depth: depth + 1)
                }
            }
        }
        return rows
    }
}

struct TagTable: View {
    let rows: [TagRow]
    var body: some View {
        Table(rows) {
            TableColumn("Tag") { Text($0.tag).font(.system(.body, design: .monospaced)) }.width(min: 120, ideal: 150)
            TableColumn("VR") { Text($0.vr).font(.system(.body, design: .monospaced)) }.width(34)
            TableColumn("Name", value: \.name).width(min: 140, ideal: 230)
            TableColumn("Länge", value: \.length).width(55)
            TableColumn("Wert") { Text($0.value).textSelection(.enabled) }
        }
    }
}

func chooseFiles(folders: Bool = true, multiple: Bool = true) -> [URL] {
    let p = NSOpenPanel()
    p.canChooseFiles = true
    p.canChooseDirectories = folders
    p.allowsMultipleSelection = multiple
    return p.runModal() == .OK ? p.urls : []
}

func chooseFolder() -> URL? {
    let p = NSOpenPanel()
    p.canChooseFiles = false
    p.canChooseDirectories = true
    p.canCreateDirectories = true
    return p.runModal() == .OK ? p.url : nil
}

func dicomDate(_ d: Date = Date()) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd"
    return f.string(from: d)
}

/// "MUSTERMANN^MAX" → "MUSTERMANN, MAX"; DA "20261103" → "03.11.2026"
func formatPN(_ s: String?) -> String {
    guard let s, !s.isEmpty else { return "" }
    return s.split(separator: "=").first.map { $0.split(separator: "^", omittingEmptySubsequences: false).filter { !$0.isEmpty }.joined(separator: ", ") } ?? s
}

func formatDA(_ s: String?) -> String {
    guard let s, s.count == 8 else { return s ?? "" }
    let c = Array(s)
    return "\(String(c[6...7])).\(String(c[4...5])).\(String(c[0...3]))"
}

func formatTM(_ s: String?) -> String {
    guard let s, s.count >= 4 else { return s ?? "" }
    let c = Array(s)
    return "\(String(c[0...1])):\(String(c[2...3]))"
}
