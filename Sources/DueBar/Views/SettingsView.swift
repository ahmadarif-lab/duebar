import AppKit
import DueKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

enum SettingsTab: Hashable { case general, reminders, account }

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

    init(initialTab: SettingsTab? = nil) {
        if let initialTab { SettingsRouter.shared.tab = initialTab }
    }

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralPane().tabItem { Label(tr("General", "Umum"), systemImage: "gearshape") }.tag(SettingsTab.general)
            NotificationsPane().tabItem { Label(tr("Reminders", "Pengingat"), systemImage: "bell") }.tag(SettingsTab.reminders)
            AccountPane().tabItem { Label(tr("Account", "Akun"), systemImage: "person.crop.circle") }.tag(SettingsTab.account)
        }
        .frame(width: 560, height: 600)
        .padding(.top, 12)
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
                    Text(tr("Follow system", "Ikuti sistem")).tag(PanelTheme.systemID)
                    ForEach(PanelTheme.presets) { Text($0.name).tag($0.id) }
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
        .themedForm()
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
        .themedForm()
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
                            Button {
                                Task { await sync.signIn() }
                            } label: {
                                HStack(spacing: 8) {
                                    if sync.signingIn { ProgressView().controlSize(.small) } else { Image(systemName: "person.crop.circle.badge.checkmark") }
                                    Text(tr("Sign in with Google", "Masuk dengan Google"))
                                }
                            }
                            .controlSize(.large).buttonStyle(.borderedProminent)
                            .disabled(sync.signingIn || !GoogleAuth.isConfigured)
                            if sync.signingIn { Text(tr("Finish in your browser…", "Selesaikan di browser…")).font(.callout).foregroundStyle(.secondary) }
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
        .themedForm()
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
        Section(tr("Updates", "Pembaruan")) {
            LabeledContent(tr("Version", "Versi")) { Text(Updater.currentVersion ?? tr("Development build", "Build pengembangan")) }
            Toggle(tr("Automatically check for updates", "Cek pembaruan otomatis"), isOn: $auto)
            HStack {
                status
                Spacer()
                if updater.isUpdating {
                    ProgressView().controlSize(.small)
                } else if let release = updater.availableUpdate {
                    Button(tr("Update to v\(release.version)", "Perbarui ke v\(release.version)")) { Task { await updater.update() } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(tr("Check for Updates", "Cek Pembaruan")) { Task { await updater.check() } }
                        .disabled(updater.isChecking || Updater.currentVersion == nil)
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let progress = updater.progressText {
            Text(progress).foregroundStyle(.secondary)
        } else if let error = updater.errorMessage {
            Text(error).foregroundStyle(.red).lineLimit(2)
        } else if let release = updater.availableUpdate {
            Text(tr("v\(release.version) is available.", "v\(release.version) tersedia.")).foregroundStyle(.secondary)
        } else if updater.checkFailed {
            Text(tr("Couldn't check for updates.", "Gagal memeriksa pembaruan.")).foregroundStyle(.orange)
        } else if updater.isChecking {
            Text(tr("Checking…", "Memeriksa…")).foregroundStyle(.secondary)
        } else if updater.lastChecked != nil {
            Text(updater.noReleases ? tr("No releases yet.", "Belum ada rilis.") : tr("DueBar is up to date.", "DueBar sudah versi terbaru.")).foregroundStyle(.secondary)
        } else {
            Text(Updater.currentVersion == nil ? tr("Updates are off in development builds.", "Pembaruan nonaktif di build pengembangan.") : "").foregroundStyle(.secondary)
        }
    }
}
