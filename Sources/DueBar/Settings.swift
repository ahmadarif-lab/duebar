import Foundation
import SwiftUI

enum SettingsKey {
    static let theme = "theme"
    static let language = "language"
    static let defaultCurrency = "defaultCurrency"
    static let defaultOffsets = "defaultOffsets"
    static let reminderMinute = "reminderMinute"
    static let notificationsOn = "notificationsOn"
    static let showInDock = "showInDock"
    static let syncEmail = "syncEmail"
    static let lastSync = "lastSync"
    static let autoCheckUpdates = "autoCheckUpdates"
}

extension UserDefaults {
    static func registerDueBarDefaults() {
        // The coloured presets (Midnight, Forest, Sunset) are gone; anyone who picked one follows the system.
        if let id = standard.string(forKey: SettingsKey.theme), !PanelTheme.validIDs.contains(id) {
            standard.set(PanelTheme.systemID, forKey: SettingsKey.theme)
        }
        standard.register(defaults: [
            SettingsKey.theme: PanelTheme.systemID,
            SettingsKey.language: "system",
            SettingsKey.defaultCurrency: Locale.current.currency?.identifier ?? "IDR",
            SettingsKey.defaultOffsets: "1,0",
            SettingsKey.reminderMinute: 9 * 60,
            SettingsKey.notificationsOn: true,
            SettingsKey.showInDock: false,
            SettingsKey.autoCheckUpdates: true,
        ])
    }

    /// The currency totals are shown in (and the default for new payments).
    var mainCurrency: String { string(forKey: SettingsKey.defaultCurrency) ?? "IDR" }

    var defaultOffsets: [Int] {
        (string(forKey: SettingsKey.defaultOffsets) ?? "1,0").split(separator: ",").compactMap { Int($0) }
    }
}

// MARK: - Localisation

/// English or Indonesian, picked inline: `tr("Mark as paid", "Tandai lunas")`.
/// Follows the Mac's language unless overridden in Settings.
func tr(_ en: String, _ id: String) -> String {
    switch UserDefaults.standard.string(forKey: SettingsKey.language) ?? "system" {
    case "en": return en
    case "id": return id
    default: return Locale.preferredLanguages.first?.hasPrefix("id") == true ? id : en
    }
}

var appLocale: Locale {
    switch UserDefaults.standard.string(forKey: SettingsKey.language) ?? "system" {
    case "en": return Locale(identifier: "en_US")
    case "id": return Locale(identifier: "id_ID")
    default: return Locale.current
    }
}
