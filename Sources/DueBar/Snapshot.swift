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
            write(Dropdown(close: {}, initialPage: .all).environmentObject(context.store).environmentObject(context.sync),
                  scheme: scheme, to: dir.appendingPathComponent("all-\(theme).png"))
            write(Dropdown(close: {}, initialPage: .history).environmentObject(context.store).environmentObject(context.sync),
                  scheme: scheme, to: dir.appendingPathComponent("history-\(theme).png"))
            let sample = context.store.ledger.allPayments.first { $0.name == "Listrik PLN" }
            write(PaymentForm(original: sample, onDone: {}).environmentObject(context.store).themedWindow(), scheme: scheme, to: dir.appendingPathComponent("form-\(theme).png"))
            for (name, tab) in [("general", SettingsTab.general), ("account", .account)] {
                write(SettingsView(initialTab: tab).environmentObject(context.store).environmentObject(context.sync).themedWindow(), scheme: scheme,
                      to: dir.appendingPathComponent("settings-\(name)-\(theme).png"))
            }
        }
        let strip = HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { dark in
                HStack(spacing: 14) {
                    ForEach([0, 2, 7, 12], id: \.self) { n in
                        if let image = StatusBarController.icon(badge: n) {
                            Image(nsImage: image).resizable().interpolation(.high).frame(width: image.size.width * 3, height: image.size.height * 3)
                        }
                    }
                }
                .padding(18).background(dark ? Color(hex: 0x2B2B2E) : Color(hex: 0xE9E3F2))
            }
        }
        write(strip, scheme: .dark, to: dir.appendingPathComponent("menubar-icons.png"))

        // The real Settings window (its frame, not just the view), on the Reminders tab.
        Windows.showSettings(tab: .reminders)
        if let window = NSApp.windows.first(where: { $0.title == tr("DueBar Settings", "Pengaturan DueBar") }), let view = window.contentView {
            view.layoutSubtreeIfNeeded()
            print("settings window frame \(window.frame.size) content \(view.frame.size)")
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("settings-window.png"))
            }
        }
        // The real editor window.
        Windows.showEditor(payment: context.store.ledger.allPayments.first { $0.name == "Listrik PLN" })
        if let window = NSApp.windows.first(where: { $0.title == tr("Edit Payment", "Ubah Pembayaran") }), let view = window.contentView {
            view.layoutSubtreeIfNeeded()
            print("editor window frame \(window.frame.size) content \(view.frame.size)")
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("editor-window.png"))
            }
        }
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
