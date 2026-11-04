import SwiftUI
import AppKit

/// Colour schemes, switchable at any time under Allgemein › Darstellung.
enum AppTheme: String, CaseIterable, Identifiable {
    case standard
    case clinicalDark

    static let storageKey = "appTheme"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard (macOS)"
        case .clinicalDark: return "Klinik Dunkel (Schwarz/Orange)"
        }
    }

    var summary: String {
        switch self {
        case .standard: return "Folgt dem Erscheinungsbild und der Akzentfarbe von macOS (hell oder dunkel)."
        case .clinicalDark: return "Dunkle Oberfläche in Schwarz und Grau mit orangefarbenen Akzenten und weißer Schrift, wie man es von Befundungs-Workstations kennt."
        }
    }

    /// nil = system accent colour.
    var accent: Color? {
        switch self {
        case .standard: return nil
        case .clinicalDark: return Color(red: 0.925, green: 0.400, blue: 0.008) // #EC6602
        }
    }

    var colorScheme: ColorScheme? { self == .clinicalDark ? .dark : nil }

    /// Window content background.
    var background: Color? { self == .clinicalDark ? Color(white: 0.09) : nil }
    /// Sidebar background.
    var sidebar: Color? { self == .clinicalDark ? Color(white: 0.05) : nil }
    /// Cards and panels.
    var panel: Color { self == .clinicalDark ? Color(white: 0.15) : Color(nsColor: .controlBackgroundColor) }
    var panelBorder: Color { self == .clinicalDark ? Color(white: 0.28) : Color.secondary.opacity(0.25) }

    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .standard
    }

    /// Also darkens menus, alerts, popovers and the menu bar dropdown.
    func applyToApp() {
        NSApp.appearance = self == .clinicalDark ? NSAppearance(named: .darkAqua) : nil
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.standard
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

/// Applies the chosen theme to a window's root view.
struct ThemedRoot: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.standard.rawValue

    func body(content: Content) -> some View {
        let theme = AppTheme(rawValue: themeRaw) ?? .standard
        content
            .environment(\.appTheme, theme)
            .tint(theme.accent)
            .accentColor(theme.accent)
            .preferredColorScheme(theme.colorScheme)
            .onAppear { theme.applyToApp() }
            .onChange(of: themeRaw) { _, new in (AppTheme(rawValue: new) ?? .standard).applyToApp() }
    }
}

extension View {
    func themedRoot() -> some View { modifier(ThemedRoot()) }

    /// Fills the area with the theme's background, if it defines one.
    @ViewBuilder func themeBackground(_ color: Color?) -> some View {
        if let color { self.scrollContentBackground(.hidden).background(color) } else { self }
    }
}
