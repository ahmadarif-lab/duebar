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
            button.imagePosition = .imageOnly
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
        let soon = context.store.agenda.dueSoonCount
        button.image = Self.icon(badge: soon)
        button.contentTintColor = nil
        button.setAccessibilityLabel(tr("DueBar, \(soon) payments due soon", "DueBar, \(soon) pembayaran segera jatuh tempo"))
    }

    /// The logo with a red count badge at its top right, as in the design. Coloured rather than a
    /// template image; without the logo file it falls back to a monochrome symbol.
    static func icon(badge: Int) -> NSImage? {
        guard let logo = BrandLogo.image else {
            let fallback = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "DueBar")
            fallback?.isTemplate = true
            return fallback
        }
        let side: CGFloat = 18
        let width = badge > 0 ? side + 6 : side
        let image = NSImage(size: NSSize(width: width, height: side), flipped: false) { _ in
            logo.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
            guard badge > 0 else { return true }
            let label = badge > 9 ? "9+" : "\(badge)"
            let diameter: CGFloat = badge > 9 ? 13 : 11.5
            let circle = NSRect(x: width - diameter, y: side - diameter + 1, width: diameter, height: diameter)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: circle).fill()
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let ring = NSBezierPath(ovalIn: circle.insetBy(dx: -0.4, dy: -0.4)); ring.lineWidth = 0.8
            let text = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: badge > 9 ? 7 : 8, weight: .bold),
                .foregroundColor: NSColor.white,
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2))
            return true
        }
        image.isTemplate = false
        return image
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
        AppLock.shared.noteOpened(windowOpen: Windows.hasOpenWindow)
        guard let button = statusItem.button, let window = button.window else { return }
        let root = Dropdown(close: { [weak self] in self?.close() })
            .environmentObject(context.store)
            .environmentObject(context.sync)
            .environmentObject(context.rates)
        let panel = DropdownPanel(
            content: root,
            anchor: NSPoint(x: window.frame.midX, y: window.frame.minY - 3),
            screen: window.screen
        )
        panel.onResignKey = { [weak self] in if !AppLock.shared.isAuthenticating { self?.close() } }
        panel.onEscape = { [weak self] in self?.close() }
        panel.show()
        self.panel = panel
        button.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { if !AppLock.shared.isAuthenticating { self?.close() } }
        }
        Task { await context.sync.syncNow() }
    }

    func close() {
        guard panel != nil else { return }
        lastDismissal = Date()
        AppLock.shared.noteClosed()
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
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
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
    /// Which payment the open editor is for ("new" for a blank one), so asking for it again
    /// brings it forward instead of replacing it and losing what was typed.
    private static var editorKey: String?
    private static var settings: NSWindow?
    static var hasOpenWindow: Bool { editor != nil || settings != nil }

    static func showEditor(payment: Payment?) {
        guard let context = AppContext.shared else { return }
        let key = payment?.id ?? "new"
        if let editor, editorKey == key { present(editor); return }
        editor?.close()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PaymentForm.size),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = payment == nil ? tr("New Payment", "Pembayaran Baru") : tr("Edit Payment", "Ubah Pembayaran")
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = host(
            PaymentForm(original: payment, onDone: { window.close() }).environmentObject(context.store).environmentObject(context.sync).environmentObject(context.rates).themedWindow())
        window.setContentSize(PaymentForm.size)
        window.center()
        track(window)
        editor = window
        editorKey = key
        present(window)
    }

    static func showSettings(tab: SettingsTab = .general) {
        guard let context = AppContext.shared else { return }
        SettingsRouter.shared.tab = tab
        if settings == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: SettingsView.size),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = tr("DueBar Settings", "Pengaturan DueBar")
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = host(
                SettingsView().environmentObject(context.store).environmentObject(context.sync).environmentObject(context.rates).themedWindow())
            window.setContentSize(SettingsView.size)
            window.center()
            track(window)
            settings = window
        }
        present(settings!)
    }

    /// SwiftUI content for a window. The hosting view would otherwise size the window from the
    /// content's ideal size (plus the title bar's safe area); the window keeps the size we give it.
    private static func host<V: View>(_ root: V) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        return hosting
    }

    /// "Show icon in Dock while a window is open": the Dock icon exists only while the editor or
    /// Settings is open, and goes away again when the last one closes.
    static func applyDockPolicy() {
        let wanted = UserDefaults.standard.bool(forKey: SettingsKey.showInDock) && (editor != nil || settings != nil)
        NSApp.setActivationPolicy(wanted ? .regular : .accessory)
    }

    private static func present(_ window: NSWindow) {
        applyDockPolicy()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func track(_ window: NSWindow) {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                window.contentView = nil
                if editor === window { editor = nil; editorKey = nil }
                if settings === window { settings = nil }
                AppLock.shared.noteClosed()
                applyDockPolicy()
            }
        }
    }
}
