import SwiftUI

/// DICOM date (DA) input: typed directly (TTMMJJJJ, TT.MM.JJJJ, JJJJMMTT, ranges with "-") or picked
/// from a calendar popover that opens when the field is clicked. The binding always holds DICOM
/// format; the field shows the German format.
struct DateField: View {
    let label: String
    @Binding var text: String
    var allowsRange = false
    var width: CGFloat = 150

    @FocusState private var focused: Bool
    @State private var showCalendar = false
    /// The popover takes key focus; when it closes the field regains focus and must not reopen it.
    @State private var suppressUntil = Date.distantPast
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField(allowsRange ? "TTMMJJJJ[-TTMMJJJJ]" : "TTMMJJJJ", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { normalize() }
                Button { showCalendar.toggle() } label: { Image(systemName: "calendar") }
                    .buttonStyle(.borderless)
                    .help("Kalender öffnen")
            }
            .frame(width: width + 24)
            .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                DateFieldCalendar(text: $text, allowsRange: allowsRange) { showCalendar = false }
            }
        }
        .help(DicomDateInput.describe(text))
        .onAppear { input = DicomDateInput.display(text) }
        .onChange(of: input) { _, typed in
            let n = DicomDateInput.normalize(typed, allowsRange: allowsRange)
            if n != text { text = n }
        }
        .onChange(of: text) { _, value in
            // Changed from outside (calendar, "Heute", reset): show it formatted.
            if DicomDateInput.normalize(input, allowsRange: allowsRange) != value { input = DicomDateInput.display(value) }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                if Date() > suppressUntil { showCalendar = true }
            } else {
                normalize()
            }
        }
        .onChange(of: showCalendar) { _, open in
            if !open { suppressUntil = Date().addingTimeInterval(0.8); normalize() }
        }
    }

    private func normalize() {
        let n = DicomDateInput.normalize(input, allowsRange: allowsRange)
        if n != text { text = n }
        input = DicomDateInput.display(n)
    }
}

private struct DateFieldCalendar: View {
    @Binding var text: String
    let allowsRange: Bool
    let close: () -> Void
    @State private var range = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if allowsRange {
                Picker("", selection: $range) {
                    Text("Einzelner Tag").tag(false)
                    Text("Zeitraum").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
            if range {
                HStack(alignment: .top, spacing: 16) {
                    calendar("Von", date: bound(\.from))
                    calendar("Bis", date: bound(\.to))
                }
            } else {
                calendar(nil, date: bound(\.from, single: true))
            }
            HStack {
                Button("Heute") { set(Date(), Date()) }
                Button("Gestern") { let d = Date().addingTimeInterval(-86400); set(d, d) }
                if allowsRange {
                    Button("Letzte 7 Tage") { range = true; set(Date().addingTimeInterval(-6 * 86400), Date()) }
                    Button("Letzte 30 Tage") { range = true; set(Date().addingTimeInterval(-29 * 86400), Date()) }
                }
                Spacer()
                Button("Leeren") { text = ""; close() }
                Button("Fertig") { close() }.keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
            Text(allowsRange
                 ? "Auch direkt eintippen: TTMMJJJJ oder TT.MM.JJJJ, Zeitraum mit „-“ (offen: „01012026-“). Leer = beliebig."
                 : "Auch direkt eintippen: TTMMJJJJ oder TT.MM.JJJJ. Leer = beliebig.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: range ? 520 : 300)
        .onAppear { range = allowsRange && DicomDateInput.parse(text).isRange }
    }

    private func calendar(_ title: String?, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title { Text(title).font(.caption.bold()).foregroundStyle(.secondary) }
            // The field style allows jumping years quickly (birth dates); the grid is for clicking.
            DatePicker("", selection: date, displayedComponents: .date).datePickerStyle(.field).labelsHidden()
            DatePicker("", selection: date, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
        }
    }

    private func bound(_ part: KeyPath<DicomDateInput.Parsed, Date?>, single: Bool = false) -> Binding<Date> {
        Binding(
            get: { DicomDateInput.parse(text)[keyPath: part] ?? Date() },
            set: { d in
                let p = DicomDateInput.parse(text)
                if single || !range {
                    set(d, d)
                } else if part == \.from {
                    set(d, max(d, p.to ?? d))
                } else {
                    set(min(d, p.from ?? d), d)
                }
            })
    }

    private func set(_ from: Date, _ to: Date) {
        let a = dicomDate(from), b = dicomDate(to)
        text = (range && a != b) ? "\(a)-\(b)" : a
    }
}

/// Parsing and normalising user date input into DICOM DA (single date or range).
enum DicomDateInput {
    struct Parsed {
        var from: Date?
        var to: Date?
        var isRange = false
    }

    private static let dicom: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd"; return f
    }()

    /// Accepts TTMMJJJJ, JJJJMMTT, TT.MM.JJJJ, T.M.JJ, JJJJ-MM-TT; returns JJJJMMTT or nil.
    static func date(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.count == 8, s.allSatisfy(\.isNumber) {
            let c = Array(s).map { Int(String($0))! }
            func num(_ r: Range<Int>) -> Int { r.reduce(0) { $0 * 10 + c[$1] } }
            // JJJJMMTT if it is a plausible date, otherwise TTMMJJJJ (e.g. 04111970).
            if (1800...2199).contains(num(0..<4)), let d = build(num(0..<4), num(4..<6), num(6..<8)) { return d }
            if (1800...2199).contains(num(4..<8)), let d = build(num(4..<8), num(2..<4), num(0..<2)) { return d }
            return nil
        }
        let iso = s.split(separator: "-", omittingEmptySubsequences: false)
        if iso.count == 3, iso[0].count == 4, let y = Int(iso[0]), let m = Int(iso[1]), let d = Int(iso[2]) { return build(y, m, d) }
        let parts = s.split(separator: ".", omittingEmptySubsequences: true)
        if parts.count == 3, let d = Int(parts[0]), let m = Int(parts[1]), var y = Int(parts[2]) {
            if parts[2].count == 2 { y += y > 50 ? 1900 : 2000 }
            return build(y, m, d)
        }
        return nil
    }

    private static func build(_ y: Int, _ m: Int, _ d: Int) -> String? {
        let s = String(format: "%04d%02d%02d", y, m, d)
        guard let d = dicom.date(from: s), dicom.string(from: d) == s else { return nil } // rejects 31.02.
        return s
    }

    /// Splits "A-B", "A - B", "A-" and "-B"; ISO dates (with dashes) are only accepted as single values.
    private static func split(_ s: String) -> (String, String)? {
        if let r = s.range(of: " - ") { return (String(s[..<r.lowerBound]), String(s[r.upperBound...])) }
        let dashes = s.filter { $0 == "-" }.count
        guard dashes == 1, let i = s.firstIndex(of: "-") else { return nil }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }

    static func normalize(_ raw: String, allowsRange: Bool) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return "" }
        if let d = date(s) { return d }
        if allowsRange, let (a, b) = split(s) {
            let na = a.trimmingCharacters(in: .whitespaces).isEmpty ? "" : date(a)
            let nb = b.trimmingCharacters(in: .whitespaces).isEmpty ? "" : date(b)
            if let na, let nb, !(na.isEmpty && nb.isEmpty) { return "\(na)-\(nb)" }
        }
        return s // unknown input (e.g. wildcards) is passed on unchanged
    }

    static func parse(_ raw: String) -> Parsed {
        let s = normalize(raw, allowsRange: true)
        if let (a, b) = split(s) {
            return Parsed(from: dicom.date(from: a), to: dicom.date(from: b), isRange: true)
        }
        let d = dicom.date(from: s)
        return Parsed(from: d, to: d)
    }

    /// DICOM value → what the field shows: "04.11.2026" or "01.11.2026 - 04.11.2026".
    static func display(_ value: String) -> String {
        if value.count == 8, date(value) == value { return formatDA(value) }
        if let (a, b) = split(value), a.isEmpty || date(a) == a, b.isEmpty || date(b) == b {
            return "\(a.isEmpty ? "" : formatDA(a)) - \(b.isEmpty ? "" : formatDA(b))".trimmingCharacters(in: .whitespaces)
        }
        return value
    }

    static func describe(_ raw: String) -> String {
        let s = normalize(raw, allowsRange: true)
        if s.isEmpty { return "Kein Datum: alle Einträge" }
        if let (a, b) = split(s) {
            return "Zeitraum \(a.isEmpty ? "…" : formatDA(a)) bis \(b.isEmpty ? "…" : formatDA(b))"
        }
        return s.count == 8 ? formatDA(s) : s
    }
}
