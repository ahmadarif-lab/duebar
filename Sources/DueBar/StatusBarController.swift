import AppKit
import Combine
import DueKit
import SwiftUI

/// One status item showing the next payment (or a count / just an icon),
/// and a dropdown panel hanging under it. Plain NSStatusItem rather than a
/// SwiftUI MenuBarExtra, as in StatBar, for control over width and focus.
@MainActor
final class StatusBarController: NSObject {
    private let context: AppContext
    private let statusItem: NSStatusItem
    private var subscriptions: Set<AnyCancellable> = []
    private var panel: DropdownPanel?
    private var outsideClickMonitor: Any?
    private var lastDismissal: Date?

    init(context: AppContext) {
        self.context = context
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "DueBar.main"
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.imagePosition = .imageLeading
        }
        context.store.objectWillChange
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        refresh()
    }

    // MARK: Title

    private func refresh() {
        guard let button = statusItem.button else { return }
        let agenda = context.store.agenda
        let style = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: SettingsKey.menuBarStyle) ?? "") ?? .next
        let hasOverdue = !agenda.overdue.isEmpty
        let symbol = hasOverdue ? "exclamationmark.circle.fill" : (agenda.today.isEmpty ? "creditcard" : "bell.badge.fill")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "DueBar")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = hasOverdue ? .systemRed : nil

        var title = ""
        switch style {
        case .icon: break
        case .count:
            if agenda.attentionCount > 0 { title = " \(agenda.attentionCount)" }
        case .next:
            if let next = agenda.next, Self.isNear(next) {
                let name = next.payment.name.count > 16 ? String(next.payment.name.prefix(15)) + "…" : next.payment.name
                title = " \(name) · \(Self.short(next.status))"
            }
        }
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.menuBarFont(ofSize: 0),
        ])
        button.setAccessibilityLabel(tr("DueBar, \(agenda.attentionCount) payments need attention", "DueBar, \(agenda.attentionCount) pembayaran perlu perhatian"))
    }

    private static func isNear(_ item: AgendaItem) -> Bool {
        if case .upcoming(let d) = item.status { return d <= 7 }
        return true
    }

    private static func short(_ status: DueStatus) -> String {
        switch status {
        case .overdue(let d): return tr("\(d)d late", "telat \(d)h")
        case .today: return tr("today", "hari ini")
        case .upcoming(let d): return d == 1 ? tr("tomorrow", "besok") : tr("in \(d)d", "\(d)h lagi")
        }
    }

    // MARK: Clicks

    @objc private func clicked(_ button: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            showContextMenu(from: button)
            return
        }
        if panel != nil { close(); return }
        // The click that closed the panel (outside click) arrives before this one.
        if let lastDismissal, Date().timeIntervalSince(lastDismissal) < 0.3 { return }
        openPanel()
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        close()
        let menu = NSMenu()
        let add = NSMenuItem(title: tr("Add payment…", "Tambah pembayaran…"), action: #selector(addPayment), keyEquivalent: "n")
        add.target = self
        menu.addItem(add)
        if context.sync.isSignedIn {
            let sync = NSMenuItem(title: tr("Sync now", "Sinkronkan sekarang"), action: #selector(syncNow), keyEquivalent: "")
            sync.target = self
            menu.addItem(sync)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: tr("Settings…", "Pengaturan…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: tr("Quit DueBar", "Keluar dari DueBar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func addPayment() { Windows.showEditor(payment: nil) }
    @objc private func openSettings() { Windows.showSettings() }
    @objc private func syncNow() { Task { await context.sync.syncNow() } }

    // MARK: Dropdown

    func openPanel() {
        close()
        guard let button = statusItem.button, let window = button.window else { return }
        let root = Dropdown(close: { [weak self] in self?.close() })
            .environmentObject(context.store)
            .environmentObject(context.sync)
        let panel = DropdownPanel(
            content: root,
            anchor: NSPoint(x: window.frame.midX, y: window.frame.minY - 3),
            screen: window.screen
        )
        panel.onResignKey = { [weak self] in self?.close() }
        panel.onEscape = { [weak self] in self?.close() }
        panel.show()
        self.panel = panel
        button.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        Task { await context.sync.syncNow() }
    }

    func close() {
        guard panel != nil else { return }
        lastDismissal = Date()
        statusItem.button?.highlight(false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        panel?.onResignKey = nil
        panel?.dismiss()
        panel = nil
    }
}

/// Borderless panel hanging under the menu bar. It takes key status (for
/// Escape and text entry) without activating DueBar.
final class DropdownPanel: NSPanel {
    var onResignKey: (() -> Void)?
    var onEscape: (() -> Void)?
    private let anchor: NSPoint
    private let visibleFrame: NSRect

    init<Content: View>(content: Content, anchor: NSPoint, screen: NSScreen?) {
        self.anchor = anchor
        visibleFrame = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false

        var resize: (CGSize) -> Void = { _ in }
        let hosting = NSHostingView(rootView:
            content
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    DispatchQueue.main.async { resize(size) }
                }
        )
        contentView = hosting
        resize = { [weak self] size in self?.place(size) }
        place(hosting.fittingSize)
    }

    override var canBecomeKey: Bool { true }

    func show() { makeKeyAndOrderFront(nil) }

    func dismiss() {
        orderOut(nil)
        contentView = nil
    }

    /// Centred under the status item, kept inside the screen.
    private func place(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let x = min(max(anchor.x - size.width / 2, visibleFrame.minX + 6), visibleFrame.maxX - size.width - 6)
        setFrame(NSRect(x: x, y: anchor.y - size.height, width: size.width, height: size.height), display: true)
        invalidateShadow()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Ordinary windows: the payment editor and settings.
@MainActor
enum Windows {
    private static var editor: NSWindow?
    private static var settings: NSWindow?

    static func showEditor(payment: Payment?) {
        guard let context = AppContext.shared else { return }
        editor?.close()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = payment == nil ? tr("New Payment", "Pembayaran Baru") : tr("Edit Payment", "Ubah Pembayaran")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            PaymentForm(original: payment, onDone: { window.close() }).environmentObject(context.store))
        window.center()
        track(window)
        editor = window
        present(window)
    }

    static func showSettings() {
        guard let context = AppContext.shared else { return }
        if settings == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = tr("DueBar Settings", "Pengaturan DueBar")
                window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView:
                SettingsView().environmentObject(context.store).environmentObject(context.sync))
            window.center()
            track(window)
            settings = window
        }
        present(settings!)
    }

    private static func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(UserDefaults.standard.bool(forKey: SettingsKey.showInDock) ? .regular : .accessory)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func track(_ window: NSWindow) {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                window.contentView = nil
                if editor === window { editor = nil }
                if settings === window { settings = nil }
            }
        }
    }
}
