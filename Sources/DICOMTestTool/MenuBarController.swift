import SwiftUI
import AppKit
import Combine

/// Menu bar icon with dropdown, built with AppKit (NSStatusItem). SwiftUI's MenuBarExtra only
/// highlighted the icon without opening the menu while another app was active.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var observation: AnyCancellable?
    private var state: AppState { AppState.shared }

    /// Shows or hides the icon (Allgemein › Darstellung).
    func setVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            item.menu = menu
            statusItem = item
            updateIcon()
            observation = state.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.updateIcon() }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            observation = nil
        }
    }

    private func updateIcon() {
        let name = state.watchHasFailure ? "exclamationmark.triangle.fill" : "waveform.path.ecg.rectangle"
        guard let button = statusItem?.button, button.toolTip != name else { return }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: AppInfo.name)
        image?.isTemplate = true
        button.image = image
        button.toolTip = name == "exclamationmark.triangle.fill" ? "\(AppInfo.name) – Watchdog meldet einen Ausfall" : AppInfo.name
    }

    // MARK: Menu (rebuilt every time it opens, so it always shows the current state)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "\(AppInfo.name) \(AppInfo.version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let scp = "\(state.scpAE):\(state.scpPort)"
        if state.scpRunning {
            add(menu, "Storage SCP stoppen (\(scp))") { $0.state.stopSCP() }
        } else {
            add(menu, "Storage SCP starten (\(scp))") { $0.state.startSCP() }
        }
        if state.watchRunning {
            add(menu, "Watchdog stoppen – \(state.watchSummary)") { $0.state.stopWatchdog() }
        } else {
            add(menu, "Watchdog starten") { c in
                if c.state.watchNodeIDs.isEmpty { c.show(.watchdog) } else { c.state.startWatchdog() }
            }
        }
        let echo = NSMenuItem(title: "Echo senden an", action: nil, keyEquivalent: "")
        let echoMenu = NSMenu()
        if state.nodes.isEmpty {
            let none = NSMenuItem(title: "Keine Knoten angelegt", action: nil, keyEquivalent: "")
            none.isEnabled = false
            echoMenu.addItem(none)
        }
        for node in state.nodes {
            add(echoMenu, "\(node.name) – \(node.summary)") { $0.state.quickEcho(node) }
        }
        echo.submenu = echoMenu
        menu.addItem(echo)
        menu.addItem(.separator())

        for s in AppSection.tools where s != .nodes {
            add(menu, s.title, symbol: s.icon) { $0.show(s) }
        }
        menu.addItem(.separator())

        add(menu, "Knoten verwalten …", symbol: AppSection.nodes.icon) { $0.show(.nodes) }
        add(menu, "Einstellungen …", symbol: "gearshape") { $0.show(.general) }
        add(menu, "Einführung …", symbol: "sparkles") { _ in WindowOpener.open(AppInfo.tourWindowID) }
        add(menu, state.updater.available != nil ? "Update installieren …" : "Nach Updates suchen …", symbol: "arrow.down.circle") { c in
            c.show(.about)
            if c.state.updater.available != nil { c.state.updater.showReleaseSheet = true } else { c.state.updater.check(userInitiated: true) }
        }
        add(menu, "Über \(AppInfo.name)", symbol: "info.circle") { $0.show(.about) }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "\(AppInfo.name) beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func show(_ s: AppSection) {
        state.section = s
        WindowOpener.open(AppInfo.mainWindowID)
    }

    private func add(_ menu: NSMenu, _ title: String, symbol: String? = nil, _ action: @escaping (MenuBarController) -> Void) {
        let item = ClosureMenuItem(title: title, action: #selector(ClosureMenuItem.fire), keyEquivalent: "")
        item.target = item
        item.handler = { [weak self] in if let self { action(self) } }
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(item)
    }
}

private final class ClosureMenuItem: NSMenuItem {
    var handler: (() -> Void)?
    @objc func fire() { handler?() }
}

/// Opens SwiftUI windows from AppKit code. The OpenWindowAction is taken from the first SwiftUI
/// view that appears and stays valid after its window is closed.
@MainActor
enum WindowOpener {
    static var action: OpenWindowAction?

    static func open(_ id: String) {
        if let action {
            presentWindow(id: id, using: action)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(id) == true }?.makeKeyAndOrderFront(nil)
        }
    }
}
