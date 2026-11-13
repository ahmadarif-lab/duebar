import AppKit
import Combine
import DueKit

/// Everything the windows and views share.
@MainActor
final class AppContext {
    static var shared: AppContext!
    let store: Store
    let sync: SyncService
    let notifier: Notifier

    init() {
        store = Store()
        sync = SyncService(store: store)
        notifier = Notifier(store: store)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var midnightTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !anotherCopyIsRunning() else { NSApp.terminate(nil); return }
        UserDefaults.registerDueBarDefaults()

        let context = AppContext()
        AppContext.shared = context
        let store = context.store

        store.onChange = { [weak context] in
            context?.sync.localChanged()
            context?.notifier.reschedule()
        }
        store.onChangeAfterRemote = { [weak context] in context?.notifier.reschedule() }

        if let dir = ProcessInfo.processInfo.environment["DUEBAR_SNAPSHOT_DIR"], !dir.isEmpty {
            Snapshot.run(into: URL(fileURLWithPath: dir), context: context)
            return
        }
        statusBar = StatusBarController(context: context)
        NSApp.mainMenu = Self.mainMenu()

        _ = Updater.shared
        context.notifier.requestAuthorization()
        context.notifier.reschedule(force: true)
        scheduleDayRollover()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dayRolledOver() }
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dayRolledOver() }
        }
        NotificationCenter.default.addObserver(forName: .openDueBarPanel, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusBar?.openPanel() }
        }

        // Opened by hand rather than at login: say hello with the dropdown.
        if !LoginItem.launchedAtLogin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.statusBar?.openPanel() }
        }
        LoginItem.enableOnFirstLaunch()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBar?.openPanel()
        return false
    }

    private func dayRolledOver() {
        AppContext.shared.store.refreshDay()
        AppContext.shared.notifier.reschedule()
    }

    /// Midnight rollover as a safety net next to the system day-change notification.
    private func scheduleDayRollover() {
        midnightTimer?.invalidate()
        midnightTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            MainActor.assumeIsolated { AppContext.shared.store.refreshDay() }
        }
    }

    private func anotherCopyIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let me = NSRunningApplication.current
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me.processIdentifier }
            .contains { other in
                guard let o = other.launchDate, let m = me.launchDate else { return false }
                return o < m
            }
    }

    /// Only visible while a window makes DueBar a regular app: enough for ⌘W, ⌘Q, ⌘C/⌘V in fields.
    private static func mainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: tr("Quit DueBar", "Keluar dari DueBar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: tr("Edit", "Edit"))
        edit.addItem(NSMenuItem(title: tr("Undo", "Urungkan"), action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: tr("Cut", "Potong"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: tr("Copy", "Salin"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: tr("Paste", "Tempel"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: tr("Select All", "Pilih Semua"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: tr("Window", "Jendela"))
        window.addItem(NSMenuItem(title: tr("Close", "Tutup"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        window.addItem(NSMenuItem(title: tr("Minimize", "Minimalkan"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }
}
