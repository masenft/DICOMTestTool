import AppKit
import SwiftUI

/// Test hook for website screenshots: renders the main window into PNG files without needing
/// screen-recording permission. Only active when DICOMTESTTOOL_SNAPSHOT=<output folder> is set.
/// Optional DICOMTESTTOOL_SNAPSHOT_FILE=<DICOM file> is opened in the viewer.
@MainActor
enum SnapshotHook {
    static func runIfRequested(_ state: AppState) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["DICOMTESTTOOL_SNAPSHOT"] else { return }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        let file = env["DICOMTESTTOOL_SNAPSHOT_FILE"].map { URL(fileURLWithPath: $0) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            UserDefaults.standard.set(AppTheme.standard.rawValue, forKey: AppTheme.storageKey)
            AppTheme.standard.applyToApp()
            NSApp.appearance = NSAppearance(named: .aqua)
            mainWindow?.appearance = NSAppearance(named: .aqua)
            state.notificationsEnabled = false
            if let w = mainWindow { w.setContentSize(NSSize(width: 1120, height: 700)); w.center() }
            state.log.removeAll()
            state.watchNodeIDs = Set(state.nodes.map(\.id))
            state.watchInterval = 10
            state.section = .watchdog
            state.startWatchdog()
            try? await Task.sleep(for: .seconds(6))
            state.log.removeAll { $0.text.contains("Mitteilung") }
            try? await Task.sleep(for: .seconds(1))
            capture(out.appendingPathComponent("watchdog.png"))

            state.stopWatchdog()
            UserDefaults.standard.set(AppTheme.clinicalDark.rawValue, forKey: AppTheme.storageKey)
            AppTheme.clinicalDark.applyToApp()
            mainWindow?.appearance = NSAppearance(named: .darkAqua)
            state.section = .viewer
            try? await Task.sleep(for: .seconds(1))
            if let file { state.viewerURL = file }
            try? await Task.sleep(for: .seconds(3))
            capture(out.appendingPathComponent("viewer.png"))
            NSApp.terminate(nil)
        }
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
