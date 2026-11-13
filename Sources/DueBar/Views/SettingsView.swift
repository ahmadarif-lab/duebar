import AppKit
import DueKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

enum SettingsTab: Hashable, CaseIterable {
    case general, reminders, account

    var title: String {
        switch self {
        case .general: return tr("General", "Umum")
        case .reminders: return tr("Reminders", "Pengingat")
        case .account: return tr("Account", "Akun")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .reminders: return "bell"
        case .account: return "person"
        }
    }
}

/// Which tab the Settings window shows. Shared so other parts of the app (the "Sign in" link
/// in the dropdown) can open it on a given tab, even while the window is already open.
@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncService
    @ObservedObject private var router = SettingsRouter.shared
    @State private var showAbout = false

    static let size = CGSize(width: 680, height: 640)

    init(initialTab: SettingsTab? = nil) {
        if let initialTab { SettingsRouter.shared.tab = initialTab }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                pane.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
    }

    // The traffic lights sit in the top-left corner (full-size content window), so the title starts after them.
    private var header: some View {
        HStack(spacing: 12) {
            BrandMark(size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("DueBar").font(.system(size: 15.5, weight: .bold))
                Text(tr("Settings", "Pengaturan")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showAbout.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                    Text(tr("About", "Tentang"))
                }
                .font(.system(size: 13.5, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAbout, arrowEdge: .bottom) { AboutView() }
        }
        .padding(.leading, 96).padding(.trailing, 18)
        .frame(height: 56)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                SidebarItem(tab: tab, selected: router.tab == tab) { router.tab = tab }
            }
            Spacer()
            SidebarIllustration().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 196)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var pane: some View {
        switch router.tab {
        case .general: GeneralPane()
        case .reminders: NotificationsPane()
        case .account: AccountPane()
        }
    }
}

private struct SidebarItem: View {
    var tab: SettingsTab
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol).font(.system(size: 16, weight: .medium)).frame(width: 22)
                Text(tab.title).font(.system(size: 15, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(hovering ? Color.primary.opacity(0.06) : Color.clear))
            )
            .shadow(color: selected ? Brand.orange.opacity(0.3) : .clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A faded calendar-and-clock in the sidebar's corner.
private struct SidebarIllustration: View {
    var body: some View {
        ZStack {
            Circle().fill(Brand.orange.opacity(0.10)).frame(width: 118, height: 118).offset(x: -6, y: 4)
            Circle().fill(Brand.orange.opacity(0.13)).frame(width: 66, height: 66).offset(x: -22, y: 40)
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Brand.orange.opacity(0.55))
                .offset(x: 6, y: -2)
        }
        .frame(width: 130, height: 120)
        .accessibilityHidden(true)
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 8) {
            BrandMark(size: 64)
            Text("DueBar").font(.system(size: 20, weight: .bold)).padding(.top, 4)
            Text(tr("Version \(Updater.currentVersion ?? "dev")", "Versi \(Updater.currentVersion ?? "dev")"))
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
            Text(tr("A menu bar payment reminder.", "Pengingat pembayaran di menu bar."))
                .font(.system(size: 13)).multilineTextAlignment(.center).padding(.top, 2)
            Divider().padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 6) {
                Link(tr("Website", "Situs"), destination: URL(string: "https://apps.ahmadarif.id/duebar/")!)
                Link(tr("Source code", "Kode sumber"), destination: URL(string: "https://github.com/ahmadarif-lab/duebar")!)
                Link(tr("Privacy Policy", "Kebijakan Privasi"), destination: URL(string: "https://apps.ahmadarif.id/duebar/privacy/")!)
                Link(tr("Terms of Service", "Syarat & Ketentuan"), destination: URL(string: "https://apps.ahmadarif.id/duebar/terms/")!)
            }
            .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            Text("© 2026 Ahmad Arif · MIT License").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
        }
        .padding(20)
        .frame(width: 270)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @AppStorage(SettingsKey.language) private var language = "system"
    @AppStorage(SettingsKey.theme) private var theme = PanelTheme.systemID
    @AppStorage(SettingsKey.menuBarStyle) private var style = MenuBarStyle.next.rawValue
    @AppStorage(SettingsKey.defaultCurrency) private var currency = "IDR"
    @AppStorage(SettingsKey.showInDock) private var showInDock = false
    @AppStorage(SettingsKey.horizonDays) private var horizon = 60
    @State private var loginItem = LoginItem.isEnabled

    var body: some View {
        Form {
            Section(tr("Menu bar", "Menu bar")) {
                Picker(tr("Show", "Tampilkan"), selection: $style) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker(tr("Upcoming list reaches", "Daftar mendatang sampai"), selection: $horizon) {
                    Text(tr("30 days", "30 hari")).tag(30)
                    Text(tr("60 days", "60 hari")).tag(60)
                    Text(tr("90 days", "90 hari")).tag(90)
                    Text(tr("1 year", "1 tahun")).tag(365)
                }
            }
            Section(tr("Appearance", "Tampilan")) {
                Picker(tr("Theme", "Tema"), selection: $theme) {
                    Text(tr("System", "Sistem")).tag(PanelTheme.systemID)
                    Text(tr("Light", "Terang")).tag(PanelTheme.light.id)
                    Text(tr("Dark", "Gelap")).tag(PanelTheme.dark.id)
                }
                Picker(tr("Language", "Bahasa"), selection: $language) {
                    Text(tr("Follow system", "Ikuti sistem")).tag("system")
                    Text("English").tag("en")
                    Text("Bahasa Indonesia").tag("id")
                }
                Picker(tr("Default currency", "Mata uang bawaan"), selection: $currency) {
                    ForEach(Money.commonCurrencies, id: \.self) { Text($0).tag($0) }
                }
            }
            Section(tr("System", "Sistem")) {
                Toggle(tr("Start at login", "Buka saat login"), isOn: Binding(
                    get: { loginItem },
                    set: { LoginItem.setEnabled($0); loginItem = LoginItem.isEnabled }
                ))
                Toggle(tr("Show icon in Dock while a window is open", "Tampilkan ikon di Dock saat jendela terbuka"), isOn: $showInDock)
            }
            UpdatesSection()
            Text(tr("Language changes apply the next time you open a window.", "Perubahan bahasa berlaku saat jendela dibuka lagi."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationsPane: View {
    @Environment(\.themeAccent) private var accent
    @EnvironmentObject var store: Store
    @AppStorage(SettingsKey.notificationsOn) private var on = true
    @AppStorage(SettingsKey.defaultOffsets) private var offsetsRaw = "1,0"
    @AppStorage(SettingsKey.reminderMinute) private var minute = 9 * 60
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        Form {
            Section {
                Toggle(tr("Send reminders", "Kirim pengingat"), isOn: $on)
                    .onChange(of: on) { _, _ in AppContext.shared.notifier.reschedule(force: true) }
                if on, status == .denied {
                    HStack {
                        Label(tr("Notifications are off for DueBar in System Settings.", "Notifikasi DueBar mati di Pengaturan Sistem."), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.callout)
                        Spacer()
                        Button(tr("Open Settings", "Buka Pengaturan")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    }
                }
            }
            Section(tr("Defaults for new payments", "Bawaan untuk pembayaran baru")) {
                HStack(spacing: 6) {
                    ForEach([0, 1, 2, 3, 7, 14], id: \.self) { d in chip(d) }
                }
                DatePicker(tr("Remind at", "Ingatkan pukul"), selection: Binding(
                    get: { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date() },
                    set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minute = (c.hour ?? 9) * 60 + (c.minute ?? 0) }
                ), displayedComponents: .hourAndMinute)
                Button(tr("Apply to all existing payments", "Terapkan ke semua pembayaran")) { applyToAll() }
            }
            Section {
                Text(tr("Late payments get a reminder each morning for three days. Notifications are scheduled on each device from your synced data.",
                        "Pembayaran terlambat diingatkan tiap pagi selama tiga hari. Notifikasi dijadwalkan di tiap perangkat dari data yang tersinkron."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { status = await AppContext.shared.notifier.authorizationStatus() }
    }

    private var offsets: Set<Int> { Set(offsetsRaw.split(separator: ",").compactMap { Int($0) }) }

    private func chip(_ d: Int) -> some View {
        let isOn = offsets.contains(d)
        let label = d == 0 ? tr("On the day", "Hari H") : (d == 7 ? tr("1 week", "1 minggu") : (d == 14 ? tr("2 weeks", "2 minggu") : tr("\(d)d before", "H-\(d)")))
        return Button {
            var s = offsets
            if isOn { s.remove(d) } else { s.insert(d) }
            offsetsRaw = s.sorted().map(String.init).joined(separator: ",")
        } label: {
            Text(label).font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Capsule().fill(isOn ? accent : Color.secondary.opacity(0.15)))
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func applyToAll() {
        let list = offsets.sorted()
        store.mutate { ledger in
            for var p in ledger.allPayments {
                p.reminderOffsets = list
                p.reminderMinute = minute
                ledger.upsert(p)
            }
        }
    }
}

// MARK: - Account

private struct AccountPane: View {
    @EnvironmentObject var sync: SyncService
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                if let s = sync.session {
                    HStack(spacing: 12) {
                        AccountAvatar(session: s, size: 44)
                        VStack(alignment: .leading) {
                            Text(s.name.isEmpty ? s.email : s.name).font(.headline)
                            if !s.name.isEmpty { Text(s.email).font(.callout).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button(tr("Sign out", "Keluar")) { Task { await sync.signOut() } }
                    }
                    LabeledContent(tr("Status", "Status")) { status }
                    HStack {
                        Spacer()
                        Button(tr("Sync now", "Sinkronkan sekarang")) { Task { await sync.syncNow() } }
                            .disabled(sync.state == .syncing)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("Keep your payments in sync across your Mac and Android.", "Sinkronkan pembayaran antara Mac dan Android."))
                        Text(tr("Your data stays on this Mac until you sign in. Signing in uploads it to your own private space; DueBar only receives your name, email and profile photo from Google.",
                                "Data tetap di Mac ini sampai kamu masuk. Setelah masuk, data diunggah ke ruang pribadimu; DueBar hanya menerima nama, email, dan foto profil dari Google."))
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            GoogleSignInButton(title: tr("Sign in with Google", "Masuk dengan Google")) {
                                sync.startSignIn()
                            }
                            .disabled(sync.signingIn || !GoogleAuth.isConfigured)
                            if sync.signingIn {
                                ProgressView().controlSize(.small)
                                Text(tr("Finish in your browser…", "Selesaikan di browser…")).font(.callout).foregroundStyle(.secondary)
                                Button(tr("Cancel", "Batal")) { sync.cancelSignIn() }
                            }
                        }
                        if !GoogleAuth.isConfigured {
                            Label(tr("This build has no Google client ID yet.", "Build ini belum punya Google client ID."), systemImage: "info.circle")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if let error = sync.lastError {
                            Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                        }
                    }
                }
            }
            DataSections()
            if sync.isSignedIn {
                Section(tr("Danger zone", "Zona bahaya")) {
                    Button(tr("Delete my account and cloud data…", "Hapus akun dan data cloud…"), role: .destructive) { confirmDelete = true }
                        .confirmationDialog(tr("Delete your cloud data?", "Hapus data cloud?"), isPresented: $confirmDelete) {
                            Button(tr("Delete cloud data", "Hapus data cloud"), role: .destructive) { Task { _ = await sync.deleteAccount() } }
                        } message: { Text(tr("This removes your account and synced payments from the server and signs out every device. Data on this Mac is kept.", "Akun dan pembayaran di server dihapus dan semua perangkat keluar. Data di Mac ini tetap ada.")) }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var status: some View {
        switch sync.state {
        case .syncing: HStack(spacing: 6) { ProgressView().controlSize(.small); Text(tr("Syncing…", "Menyinkronkan…")) }
        case .idle: Text(sync.lastSync.map { tr("Synced \($0.formatted(.relative(presentation: .named)))", "Tersinkron \($0.formatted(.relative(presentation: .named)))") } ?? tr("Ready", "Siap"))
        case .failed(let why): Text(why).foregroundStyle(.red).lineLimit(2)
        case .signedOut: Text("—")
        }
    }
}

// MARK: - Data

/// Export, backup and storage, shown under the account in the Account tab.
private struct DataSections: View {
    @EnvironmentObject var store: Store
    @State private var message: String?

    var body: some View {
        Section(tr("Data", "Data")) {
            HStack {
                Button(tr("Export CSV…", "Ekspor CSV…")) { exportCSV() }
                Button(tr("Back up…", "Cadangkan…")) { exportBackup() }
                Button(tr("Restore…", "Pulihkan…")) { restore() }
            }
            Text(tr("CSV opens in Numbers or Excel. The JSON backup restores everything, including history.", "CSV bisa dibuka di Numbers atau Excel. Cadangan JSON memulihkan semuanya, termasuk riwayat."))
                .font(.callout).foregroundStyle(.secondary)
            LabeledContent(tr("On this Mac", "Di Mac ini")) {
                HStack(spacing: 10) {
                    Text(tr("\(store.ledger.allPayments.count) payments · \(store.history.count) history", "\(store.ledger.allPayments.count) pembayaran · \(store.history.count) riwayat"))
                        .foregroundStyle(.secondary)
                    Button(tr("Show in Finder", "Tampilkan di Finder")) { NSWorkspace.shared.open(Store.defaultDirectory) }
                }
            }
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "duebar-payments.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Export.csv(ledger: store.ledger).write(to: url, atomically: true, encoding: .utf8)
            message = tr("Exported to \(url.lastPathComponent).", "Diekspor ke \(url.lastPathComponent).")
        } catch { message = error.localizedDescription }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "duebar-backup.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Export.backupJSON(ledger: store.ledger).write(to: url, options: .atomic)
            message = tr("Backup saved to \(url.lastPathComponent).", "Cadangan disimpan ke \(url.lastPathComponent).")
        } catch { message = error.localizedDescription }
    }

    private func restore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            var count = 0
            var ledger = store.ledger
            count = try Export.restore(data, into: &ledger)
            store.replaceAll(ledger)
            message = tr("Restored \(count) payments.", "\(count) pembayaran dipulihkan.")
        } catch { message = tr("That file isn't a DueBar backup.", "Berkas itu bukan cadangan DueBar.") }
    }
}

// MARK: - Updates

private struct UpdatesSection: View {
    @ObservedObject private var updater = Updater.shared
    @AppStorage(SettingsKey.autoCheckUpdates) private var auto = true

    var body: some View {
        Section {
            LabeledContent(tr("Version", "Versi")) { Text(Updater.currentVersion ?? tr("Development build", "Build pengembangan")) }
            Toggle(tr("Automatically check for updates", "Cek pembaruan otomatis"), isOn: $auto)
        } header: {
            Text(tr("Updates", "Pembaruan"))
        } footer: {
            HStack(spacing: 8) {
                Circle().fill(status.color).frame(width: 8, height: 8)
                Text(status.text).foregroundStyle(.secondary)
                Spacer()
                if updater.isUpdating {
                    ProgressView().controlSize(.small)
                } else if let release = updater.availableUpdate {
                    Button(tr("Update to v\(release.version)", "Perbarui ke v\(release.version)")) { Task { await updater.update() } }
                        .buttonStyle(.borderedProminent).controlSize(.regular)
                } else {
                    Button(tr("Check for Updates", "Cek Pembaruan")) { Task { await updater.check() } }
                        .buttonStyle(.bordered).controlSize(.regular)
                        .disabled(updater.isChecking || Updater.currentVersion == nil)
                }
            }
            .font(.system(size: 12.5))
            .padding(.top, 4)
        }
    }

    private var status: (text: String, color: Color) {
        if let progress = updater.progressText { return (progress, .secondary) }
        if let error = updater.errorMessage { return (error, .red) }
        if let release = updater.availableUpdate { return (tr("v\(release.version) is available.", "v\(release.version) tersedia."), Brand.orange) }
        if updater.checkFailed { return (tr("Couldn't check for updates.", "Gagal memeriksa pembaruan."), .orange) }
        if updater.isChecking { return (tr("Checking…", "Memeriksa…"), .secondary) }
        if updater.lastChecked != nil {
            return updater.noReleases ? (tr("No releases yet.", "Belum ada rilis."), .secondary) : (tr("You're using the latest version.", "Kamu memakai versi terbaru."), .green)
        }
        return Updater.currentVersion == nil ? (tr("Updates are off in development builds.", "Pembaruan nonaktif di build pengembangan."), .secondary) : ("", .clear)
    }
}
