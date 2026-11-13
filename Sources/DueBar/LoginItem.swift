import AppKit
import Foundation
import ServiceManagement

/// Start-at-login via SMAppService (macOS 13+), same approach as StatBar.
enum LoginItem {
    private static let autoEnabledKey = "loginItemAutoEnabled"

    @MainActor
    static var launchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event?.eventID == kAEOpenApplication,
           event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        return ProcessInfo.processInfo.systemUptime < 180
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    private static var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Error? {
        do {
            if enabled {
                guard isBundledApp else { return nil }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch { return error }
    }

    /// On the very first run only, so a user who switches it off keeps it off.
    static func enableOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: autoEnabledKey) else { return }
        defaults.set(true, forKey: autoEnabledKey)
        setEnabled(true)
    }
}
