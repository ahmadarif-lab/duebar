import DueKit
import SwiftUI

struct DropdownContent: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncService
    @ObservedObject private var updater = Updater.shared
    @Environment(\.panelTheme) private var theme
    var close: () -> Void
    var initialTab: Tab = .upcoming

    enum Tab { case upcoming, history }
    @State private var tab: Tab

    @State private var undo: PaymentEvent?
    @State private var undoTask: Task<Void, Never>?

    init(close: @escaping () -> Void, initialTab: Tab = .upcoming) {
        self.close = close
        self.initialTab = initialTab
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 6) {
            SummaryCard(summary: store.summary)
            tabBar
            Group {
                switch tab {
                case .upcoming: UpcomingList(markPaid: markPaid(_:), close: close)
                case .history: HistoryList()
                }
            }
            if let undo { undoBar(undo) }
            if let release = updater.availableUpdate { updateBar(release) }
            FooterBar(close: close)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(tr("Upcoming", "Mendatang"), .upcoming)
            tabButton(tr("History", "Riwayat"), .history)
            Spacer()
            Button {
                close()
                Windows.showEditor(payment: nil)
            } label: {
                Label(tr("Add", "Tambah"), systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(theme.primary))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func tabButton(_ title: String, _ value: Tab) -> some View {
        Button { tab = value } label: {
            Text(title)
                .font(.system(size: 12, weight: tab == value ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(tab == value ? theme.track : .clear))
                .foregroundStyle(tab == value ? theme.text : theme.secondaryText)
        }
        .buttonStyle(.plain)
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

    private func updateBar(_ release: Updater.Release) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(theme.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("DueBar v\(release.version) is available", "DueBar v\(release.version) tersedia")).font(.system(size: 12, weight: .medium))
                if let progress = updater.progressText {
                    Text(progress).font(.system(size: 11)).foregroundStyle(theme.secondaryText)
                } else if let error = updater.errorMessage {
                    Text(error).font(.system(size: 11)).foregroundStyle(theme.critical).lineLimit(1)
                }
            }
            Spacer()
            if updater.isUpdating {
                ProgressView().controlSize(.small)
            } else {
                Button(tr("Update", "Perbarui")) { Task { await updater.update() } }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.primary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.section))
    }

    private func undoBar(_ event: PaymentEvent) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.positive)
            Text(tr("\(event.name) marked paid", "\(event.name) ditandai lunas")).font(.system(size: 12)).lineLimit(1)
            Spacer()
            Button(tr("Undo", "Urungkan")) {
                store.undo(event.id)
                undo = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.section))
        .transition(.opacity)
    }
}

// MARK: - Summary

struct SummaryCard: View {
    @Environment(\.panelTheme) private var theme
    var summary: MonthSummary

    var body: some View {
        let month = { () -> String in
            let f = DateFormatter()
            f.locale = appLocale
            f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
            return f.string(from: Date()).capitalized
        }()
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(month.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.header)
                Spacer()
                if summary.totalCount > 0 {
                    Text(tr("\(summary.paidCount) of \(summary.totalCount) paid", "\(summary.paidCount) dari \(summary.totalCount) lunas"))
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(theme.secondaryText)
                }
            }
            if summary.currencies.isEmpty {
                Text(tr("Nothing due this month", "Tidak ada tagihan bulan ini")).font(.system(size: 13)).foregroundStyle(theme.secondaryText)
            } else {
                ForEach(summary.currencies, id: \.self) { currency in
                    let remaining = summary.remaining[currency] ?? 0
                    let paid = summary.paid[currency] ?? 0
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Money.format(remaining, currency: currency))
                                .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(tr("left to pay", "sisa dibayar")).font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                        }
                        if paid > 0 {
                            Text(tr("\(Money.format(paid, currency: currency)) already paid", "\(Money.format(paid, currency: currency)) sudah dibayar"))
                                .font(.system(size: 11.5)).foregroundStyle(theme.positive)
                        }
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.track)
                        Capsule().fill(theme.positive).frame(width: max(geo.size.width * summary.progress, summary.progress > 0 ? 6 : 0))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.section))
    }
}

// MARK: - Upcoming

struct UpcomingList: View {
    @EnvironmentObject var store: Store
    @Environment(\.panelTheme) private var theme
    var markPaid: (String) -> Void
    var close: () -> Void

    var body: some View {
        let agenda = store.agenda
        if agenda.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundStyle(theme.positive)
                Text(tr("No payments yet", "Belum ada pembayaran")).font(.system(size: 14, weight: .semibold))
                Text(tr("Add bills, subscriptions and installments to get reminded before they're due.",
                        "Tambahkan tagihan, langganan, dan cicilan supaya diingatkan sebelum jatuh tempo."))
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center)
            }
            .padding(.vertical, 26).padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.section))
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    group(tr("Overdue", "Terlambat"), agenda.overdue, color: theme.critical)
                    group(tr("Today", "Hari ini"), agenda.today, color: theme.warning)
                    group(tr("This week", "Minggu ini"), agenda.week)
                    group(tr("Later", "Nanti"), agenda.later)
                    if !agenda.paused.isEmpty { pausedBox(agenda.paused) }
                    if agenda.attentionCount + agenda.week.count + agenda.later.count == 0 && agenda.paused.isEmpty == false { EmptyView() }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 400)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [AgendaItem], color: Color? = nil) -> some View {
        if !items.isEmpty {
            SectionBox(title, color: color, trailing: total(items)) {
                VStack(spacing: 2) {
                    ForEach(items) { PaymentRow(item: $0, markPaid: markPaid, close: close) }
                }
            }
        }
    }

    private func pausedBox(_ payments: [Payment]) -> some View {
        SectionBox(tr("Paused", "Dijeda")) {
            ForEach(payments) { p in
                HStack(spacing: 8) {
                    CategoryBadge(category: p.category, size: 24).opacity(0.5)
                    Text(p.name).font(.system(size: 12.5)).foregroundStyle(theme.secondaryText).lineLimit(1)
                    Spacer()
                    Button(tr("Resume", "Lanjutkan")) { store.setPaused(p.id, false) }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.primary)
                }
            }
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
            CategoryBadge(category: p.category)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(DueText.relative(item.status)).foregroundStyle(statusColor)
                    Text("·").foregroundStyle(theme.secondaryText)
                    Text(DueText.date(item.due)).foregroundStyle(theme.secondaryText)
                    if p.repeatRule.isRepeating {
                        Image(systemName: "repeat").font(.system(size: 9)).foregroundStyle(theme.secondaryText)
                    }
                }
                .font(.system(size: 11)).lineLimit(1)
            }
            Spacer(minLength: 6)
            if hovering {
                IconButton(symbol: "checkmark.circle", help: tr("Mark as paid", "Tandai lunas"), tint: theme.positive) { markPaid(p.id) }
                menu
            } else {
                Text(Money.format(p.amount, currency: p.currency)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? theme.track.opacity(0.6) : .clear))
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
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.secondaryText)
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26)
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

// MARK: - History

struct HistoryList: View {
    @EnvironmentObject var store: Store
    @Environment(\.panelTheme) private var theme

    var body: some View {
        let events = Array(store.history.prefix(80))
        if events.isEmpty {
            Text(tr("Paid payments will show up here.", "Pembayaran yang sudah lunas muncul di sini."))
                .font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity).padding(.vertical, 26)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.section))
        } else {
            let groups = Dictionary(grouping: events) { String($0.resolvedAt.formatted(.dateTime.year().month(.twoDigits))) }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(groups.keys.sorted(by: >), id: \.self) { key in
                        let rows = groups[key] ?? []
                        SectionBox(Self.monthTitle(rows[0].resolvedAt), trailing: Self.total(rows)) {
                            ForEach(rows) { row($0) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 400)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ e: PaymentEvent) -> some View {
        HStack(spacing: 10) {
            CategoryBadge(category: e.category, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text("\(e.kind == .paid ? tr("Paid", "Lunas") : tr("Skipped", "Dilewati")) · \(DueText.date(DayStamp(e.resolvedAt)))")
                    .font(.system(size: 11)).foregroundStyle(e.kind == .paid ? theme.positive : theme.secondaryText)
            }
            Spacer()
            Text(Money.format(e.amount, currency: e.currency))
                .font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(e.kind == .paid ? theme.text : theme.secondaryText)
            if canUndo(e) {
                IconButton(symbol: "arrow.uturn.backward", help: tr("Undo", "Urungkan")) { store.undo(e.id) }
            }
        }
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

struct FooterBar: View {
    @EnvironmentObject var sync: SyncService
    @Environment(\.panelTheme) private var theme
    var close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let session = sync.session {
                AccountAvatar(session: session, size: 24)
            }
            syncLabel
            Spacer(minLength: 4)
            IconButton(symbol: "gearshape", help: tr("Settings", "Pengaturan")) { close(); Windows.showSettings() }
            IconButton(symbol: "power", help: tr("Quit DueBar", "Keluar dari DueBar")) { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var syncLabel: some View {
        if let session = sync.session {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.email)
                    .font(.system(size: 11.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                statusLine
            }
        } else {
            Button {
                close(); Windows.showSettings(tab: .account)
            } label: {
                HStack(spacing: 7) {
                    GoogleLogo(size: 15)
                    Text(tr("Sign in with Google", "Masuk dengan Google")).font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(theme.text)
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch sync.state {
        case .syncing:
            HStack(spacing: 4) { ProgressView().controlSize(.mini); Text(tr("Syncing…", "Menyinkronkan…")) }
                .font(.system(size: 10.5)).foregroundStyle(theme.secondaryText)
        case .failed(let why):
            Label(tr("Sync failed", "Sinkron gagal"), systemImage: "exclamationmark.icloud")
                .font(.system(size: 10.5)).foregroundStyle(theme.critical).help(why)
        default:
            Label(sync.lastSync.map { tr("Synced \($0.formatted(.relative(presentation: .named)))", "Tersinkron \($0.formatted(.relative(presentation: .named)))") } ?? tr("Synced", "Tersinkron"),
                  systemImage: "checkmark.icloud")
                .font(.system(size: 10.5)).foregroundStyle(theme.secondaryText)
        }
    }
}
