import DueKit
import SwiftUI

/// The menu bar dropdown: a home page with the headline numbers and the next few payments,
/// a page with every payment, and the history.
struct DropdownContent: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncService
    @ObservedObject private var updater = Updater.shared
    @Environment(\.panelTheme) private var theme
    var close: () -> Void

    enum Page { case home, all, history }
    @State private var page: Page
    @State private var undo: PaymentEvent?
    @State private var undoTask: Task<Void, Never>?

    init(close: @escaping () -> Void, initialPage: Page = .home) {
        self.close = close
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        VStack(spacing: 10) {
            switch page {
            case .home: HomePage(goAll: { page = .all }, markPaid: markPaid(_:), close: close)
            case .all, .history: ListPage(page: $page, markPaid: markPaid(_:), close: close)
            }
            if let undo { undoBar(undo) }
            if let release = updater.availableUpdate { updateBar(release) }
            FooterMenu(close: close)
        }
    }

    private func markPaid(_ id: String) {
        guard let event = store.resolve(id, .paid) else { return }
        undo = event
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(7))
            if !Task.isCancelled { undo = nil }
        }
    }

    private func undoBar(_ event: PaymentEvent) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.positive)
            Text(tr("\(event.name) marked paid", "\(event.name) ditandai lunas")).font(.system(size: 9)).lineLimit(1)
            Spacer()
            Button(tr("Undo", "Urungkan")) {
                store.undo(event.id)
                undo = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .cardBackground()
    }

    private func updateBar(_ release: Updater.Release) -> some View {
        HStack(spacing: 8.5) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 12.5)).foregroundStyle(theme.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("DueBar v\(release.version) is available", "DueBar v\(release.version) tersedia")).font(.system(size: 9, weight: .medium))
                if let progress = updater.progressText {
                    Text(progress).font(.system(size: 9)).foregroundStyle(theme.secondaryText)
                } else if let error = updater.errorMessage {
                    Text(error).font(.system(size: 9)).foregroundStyle(theme.critical).lineLimit(1)
                }
            }
            Spacer()
            if updater.isUpdating {
                ProgressView().controlSize(.small)
            } else {
                Button(tr("Update", "Perbarui")) { Task { await updater.update() } }
                    .buttonStyle(.plain).font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.primary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .cardBackground()
    }
}

// MARK: - Home

private struct HomePage: View {
    @EnvironmentObject var store: Store
    @Environment(\.panelTheme) private var theme
    var goAll: () -> Void
    var markPaid: (String) -> Void
    var close: () -> Void

    var body: some View {
        let agenda = store.agenda
        let hasPayments = !agenda.isEmpty
        VStack(spacing: 12) {
            HeaderRow(agenda: agenda, close: close)
            OutstandingCard(outstanding: agenda.outstanding(), goAll: goAll)
            if hasPayments {
                upcoming(agenda)
                if agenda.overdue.isEmpty && agenda.today.isEmpty && agenda.week.isEmpty { CaughtUpCard() }
            } else {
                EmptyCard(close: close)
            }
        }
    }

    @ViewBuilder
    private func upcoming(_ agenda: Agenda) -> some View {
        let items = Array((agenda.overdue + agenda.today + agenda.week + agenda.later).prefix(3))
        if !items.isEmpty {
            VStack(spacing: 6.5) {
                HStack {
                    Text(tr("Upcoming", "Mendatang")).font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Button(action: goAll) {
                        HStack(spacing: 3.5) {
                            Text(tr("View All", "Lihat Semua"))
                            Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 3.5)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PaymentRow(item: item, markPaid: markPaid, close: close)
                        if index < items.count - 1 { Divider().overlay(theme.track).padding(.leading, 50.5) }
                    }
                }
                .padding(.horizontal, 3.5).padding(.vertical, 1.5)
                .cardBackground()
            }
        }
    }
}

private struct HeaderRow: View {
    @Environment(\.panelTheme) private var theme
    var agenda: Agenda
    var close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            BrandMark(size: 38.5)
            VStack(alignment: .leading, spacing: 1.5) {
                Text("DueBar").font(.system(size: 12.5, weight: .bold))
                subtitle.font(.system(size: 9.5))
            }
            Spacer()
            IconButton(symbol: "gearshape", help: tr("Settings", "Pengaturan"), size: 28.5) { close(); Windows.showSettings() }
        }
        .padding(.horizontal, 3.5)
    }

    @ViewBuilder
    private var subtitle: some View {
        let soon = agenda.today.count + agenda.week.count
        if !agenda.overdue.isEmpty {
            Text(tr("\(agenda.overdue.count) overdue", "\(agenda.overdue.count) terlambat")).foregroundStyle(theme.critical)
        } else if soon > 0 {
            Text(soon == 1 ? tr("1 payment due soon", "1 pembayaran segera jatuh tempo") : tr("\(soon) payments due soon", "\(soon) pembayaran segera jatuh tempo"))
                .foregroundStyle(theme.secondaryText)
        } else if !agenda.isEmpty {
            Text(tr("All caught up", "Semua beres")).foregroundStyle(theme.secondaryText)
        } else {
            Text(tr("No payments yet", "Belum ada pembayaran")).foregroundStyle(theme.secondaryText)
        }
    }
}

private struct OutstandingCard: View {
    @Environment(\.panelTheme) private var theme
    var outstanding: Outstanding
    var goAll: () -> Void

    var body: some View {
        Button(action: goAll) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.gradient)
                    Image(systemName: "creditcard.fill").font(.system(size: 15.5, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 43.5, height: 43.5)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(tr("Total Outstanding", "Total Tertunggak")).font(.system(size: 10)).foregroundStyle(theme.secondaryText)
                    ForEach(amountCurrencies, id: \.self) { currency in
                        Text(Money.format(outstanding.totals[currency] ?? 0, currency: currency))
                            .font(.system(size: 18.5, weight: .bold, design: .rounded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 4)
                HStack(spacing: 3.5) {
                    Text(outstanding.count == 1 ? tr("1 item", "1 item") : tr("\(outstanding.count) items", "\(outstanding.count) item"))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.primary)
                .padding(.horizontal, 10).padding(.vertical, 6.5)
                .background(Capsule().fill(theme.primary.opacity(0.16)))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(theme.primary.opacity(theme.isDark ? 0.16 : 0.12)))
        }
        .buttonStyle(.plain)
    }

    private var amountCurrencies: [String] {
        let list = outstanding.currencies
        if list.isEmpty { return [UserDefaults.standard.string(forKey: SettingsKey.defaultCurrency) ?? "IDR"] }
        return Array(list.prefix(2))
    }
}

private struct CaughtUpCard: View {
    @Environment(\.panelTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(theme.positive)
            VStack(alignment: .leading, spacing: 1.5) {
                Text(tr("All caught up!", "Semua beres!")).font(.system(size: 11.5, weight: .bold))
                Text(tr("No more payments due this week.", "Tidak ada lagi pembayaran minggu ini."))
                    .font(.system(size: 9)).foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Text("🎉").font(.system(size: 21))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(theme.positive.opacity(theme.isDark ? 0.16 : 0.13)))
    }
}

private struct EmptyCard: View {
    @Environment(\.panelTheme) private var theme
    var close: () -> Void

    var body: some View {
        VStack(spacing: 8.5) {
            Text(tr("Add bills, subscriptions and installments to get reminded before they're due.",
                    "Tambahkan tagihan, langganan, dan cicilan supaya diingatkan sebelum jatuh tempo."))
                .font(.system(size: 9.5)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center)
            Button {
                close(); Windows.showEditor(payment: nil)
            } label: {
                Label(tr("Add your first payment", "Tambah pembayaran pertama"), systemImage: "plus")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 13.5).padding(.vertical, 7.5)
                    .background(Capsule().fill(Brand.gradient))
            }
            .buttonStyle(.plain)
        }
        .padding(15).frame(maxWidth: .infinity)
        .cardBackground()
    }
}

// MARK: - All payments / history

private struct ListPage: View {
    @EnvironmentObject var store: Store
    @Environment(\.panelTheme) private var theme
    @Binding var page: DropdownContent.Page
    var markPaid: (String) -> Void
    var close: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6.5) {
                Button { page = .home } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        .frame(width: 28.5, height: 28.5).background(Circle().fill(theme.track))
                }
                .buttonStyle(.plain).help(tr("Back", "Kembali"))
                Text(page == .all ? tr("All payments", "Semua pembayaran") : tr("History", "Riwayat"))
                    .font(.system(size: 12.5, weight: .bold))
                Spacer()
                tabButton(tr("Upcoming", "Mendatang"), .all)
                tabButton(tr("History", "Riwayat"), .history)
            }
            .padding(.horizontal, 3.5)
            if page == .all {
                UpcomingList(markPaid: markPaid, close: close)
            } else {
                HistoryList()
            }
        }
    }

    private func tabButton(_ title: String, _ value: DropdownContent.Page) -> some View {
        Button { page = value } label: {
            Text(title)
                .font(.system(size: 9, weight: page == value ? .semibold : .regular))
                .padding(.horizontal, 8.5).padding(.vertical, 5)
                .background(Capsule().fill(page == value ? theme.primary.opacity(0.18) : .clear))
                .foregroundStyle(page == value ? theme.primary : theme.secondaryText)
        }
        .buttonStyle(.plain)
    }
}

struct UpcomingList: View {
    @EnvironmentObject var store: Store
    @Environment(\.panelTheme) private var theme
    var markPaid: (String) -> Void
    var close: () -> Void

    var body: some View {
        let agenda = store.agenda
        if agenda.isEmpty {
            Text(tr("No payments yet", "Belum ada pembayaran"))
                .font(.system(size: 9.5)).foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity).padding(.vertical, 23.5).cardBackground()
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    group(tr("Overdue", "Terlambat"), agenda.overdue, color: theme.critical)
                    group(tr("Today", "Hari ini"), agenda.today, color: theme.warning)
                    group(tr("This week", "Minggu ini"), agenda.week)
                    group(tr("Later", "Nanti"), agenda.later)
                    if !agenda.paused.isEmpty { pausedBox(agenda.paused) }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 336)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [AgendaItem], color: Color? = nil) -> some View {
        if !items.isEmpty {
            VStack(spacing: 5) {
                HStack {
                    Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(color ?? theme.text)
                    Spacer()
                    if let total = total(items) { Text(total).font(.system(size: 9, weight: .medium)).foregroundStyle(theme.secondaryText).monospacedDigit() }
                }
                .padding(.horizontal, 5)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PaymentRow(item: item, markPaid: markPaid, close: close)
                        if index < items.count - 1 { Divider().overlay(theme.track).padding(.leading, 50.5) }
                    }
                }
                .padding(.horizontal, 3.5).padding(.vertical, 1.5)
                .cardBackground()
            }
        }
    }

    private func pausedBox(_ payments: [Payment]) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(tr("Paused", "Dijeda")).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 5)
            VStack(spacing: 6.5) {
                ForEach(payments) { p in
                    HStack(spacing: 8.5) {
                        CategoryBadge(category: p.category, size: 28.5).opacity(0.5)
                        Text(p.name).font(.system(size: 10)).foregroundStyle(theme.secondaryText).lineLimit(1)
                        Spacer()
                        Button(tr("Resume", "Lanjutkan")) { store.setPaused(p.id, false) }
                            .buttonStyle(.plain).font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.primary)
                    }
                }
            }
            .padding(10).cardBackground()
        }
    }

    private func total(_ items: [AgendaItem]) -> String? {
        let currencies = Set(items.map(\.payment.currency))
        guard currencies.count == 1, let c = currencies.first else { return "\(items.count)" }
        return Money.format(items.reduce(0) { $0 + $1.payment.amount }, currency: c)
    }
}

struct PaymentRow: View {
    @EnvironmentObject var store: Store
    @Environment(\.panelTheme) private var theme
    var item: AgendaItem
    var markPaid: (String) -> Void
    var close: () -> Void
    @State private var hovering = false

    var body: some View {
        let p = item.payment
        HStack(spacing: 10) {
            CategoryBadge(category: p.category, size: 38.5)
            VStack(alignment: .leading, spacing: 2.5) {
                Text(p.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: p.repeatRule.isRepeating ? "repeat" : "calendar").font(.system(size: 9)).foregroundStyle(theme.primary)
                    Text(DueText.relative(item.status)).foregroundStyle(statusColor)
                    Text("·").foregroundStyle(theme.secondaryText)
                    Text(DueText.date(item.due)).foregroundStyle(theme.secondaryText)
                }
                .font(.system(size: 9)).lineLimit(1)
            }
            Spacer(minLength: 6)
            if hovering {
                IconButton(symbol: "checkmark.circle", help: tr("Mark as paid", "Tandai lunas"), tint: theme.positive, size: 27) { markPaid(p.id) }
                menu
            } else {
                Text(Money.format(p.amount, currency: p.currency)).font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
            }
        }
        .padding(.vertical, 7.5).padding(.horizontal, 6.5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? theme.track.opacity(0.6) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { edit() }
        .contextMenu { menuItems }
    }

    private var statusColor: Color {
        switch item.status {
        case .overdue: return theme.critical
        case .today: return theme.warning
        case .upcoming(let d): return d <= 2 ? theme.warning : theme.secondaryText
        }
    }

    private var menu: some View {
        Menu { menuItems } label: {
            Image(systemName: "ellipsis").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.secondaryText)
                .frame(width: 25, height: 27)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 25)
    }

    @ViewBuilder
    private var menuItems: some View {
        let p = item.payment
        Button(tr("Mark as paid", "Tandai lunas")) { markPaid(p.id) }
        Button(tr("Skip this time", "Lewati kali ini")) { store.resolve(p.id, .skipped) }
        if let url = URL(string: p.url), !p.url.isEmpty, url.scheme != nil {
            Button(tr("Open payment link", "Buka tautan pembayaran")) { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button(tr("Edit…", "Ubah…")) { edit() }
        Button(tr("Pause", "Jeda")) { store.setPaused(p.id, true) }
        Button(tr("Delete", "Hapus"), role: .destructive) { store.delete(p.id) }
    }

    private func edit() {
        close()
        Windows.showEditor(payment: item.payment)
    }
}

struct HistoryList: View {
    @EnvironmentObject var store: Store
    @Environment(\.panelTheme) private var theme

    var body: some View {
        let events = Array(store.history.prefix(80))
        if events.isEmpty {
            Text(tr("Paid payments will show up here.", "Pembayaran yang sudah lunas muncul di sini."))
                .font(.system(size: 9.5)).foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity).padding(.vertical, 23.5).cardBackground()
        } else {
            let groups = Dictionary(grouping: events) { String($0.resolvedAt.formatted(.dateTime.year().month(.twoDigits))) }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(groups.keys.sorted(by: >), id: \.self) { key in
                        let rows = groups[key] ?? []
                        VStack(spacing: 5) {
                            HStack {
                                Text(Self.monthTitle(rows[0].resolvedAt)).font(.system(size: 10, weight: .semibold))
                                Spacer()
                                if let total = Self.total(rows) { Text(total).font(.system(size: 9, weight: .medium)).foregroundStyle(theme.secondaryText).monospacedDigit() }
                            }
                            .padding(.horizontal, 5)
                            VStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, e in
                                    row(e)
                                    if index < rows.count - 1 { Divider().overlay(theme.track).padding(.leading, 47) }
                                }
                            }
                            .padding(.horizontal, 3.5).padding(.vertical, 1.5)
                            .cardBackground()
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 336)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ e: PaymentEvent) -> some View {
        HStack(spacing: 10) {
            CategoryBadge(category: e.category, size: 33.5)
            VStack(alignment: .leading, spacing: 1.5) {
                Text(e.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Text("\(e.kind == .paid ? tr("Paid", "Lunas") : tr("Skipped", "Dilewati")) · \(DueText.date(DayStamp(e.resolvedAt)))")
                    .font(.system(size: 9)).foregroundStyle(e.kind == .paid ? theme.positive : theme.secondaryText)
            }
            Spacer()
            Text(Money.format(e.amount, currency: e.currency))
                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                .foregroundStyle(e.kind == .paid ? theme.text : theme.secondaryText)
            if canUndo(e) {
                IconButton(symbol: "arrow.uturn.backward", help: tr("Undo", "Urungkan"), size: 25) { store.undo(e.id) }
            }
        }
        .padding(.vertical, 6.5).padding(.horizontal, 6.5)
    }

    /// Only the latest resolution of a payment can be taken back.
    private func canUndo(_ e: PaymentEvent) -> Bool {
        guard let p = store.ledger.payment(e.paymentId), p.resolvedCount > 0 else { return false }
        return p.occurrence(p.resolvedCount - 1) == e.dueDate
    }

    private static func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = appLocale
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f.string(from: date).capitalized
    }

    private static func total(_ rows: [PaymentEvent]) -> String? {
        let paid = rows.filter { $0.kind == .paid }
        let currencies = Set(paid.map(\.currency))
        guard currencies.count == 1, let c = currencies.first else { return nil }
        return Money.format(paid.reduce(0) { $0 + $1.amount }, currency: c)
    }
}

// MARK: - Footer

private struct FooterMenu: View {
    @EnvironmentObject var sync: SyncService
    @Environment(\.panelTheme) private var theme
    var close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.track).frame(height: 1).padding(.horizontal, 3.5)
            account
            MenuRow(symbol: "plus.circle", title: tr("Add payment", "Tambah pembayaran"), shortcut: "⌘N", key: "n") {
                close(); Windows.showEditor(payment: nil)
            }
            MenuRow(symbol: "gearshape", title: tr("Settings…", "Pengaturan…"), shortcut: "⌘,", key: ",") {
                close(); Windows.showSettings()
            }
            MenuRow(symbol: "rectangle.portrait.and.arrow.right", title: tr("Quit", "Keluar"), shortcut: "⌘Q", key: "q") {
                NSApp.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private var account: some View {
        if let session = sync.session {
            Button {
                close(); Windows.showSettings(tab: .account)
            } label: {
                HStack(spacing: 8.5) {
                    AccountAvatar(session: session, size: 23.5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.email).font(.system(size: 9, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        statusLine
                    }
                    Spacer()
                }
                .padding(.horizontal, 8.5).padding(.vertical, 7.5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Button {
                close(); Windows.showSettings(tab: .account)
            } label: {
                HStack(spacing: 10) {
                    GoogleLogo(size: 17).frame(width: 20)
                    Text(tr("Sign in with Google", "Masuk dengan Google")).font(.system(size: 10.5))
                    Spacer()
                }
                .padding(.horizontal, 8.5).padding(.vertical, 7.5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch sync.state {
        case .syncing:
            HStack(spacing: 3.5) { ProgressView().controlSize(.mini); Text(tr("Syncing…", "Menyinkronkan…")) }
                .font(.system(size: 9)).foregroundStyle(theme.secondaryText)
        case .failed(let why):
            Label(tr("Sync failed", "Sinkron gagal"), systemImage: "exclamationmark.icloud")
                .font(.system(size: 9)).foregroundStyle(theme.critical).help(why)
        default:
            Label(sync.lastSync.map { tr("Synced \($0.formatted(.relative(presentation: .named)))", "Tersinkron \($0.formatted(.relative(presentation: .named)))") } ?? tr("Synced", "Tersinkron"),
                  systemImage: "checkmark.icloud")
                .font(.system(size: 9)).foregroundStyle(theme.secondaryText)
        }
    }
}

private struct MenuRow: View {
    @Environment(\.panelTheme) private var theme
    var symbol: String
    var title: String
    var shortcut: String
    var key: KeyEquivalent
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 11.5)).frame(width: 20)
                Text(title).font(.system(size: 10.5))
                Spacer()
                Text(shortcut).font(.system(size: 9.5)).foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 8.5).padding(.vertical, 7.5)
            .background(RoundedRectangle(cornerRadius: 8.5, style: .continuous).fill(hovering ? theme.track : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(key, modifiers: .command)
    }
}
