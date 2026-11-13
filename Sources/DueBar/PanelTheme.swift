import SwiftUI

/// Colours for the dropdown and settings. "system" follows the Mac.
/// DueBar's orange.
enum Brand {
    static let orange = Color(hex: 0xFF6B1F)
    static let gradient = LinearGradient(colors: [Color(hex: 0xFF8E42), Color(hex: 0xFF5A0F)], startPoint: .top, endPoint: .bottom)
}

struct PanelTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let isDark: Bool
    let background: Color
    let section: Color
    let header: Color
    let text: Color
    let secondaryText: Color
    /// Brand / action colour.
    let primary: Color
    /// The brand colour for small text: darker on light backgrounds, where the bright orange is too faint.
    let primaryText: Color
    /// Paid / success.
    let positive: Color
    /// Due soon.
    let warning: Color
    /// Overdue.
    let critical: Color
    let track: Color

    static let systemID = "system"

    static let dark = PanelTheme(
        id: "dark", name: "Dark", isDark: true,
        background: Color(hex: 0x1C1C1E), section: Color(hex: 0x2A2A2D),
        header: Color(hex: 0x9A9AA0), text: .white, secondaryText: Color(hex: 0xAEAEB4),
        primary: Brand.orange, primaryText: Brand.orange, positive: Color(hex: 0x30D158), warning: Color(hex: 0xFF9F0A), critical: Color(hex: 0xFF453A),
        track: Color.white.opacity(0.12)
    )

    static let light = PanelTheme(
        id: "light", name: "Light", isDark: false,
        background: Color(hex: 0xFAF7F4), section: .white,
        header: Color(hex: 0x6B6B70), text: Color(hex: 0x1D1D1F), secondaryText: Color(hex: 0x55555A),
        primary: Brand.orange, primaryText: Color(hex: 0xC24600), positive: Color(hex: 0x28A745), warning: Color(hex: 0xE08600), critical: Color(hex: 0xFF3B30),
        track: Color.black.opacity(0.09)
    )

    /// Light and Dark; "system" follows the Mac and is not a preset.
    static let presets: [PanelTheme] = [dark, light]

    static let validIDs: Set<String> = [systemID, dark.id, light.id]

    static func resolve(_ id: String, colorScheme: ColorScheme) -> PanelTheme {
        if let preset = presets.first(where: { $0.id == id }) { return preset }
        return colorScheme == .dark ? dark : light
    }
}

private struct PanelThemeKey: EnvironmentKey { static let defaultValue = PanelTheme.dark }

private struct ThemeAccentKey: EnvironmentKey { static let defaultValue = Brand.orange }

extension EnvironmentValues {
    /// Accent for custom-drawn controls (chips, avatar): the brand orange.
    var themeAccent: Color {
        get { self[ThemeAccentKey.self] }
        set { self[ThemeAccentKey.self] = newValue }
    }

    var panelTheme: PanelTheme {
        get { self[PanelThemeKey.self] }
        set { self[PanelThemeKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Themed windows

/// Applies the chosen theme (System, Light or Dark) to a window: its light/dark mode and the
/// brand accent for controls. Everything else is the native look.
struct ThemedWindowContent: ViewModifier {
    @AppStorage(SettingsKey.theme) private var themeID = PanelTheme.systemID

    func body(content: Content) -> some View {
        let forced: ColorScheme? = themeID == PanelTheme.light.id ? .light : (themeID == PanelTheme.dark.id ? .dark : nil)
        content
            .environment(\.themeAccent, Brand.orange)
            .tint(Brand.orange)
            .preferredColorScheme(forced)
    }
}

extension View {
    func themedWindow() -> some View { modifier(ThemedWindowContent()) }
}
