import Foundation
import AppKit
import CryptoKit

struct GitHubRelease: Decodable, Identifiable {
    struct Asset: Decodable {
        let name: String
        let size: Int
        let browser_download_url: URL
    }
    let id: Int
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let published_at: Date?
    let assets: [Asset]

    var version: String { Updater.normalize(tag_name) }
    var title: String { (name?.isEmpty == false ? name! : tag_name) }

    /// The app archive: first .zip asset, preferring one named after the app.
    var zipAsset: Asset? {
        let zips = assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        return zips.first { $0.name.lowercased().contains("dicom") } ?? zips.first
    }

    func checksumAsset(for zip: Asset) -> Asset? {
        assets.first { $0.name == zip.name + ".sha256" } ?? assets.first { $0.name.lowercased() == "sha256sums.txt" }
    }
}

/// Checks GitHub releases, downloads the archive, verifies it and swaps the app bundle.
@MainActor
final class Updater: ObservableObject {
    nonisolated static let keys: Set<String> = ["updateRepository", "updateAutoCheck", "updateAutoDownload", "updatePrerelease",
                                    "updateSkippedVersion", "updateLastCheck"]

    @Published var repository = AppInfo.defaultRepository { didSet { save() } }
    @Published var autoCheck = true { didSet { save() } }
    @Published var autoDownload = false { didSet { save() } }
    @Published var includePrereleases = false { didSet { save() } }
    @Published var skippedVersion = "" { didSet { save() } }
    @Published var lastCheck: Date? { didSet { save() } }

    @Published var isChecking = false
    @Published var isInstalling = false
    @Published var statusText = ""
    @Published var available: GitHubRelease?
    @Published var showReleaseSheet = false
    @Published var downloadedApp: URL?
    private var relaunchScheduled = false

    var log: ((String, Bool) -> Void)?
    var notify: ((String, String) -> Void)?
    private let defaults = UserDefaults.standard
    private var loading = false
    private var timer: Task<Void, Never>?

    init() { reload() }

    func reload() {
        loading = true
        defer { loading = false }
        // Older builds stored the "OWNER/…" placeholder; replace it with the real default.
        let stored = defaults.string(forKey: "updateRepository")
        repository = stored.flatMap { $0.hasPrefix("OWNER/") ? nil : $0 } ?? AppInfo.defaultRepository
        autoCheck = defaults.object(forKey: "updateAutoCheck") as? Bool ?? true
        autoDownload = defaults.bool(forKey: "updateAutoDownload")
        includePrereleases = defaults.bool(forKey: "updatePrerelease")
        skippedVersion = defaults.string(forKey: "updateSkippedVersion") ?? ""
        lastCheck = defaults.object(forKey: "updateLastCheck") as? Date
    }

    private func save() {
        guard !loading else { return }
        defaults.set(repository, forKey: "updateRepository")
        defaults.set(autoCheck, forKey: "updateAutoCheck")
        defaults.set(autoDownload, forKey: "updateAutoDownload")
        defaults.set(includePrereleases, forKey: "updatePrerelease")
        defaults.set(skippedVersion, forKey: "updateSkippedVersion")
        defaults.set(lastCheck, forKey: "updateLastCheck")
    }

    var isRepositoryConfigured: Bool {
        let parts = repository.split(separator: "/")
        return parts.count == 2 && parts[0] != "OWNER" && !parts.contains { $0.isEmpty }
    }

    var repositoryURL: URL? { isRepositoryConfigured ? URL(string: "https://github.com/\(repository)") : nil }

    // MARK: Checking

    func startAutomaticChecks() {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                if self.autoCheck, self.isRepositoryConfigured,
                   Date().timeIntervalSince(self.lastCheck ?? .distantPast) > 23 * 3600 {
                    self.check(userInitiated: false)
                }
                try? await Task.sleep(nanoseconds: 3600 * 1_000_000_000)
            }
        }
    }

    func check(userInitiated: Bool) {
        guard !isChecking else { return }
        guard isRepositoryConfigured else {
            statusText = "Kein GitHub-Repository eingestellt (Über › Updates › GitHub-Repository)."
            if userInitiated { AppState.shared.open(.about) }
            return
        }
        isChecking = true
        statusText = "Suche nach Updates …"
        Task {
            defer { isChecking = false }
            do {
                let release = try await fetchNewestRelease()
                lastCheck = Date()
                guard let release, Self.compare(release.version, AppInfo.version) > 0 else {
                    available = nil
                    statusText = "\(AppInfo.name) \(AppInfo.version) ist aktuell."
                    if userInitiated { log?(statusText, false) }
                    return
                }
                if !userInitiated && release.version == skippedVersion {
                    statusText = "Version \(release.version) wird übersprungen."
                    return
                }
                available = release
                statusText = "Version \(release.version) ist verfügbar."
                log?("Update verfügbar: \(release.version) (installiert: \(AppInfo.version))", false)
                if autoDownload && !userInitiated { try? await download(release) }
                // Test hook for the mock-server update test: install without the confirmation click.
                if ProcessInfo.processInfo.environment["DICOMTESTTOOL_UPDATE_AUTOINSTALL"] == "1" { install(); return }
                showReleaseSheet = true
                if !userInitiated { notify?("Update verfügbar", "\(AppInfo.name) \(release.version) kann installiert werden.") }
                AppState.shared.open(AppState.shared.section)
            } catch {
                statusText = "Update-Prüfung fehlgeschlagen: \(error.localizedDescription)"
                log?(statusText, true)
            }
        }
    }

    private func fetchNewestRelease() async throws -> GitHubRelease? {
        let path = includePrereleases ? "releases?per_page=15" : "releases/latest"
        // DICOMTESTTOOL_UPDATE_API lets a local mock server stand in for GitHub during testing.
        let api = ProcessInfo.processInfo.environment["DICOMTESTTOOL_UPDATE_API"] ?? "https://api.github.com"
        guard let url = URL(string: "\(api)/repos/\(repository)/\(path)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("\(AppInfo.name.replacingOccurrences(of: " ", with: ""))/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw UpdateError.message("Repository oder Release nicht gefunden (\(repository))") }
        guard code == 200 else { throw UpdateError.message("GitHub antwortete mit HTTP \(code)") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if includePrereleases {
            let all = try decoder.decode([GitHubRelease].self, from: data).filter { !$0.draft }
            return all.max { Self.compare($0.version, $1.version) < 0 }
        }
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    func skip() {
        if let v = available?.version { skippedVersion = v }
        showReleaseSheet = false
    }

    // MARK: Installing

    enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    func install() {
        guard let release = available, !isInstalling, !relaunchScheduled else { return }
        isInstalling = true
        Task {
            defer { isInstalling = false }
            do {
                let app = try await download(release)
                try replaceAndRelaunch(with: app)
            } catch {
                statusText = "Installation fehlgeschlagen: \(error.localizedDescription)"
                log?(statusText, true)
            }
        }
    }

    @discardableResult
    private func download(_ release: GitHubRelease) async throws -> URL {
        if let d = downloadedApp, FileManager.default.fileExists(atPath: d.path) { return d }
        guard let asset = release.zipAsset else { throw UpdateError.message("Das Release enthält kein ZIP-Archiv der App") }
        statusText = "Lade \(asset.name) (\(ByteCountFormatter.string(fromByteCount: Int64(asset.size), countStyle: .file))) …"
        log?(statusText, false)
        let (tmp, response) = try await URLSession.shared.download(from: asset.browser_download_url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.message("Download fehlgeschlagen") }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("DICOMTestTool-Update-\(release.version)")
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: tmp, to: zip)

        if let sumAsset = release.checksumAsset(for: asset) {
            let (sumData, _) = try await URLSession.shared.data(from: sumAsset.browser_download_url)
            let text = String(decoding: sumData, as: UTF8.self)
            let expected = text.split(whereSeparator: \.isNewline)
                .first { $0.contains(asset.name) || !$0.contains(" ") }?
                .split(separator: " ").first.map(String.init)?.lowercased() ?? ""
            let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
            guard !expected.isEmpty, expected == actual else { throw UpdateError.message("SHA-256-Prüfsumme stimmt nicht überein") }
            log?("Prüfsumme bestätigt", false)
        } else {
            log?("Hinweis: Release enthält keine .sha256-Prüfsumme", false)
        }

        let extracted = work.appendingPathComponent("extracted")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
        guard let app = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { throw UpdateError.message("Keine .app im Archiv gefunden") }
        let newID = Bundle(url: app)?.bundleIdentifier
        guard newID == AppInfo.bundleID else { throw UpdateError.message("Bundle-ID im Update (\(newID ?? "?")) passt nicht") }
        try run("/usr/bin/codesign", ["--verify", "--deep", app.path])
        downloadedApp = app
        statusText = "Version \(release.version) heruntergeladen und geprüft."
        log?(statusText, false)
        return app
    }

    private func replaceAndRelaunch(with newApp: URL) throws {
        let current = Bundle.main.bundleURL
        guard current.pathExtension == "app" else { throw UpdateError.message("Die App läuft nicht als .app-Bundle") }
        guard FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            throw UpdateError.message("Keine Schreibrechte für \(current.deletingLastPathComponent().path)")
        }
        // A detached shell waits for this process to exit, swaps the bundle (rollback on failure) and relaunches.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.3; done
        rm -rf "$2.old"
        if mv "$2" "$2.old" && mv "$3" "$2"; then
          rm -rf "$2.old"
        else
          rm -rf "$2"; mv "$2.old" "$2"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$2" 2>/dev/null
        /usr/bin/open "$2"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "updater", String(ProcessInfo.processInfo.processIdentifier), current.path, newApp.path]
        try p.run()
        relaunchScheduled = true
        log?("Installiere Update und starte neu …", false)
        FileLogger.shared.write("Update", "Ersetze \(current.path)")
        // An open sheet blocks NSApp.terminate, so close it first; exit hard if termination is still refused.
        showReleaseSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) }
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw UpdateError.message("\((tool as NSString).lastPathComponent) fehlgeschlagen: \(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    // MARK: Versions

    nonisolated static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasPrefix("v") { s.removeFirst() }
        return s
    }

    /// Semantic version comparison; a pre-release suffix ranks below the plain version.
    nonisolated static func compare(_ a: String, _ b: String) -> Int {
        func split(_ v: String) -> ([Int], String) {
            let parts = normalize(v).split(separator: "-", maxSplits: 1)
            let nums = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
            return (nums, parts.count > 1 ? String(parts[1]) : "")
        }
        let (na, pa) = split(a), (nb, pb) = split(b)
        for i in 0..<max(na.count, nb.count) {
            let x = i < na.count ? na[i] : 0, y = i < nb.count ? nb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        if pa == pb { return 0 }
        if pa.isEmpty { return 1 }
        if pb.isEmpty { return -1 }
        return pa < pb ? -1 : 1
    }
}
