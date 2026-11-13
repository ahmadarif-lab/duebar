import AppKit
import DueKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

enum SettingsTab: Hashable, CaseIterable {
    case general, reminders, data, account

    var title: String {
        switch self {
        case .general: return tr("General", "Umum")
        case .reminders: return tr("Reminders", "Pengingat")
        case .data: return tr("Data", "Data")
        case .account: return tr("Account", "Akun")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .reminders: return "bell"
        case .data: return "list.bullet.rectangle"
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

    /// Taller only for UI snapshots (DUEBAR_SETTINGS_HEIGHT), so a whole pane fits one picture.
    static var size: CGSize {
        CGSize(width: 560, height: CGFloat(Double(ProcessInfo.processInfo.environment["DUEBAR_SETTINGS_HEIGHT"] ?? "") ?? 500))
    }

    init(initialTab: SettingsTab? = nil) {
        if let initialTab { SettingsRouter.shared.tab = initialTab }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            pane.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// The logo and name sit at the bottom of the sidebar; clicking them opens About.
    private var brand: some View {
        Button { showAbout.toggle() } label: {
            HStack(spacing: 10) {
                BrandMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DueBar").font(.system(size: 13.5, weight: .semibold))
                    Text(Updater.currentVersion.map { "v\($0)" } ?? tr("dev build", "build dev"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tr("About DueBar", "Tentang DueBar"))
        .popover(isPresented: $showAbout, arrowEdge: .trailing) { AboutView() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                SidebarItem(tab: tab, selected: router.tab == tab) { router.tab = tab }
            }
            Spacer()
            brand
        }
        .padding(12)
        .frame(width: 150)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var pane: some View {
        switch router.tab {
        case .general: GeneralPane()
        case .reminders: NotificationsPane()
        case .data: DataPane()
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
            HStack(spacing: 8.5) {
                Image(systemName: tab.symbol).font(.system(size: 11.5, weight: .medium)).frame(width: 22)
                Text(tab.title).font(.system(size: 10.5, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8.5)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(hovering ? Color.primary.opacity(0.06) : Color.clear))
            )
            .shadow(color: selected ? Brand.orange.opacity(0.3) : .clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 6.5) {
            BrandMark(size: 54)
            Text("DueBar").font(.system(size: 14.5, weight: .bold)).padding(.top, 3.5)
            Text(tr("Version \(Updater.currentVersion ?? "dev")", "Versi \(Updater.currentVersion ?? "dev")"))
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Text(tr("A menu bar payment reminder.", "Pengingat pembayaran di menu bar."))
                .font(.system(size: 9)).multilineTextAlignment(.center).padding(.top, 1.5)
            Divider().padding(.vertical, 5)
            VStack(alignment: .leading, spacing: 6) {
                Link(tr("Website", "Situs"), destination: URL(string: "https://apps.ahmadarif.id/duebar/")!)
                Link(tr("Source code", "Kode sumber"), destination: URL(string: "https://github.com/ahmadarif-lab/duebar")!)
                Link(tr("Privacy Policy", "Kebijakan Privasi"), destination: URL(string: "https://apps.ahmadarif.id/duebar/privacy/")!)
                Link(tr("Terms of Service", "Syarat & Ketentuan"), destination: URL(string: "https://apps.ahmadarif.id/duebar/terms/")!)
            }
            .font(.system(size: 9)).frame(maxWidth: .infinity, alignment: .leading)
            Link(tr("Exchange rates by ExchangeRate-API", "Kurs dari ExchangeRate-API"), destination: URL(string: "https://www.exchangerate-api.com")!)
                .font(.system(size: 11)).padding(.top, 6)
            Text("© 2026 Ahmad Arif · MIT License").font(.system(size: 9)).foregroundStyle(.secondary).padding(.top, 6.5)
        }
        .padding(17)
        .frame(width: 240)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @EnvironmentObject var rates: RatesService
    @AppStorage(SettingsKey.language) private var language = "system"
    @AppStorage(SettingsKey.theme) private var theme = PanelTheme.systemID
    @AppStorage(SettingsKey.defaultCurrency) private var currency = "IDR"
    @AppStorage(SettingsKey.showInDock) private var showInDock = false
    @State private var loginItem = LoginItem.isEnabled

    private var currencyChoices: [String] {
        Money.commonCurrencies.contains(currency) ? Money.commonCurrencies : Money.commonCurrencies + [currency]
    }

    var body: some View {
        Form {
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
                Picker(tr("Main currency", "Mata uang utama"), selection: $currency) {
                    ForEach(currencyChoices, id: \.self) { Text($0).tag($0) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Totals are shown in this currency, and new payments start with it. Payments in another currency are converted at the latest exchange rate.",
                            "Total ditampilkan dalam mata uang ini dan pembayaran baru memakainya. Pembayaran dalam mata uang lain dikonversi dengan kurs terbaru."))
                    if let rates = rates.rates {
                        Text(tr("Rates updated \(DueText.ago(rates.fetchedAt)).", "Kurs diperbarui \(DueText.ago(rates.fetchedAt))."))
                    } else if rates.failed {
                        Text(tr("Couldn't fetch exchange rates; they are fetched again when needed.", "Gagal mengambil kurs; akan dicoba lagi saat diperlukan."))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Section(tr("System", "Sistem")) {
                Toggle(tr("Start at login", "Buka saat login"), isOn: Binding(
                    get: { loginItem },
                    set: { LoginItem.setEnabled($0); loginItem = LoginItem.isEnabled }
                ))
                Toggle(tr("Show icon in Dock while a window is open", "Tampilkan ikon di Dock saat jendela terbuka"), isOn: $showInDock)
                    .onChange(of: showInDock) { _, _ in Windows.applyDockPolicy() }
            }
            UpdatesSection()
            Text(tr("Language changes apply the next time you open a window.", "Perubahan bahasa berlaku saat jendela dibuka lagi."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .controlSize(.small)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach([0, 1, 2, 3, 7, 14], id: \.self) { d in chip(d) }
                }
                LabeledContent(tr("Remind at", "Ingatkan pukul")) {
                    TimeField(date: Binding(
                        get: { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date() },
                        set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minute = (c.hour ?? 9) * 60 + (c.minute ?? 0) }
                    ))
                }
                Button(tr("Apply to all existing payments", "Terapkan ke semua pembayaran")) { applyToAll() }
            }
            Section {
                Text(tr("Late payments get a reminder each morning for three days. Notifications are scheduled on each device from your synced data.",
                        "Pembayaran terlambat diingatkan tiap pagi selama tiga hari. Notifikasi dijadwalkan di tiap perangkat dari data yang tersinkron."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
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
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6).padding(.vertical, 5)
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
        .controlSize(.small)
    }

    @ViewBuilder
    private var status: some View {
        switch sync.state {
        case .syncing: HStack(spacing: 6) { ProgressView().controlSize(.small); Text(tr("Syncing…", "Menyinkronkan…")) }
        case .idle: Text(sync.lastSync.map { tr("Synced \(DueText.ago($0))", "Tersinkron \(DueText.ago($0))") } ?? tr("Ready", "Siap"))
        case .failed(let why): Text(why).foregroundStyle(.red).lineLimit(2)
        case .signedOut: Text("—")
        }
    }
}

// MARK: - Data

// MARK: - Data (manage payments)

private enum PaymentFilter: CaseIterable, Hashable {
    case active, paused, finished, history

    var title: String {
        switch self {
        case .active: return tr("Active", "Aktif")
        case .paused: return tr("Paused", "Dijeda")
        case .finished: return tr("Finished", "Selesai")
        case .history: return tr("History", "Riwayat")
        }
    }
}

/// Every payment in one place: search, add, edit, pause, mark paid or delete without going through
/// the menu bar, plus the history and the backup tools. Laid out with the same pills and cards as
/// the dropdown rather than as a system form.
private struct DataPane: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var rates: RatesService
    @Environment(\.themeAccent) private var accent
    @State private var filter: PaymentFilter = .active
    @State private var query = ""
    @State private var pendingDelete: Payment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    searchField
                    Button { Windows.showEditor(payment: nil) } label: {
                        Label(tr("Add", "Tambah"), systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Brand.gradient))
                            .shadow(color: Brand.orange.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                filterPills
                listCard
                DataToolsCard()
            }
            .padding(18)
        }
        .confirmationDialog(
            tr("Delete \(pendingDelete?.name ?? "this payment")?", "Hapus \(pendingDelete?.name ?? "pembayaran ini")?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { payment in
            Button(tr("Delete", "Hapus"), role: .destructive) { store.delete(payment.id) }
        } message: { _ in
            Text(tr("Its history is removed too, on every device.", "Riwayatnya ikut terhapus, di semua perangkat."))
        }
    }

    // MARK: Controls

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            TextField("", text: $query, prompt: Text(tr("Search payments", "Cari pembayaran")))
                .textFieldStyle(.plain).labelsHidden().font(.system(size: 13))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var filterPills: some View {
        HStack(spacing: 4) {
            ForEach(PaymentFilter.allCases, id: \.self) { f in
                let selected = filter == f
                Button { filter = f } label: {
                    HStack(spacing: 5) {
                        Text(f.title)
                        Text("\(count(f))").font(.system(size: 11, weight: .semibold)).opacity(selected ? 1 : 0.7)
                    }
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(selected ? accent.opacity(0.16) : Color.clear))
                    .foregroundStyle(selected ? accent : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Lists

    @ViewBuilder
    private var listCard: some View {
        if filter == .history {
            let events = store.history.filter { matches($0.name) }
            if events.isEmpty {
                emptyCard(query.isEmpty ? tr("Paid payments will show up here.", "Pembayaran yang sudah lunas muncul di sini.") : tr("No matches.", "Tidak ada yang cocok."))
            } else {
                VStack(spacing: 6) {
                    rows(Array(events.prefix(200)), id: \.id) { HistoryRow(event: $0) }
                    if events.count > 200 {
                        Text(tr("Showing the latest 200 of \(events.count) entries.", "Menampilkan 200 terbaru dari \(events.count) entri.")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            let list = payments(for: filter).filter { matches($0.name) }
            if list.isEmpty {
                emptyCard(emptyText)
            } else {
                rows(list, id: \.id) { ManagedPaymentRow(payment: $0, onDelete: { pendingDelete = $0 }) }
            }
        }
    }

    private func rows<Item, Row: View>(_ items: [Item], id: KeyPath<Item, String>, @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(item)
                if index < items.count - 1 { Divider().padding(.leading, 58) }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .settingsCard()
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 26).padding(.horizontal, 16)
            .settingsCard()
    }

    private func payments(for filter: PaymentFilter) -> [Payment] {
        let all = store.ledger.allPayments
        switch filter {
        case .active:
            return all.filter { !$0.archived && !$0.paused }.sorted { ($0.nextDue() ?? .today(), $0.name.lowercased()) < ($1.nextDue() ?? .today(), $1.name.lowercased()) }
        case .paused:
            return all.filter { !$0.archived && $0.paused }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .finished:
            return all.filter(\.archived).sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .history:
            return []
        }
    }

    private func count(_ filter: PaymentFilter) -> Int {
        filter == .history ? store.history.count : payments(for: filter).count
    }

    private func matches(_ name: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || name.lowercased().contains(q)
    }

    private var emptyText: String {
        if !query.isEmpty { return tr("No matches.", "Tidak ada yang cocok.") }
        switch filter {
        case .active: return tr("No active payments yet. Add one with the button above.", "Belum ada pembayaran aktif. Tambahkan dengan tombol di atas.")
        case .paused: return tr("Nothing is paused.", "Tidak ada yang dijeda.")
        case .finished: return tr("Payments that reach their end land here.", "Pembayaran yang sudah berakhir muncul di sini.")
        case .history: return ""
        }
    }
}

private struct ManagedPaymentRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var rates: RatesService
    @Environment(\.themeAccent) private var accent
    var payment: Payment
    var onDelete: (Payment) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: payment.category, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(payment.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                subtitle.font(.system(size: 12)).lineLimit(1)
            }
            Spacer(minLength: 8)
            // Like the dropdown: on hover the actions take the amount's place.
            if hovering {
                HStack(spacing: 2) {
                    if !payment.archived && !payment.paused {
                        RowIconButton(symbol: "checkmark.circle", help: tr("Mark as paid", "Tandai lunas"), tint: .green) { store.resolve(payment.id, .paid) }
                    }
                    RowIconButton(symbol: "pencil", help: tr("Edit", "Ubah")) { Windows.showEditor(payment: payment) }
                    Menu { menuItems } label: {
                        Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).frame(width: 26, height: 26)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26)
                }
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Money.format(payment.amount, currency: payment.currency)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    if let converted = convertedText { Text(converted).font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit() }
                }
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Color.primary.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { Windows.showEditor(payment: payment) }
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        if !payment.archived && !payment.paused {
            Button(tr("Mark as paid", "Tandai lunas")) { store.resolve(payment.id, .paid) }
            Button(tr("Skip this time", "Lewati kali ini")) { store.resolve(payment.id, .skipped) }
        }
        if let url = URL(string: payment.url), !payment.url.isEmpty, url.scheme != nil {
            Button(tr("Open payment link", "Buka tautan pembayaran")) { NSWorkspace.shared.open(url) }
        }
        if !payment.archived {
            Button(payment.paused ? tr("Resume", "Lanjutkan") : tr("Pause", "Jeda")) { store.setPaused(payment.id, !payment.paused) }
        }
        Button(tr("Edit…", "Ubah…")) { Windows.showEditor(payment: payment) }
        Divider()
        Button(tr("Delete…", "Hapus…"), role: .destructive) { onDelete(payment) }
    }

    @ViewBuilder
    private var subtitle: some View {
        if payment.archived {
            Text(tr("Finished · \(DueText.repeatText(payment.repeatRule))", "Selesai · \(DueText.repeatText(payment.repeatRule))")).foregroundStyle(.secondary)
        } else if payment.paused {
            Text(tr("Paused · \(DueText.repeatText(payment.repeatRule))", "Dijeda · \(DueText.repeatText(payment.repeatRule))")).foregroundStyle(.secondary)
        } else if let status = payment.status(), let due = payment.nextDue() {
            HStack(spacing: 5) {
                Image(systemName: payment.repeatRule.isRepeating ? "repeat" : "calendar").font(.system(size: 10.5)).foregroundStyle(accent)
                Text(DueText.relative(status)).foregroundStyle(color(status))
                Text("·").foregroundStyle(.secondary)
                Text(DueText.date(due)).foregroundStyle(.secondary)
            }
        }
    }

    private func color(_ status: DueStatus) -> Color {
        switch status {
        case .overdue: return .red
        case .today: return .orange
        case .upcoming(let d): return d <= 2 ? .orange : .secondary
        }
    }

    private var convertedText: String? {
        let main = UserDefaults.standard.mainCurrency
        guard payment.currency != main, let value = rates.rates?.convert(payment.amount, from: payment.currency, to: main) else { return nil }
        return "≈ " + Money.formatTotal(value, currency: main)
    }
}

private struct RowIconButton: View {
    var symbol: String
    var help: String
    var tint: Color = .secondary
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(hovering ? Color.primary.opacity(0.1) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct HistoryRow: View {
    @EnvironmentObject var store: Store
    var event: PaymentEvent

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: event.category, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text("\(event.kind == .paid ? tr("Paid", "Lunas") : tr("Skipped", "Dilewati")) · \(DueText.date(DayStamp(event.resolvedAt)))")
                    .font(.system(size: 12)).foregroundStyle(event.kind == .paid ? Color.green : Color.secondary)
            }
            Spacer(minLength: 8)
            Text(Money.format(event.amount, currency: event.currency)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            if canUndo {
                RowIconButton(symbol: "arrow.uturn.backward", help: tr("Undo", "Urungkan")) { store.undo(event.id) }
            } else {
                Color.clear.frame(width: 26, height: 26)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
    }

    /// Only the latest resolution of a payment can be taken back.
    private var canUndo: Bool {
        guard let p = store.ledger.payment(event.paymentId), p.resolvedCount > 0 else { return false }
        return p.occurrence(p.resolvedCount - 1) == event.dueDate
    }
}

/// Export, backup and storage, shown under the account in the Account tab.
private struct DataToolsCard: View {
    @EnvironmentObject var store: Store
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Backup & export", "Cadangan & ekspor")).font(.system(size: 14, weight: .semibold)).padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    PillButton(title: tr("Export CSV", "Ekspor CSV"), symbol: "tablecells") { exportCSV() }
                    PillButton(title: tr("Back up", "Cadangkan"), symbol: "arrow.down.doc") { exportBackup() }
                    PillButton(title: tr("Restore", "Pulihkan"), symbol: "arrow.up.doc") { restore() }
                }
                Text(tr("CSV opens in Numbers or Excel. The JSON backup restores everything, including history.", "CSV bisa dibuka di Numbers atau Excel. Cadangan JSON memulihkan semuanya, termasuk riwayat."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("On this Mac", "Di Mac ini")).font(.system(size: 13))
                        Text(tr("\(store.ledger.allPayments.count) payments · \(store.history.count) history", "\(store.ledger.allPayments.count) pembayaran · \(store.history.count) riwayat"))
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    PillButton(title: tr("Show in Finder", "Tampilkan di Finder"), symbol: "folder") { NSWorkspace.shared.open(Store.defaultDirectory) }
                }
                if let message { Text(message).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            .padding(14)
            .settingsCard()
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
