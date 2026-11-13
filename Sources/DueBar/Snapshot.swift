import AppKit
import DueKit
import SwiftUI

/// `DUEBAR_SNAPSHOT_DIR=/path` renders the dropdown, editor and settings to
/// PNGs and quits: a way to look at the UI without driving the menu bar.
@MainActor
enum Snapshot {
    static func run(into dir: URL, context: AppContext) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let themes = (ProcessInfo.processInfo.environment["DUEBAR_SNAPSHOT_THEMES"] ?? "dark,light").split(separator: ",").map(String.init)
        for theme in themes {
            UserDefaults.standard.set(theme, forKey: SettingsKey.theme)
            let scheme: ColorScheme = theme == "light" ? .light : .dark
            write(Dropdown(close: {}).environmentObject(context.store).environmentObject(context.sync),
                  scheme: scheme, to: dir.appendingPathComponent("dropdown-\(theme).png"))
            write(Dropdown(close: {}, initialTab: .history).environmentObject(context.store).environmentObject(context.sync),
                  scheme: scheme, to: dir.appendingPathComponent("history-\(theme).png"))
        }
        let sample = context.store.ledger.allPayments.first { $0.name == "Listrik PLN" }
        write(PaymentForm(original: sample, onDone: {}).environmentObject(context.store), scheme: .light,
              to: dir.appendingPathComponent("form.png"))
        write(SettingsView().environmentObject(context.store).environmentObject(context.sync), scheme: .light,
              to: dir.appendingPathComponent("settings.png"))
        write(SettingsView(initialTab: .account).environmentObject(context.store).environmentObject(context.sync), scheme: .dark,
              to: dir.appendingPathComponent("settings-account.png"))
        NSApp.terminate(nil)
    }

    private static func write<V: View>(_ view: V, scheme: ColorScheme, to url: URL) {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme).fixedSize())
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
