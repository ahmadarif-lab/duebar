import SwiftUI

/// Colours for the dropdown and settings. "system" follows the Mac.
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
        header: Color(hex: 0x8E8E93), text: .white, secondaryText: Color(hex: 0xA1A1A6),
        primary: Color(hex: 0x2F7BF6), positive: Color(hex: 0x30D158), warning: Color(hex: 0xFF9F0A), critical: Color(hex: 0xFF453A),
        track: Color.white.opacity(0.12)
    )

    static let light = PanelTheme(
        id: "light", name: "Light", isDark: false,
        background: Color(hex: 0xECECEF), section: .white,
        header: Color(hex: 0x86868B), text: Color(hex: 0x1D1D1F), secondaryText: Color(hex: 0x6E6E73),
        primary: Color(hex: 0x0A7AFF), positive: Color(hex: 0x28A745), warning: Color(hex: 0xE08600), critical: Color(hex: 0xFF3B30),
        track: Color.black.opacity(0.09)
    )

    static let presets: [PanelTheme] = [
        dark, light,
        PanelTheme(
            id: "midnight", name: "Midnight", isDark: true,
            background: Color(hex: 0x0E1533), section: Color(hex: 0x19224A),
            header: Color(hex: 0x4A86FF), text: .white, secondaryText: Color(hex: 0x9AA6D0),
            primary: Color(hex: 0x2F6BFF), positive: Color(hex: 0x3DDC97), warning: Color(hex: 0xFFB020), critical: Color(hex: 0xFF5C7A),
            track: Color.white.opacity(0.12)
        ),
        PanelTheme(
            id: "forest", name: "Forest", isDark: true,
            background: Color(hex: 0x0E1C16), section: Color(hex: 0x172E24),
            header: Color(hex: 0x5BD69A), text: .white, secondaryText: Color(hex: 0x93B8A5),
            primary: Color(hex: 0x34C759), positive: Color(hex: 0x7CE3A7), warning: Color(hex: 0xFFD60A), critical: Color(hex: 0xFF6B5E),
            track: Color.white.opacity(0.12)
        ),
        PanelTheme(
            id: "sunset", name: "Sunset", isDark: true,
            background: Color(hex: 0x200F1A), section: Color(hex: 0x331A2A),
            header: Color(hex: 0xFF8A65), text: .white, secondaryText: Color(hex: 0xC99AAE),
            primary: Color(hex: 0xFF9F0A), positive: Color(hex: 0x5BD69A), warning: Color(hex: 0xFFD60A), critical: Color(hex: 0xFF375F),
            track: Color.white.opacity(0.12)
        ),
    ]

    static func resolve(_ id: String, colorScheme: ColorScheme) -> PanelTheme {
        if let preset = presets.first(where: { $0.id == id }) { return preset }
        return colorScheme == .dark ? dark : light
    }
}

private struct PanelThemeKey: EnvironmentKey { static let defaultValue = PanelTheme.dark }

extension EnvironmentValues {
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
