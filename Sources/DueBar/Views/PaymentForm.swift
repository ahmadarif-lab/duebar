import DueKit
import SwiftUI

/// Add / edit a payment in its own window.
struct PaymentForm: View {
    @Environment(\.themeAccent) private var accent
    @EnvironmentObject var store: Store
    var original: Payment?
    var onDone: () -> Void

    @State private var name = ""
    @State private var amountText = ""
    @State private var currency = UserDefaults.standard.string(forKey: SettingsKey.defaultCurrency) ?? "IDR"
    @State private var category: PaymentCategory = .utilities
    @State private var due = Date()
    @State private var repeatChoice: RepeatChoice = .monthly
    @State private var customInterval = 2
    @State private var customUnit: RepeatUnit = .week
    @State private var endMode: EndMode = .never
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var endCount = 12
    @State private var offsets: Set<Int> = Set(UserDefaults.standard.defaultOffsets)
    @State private var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var url = ""
    @State private var notes = ""
    @State private var paused = false
    @State private var confirmDelete = false
    @State private var loaded = false

    enum RepeatChoice: String, CaseIterable, Identifiable {
        case once, daily, weekly, monthly, quarterly, semiannual, yearly, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .once: return tr("Does not repeat", "Tidak berulang")
            case .daily: return tr("Every day", "Setiap hari")
            case .weekly: return tr("Every week", "Setiap minggu")
            case .monthly: return tr("Every month", "Setiap bulan")
            case .quarterly: return tr("Every 3 months", "Setiap 3 bulan")
            case .semiannual: return tr("Every 6 months", "Setiap 6 bulan")
            case .yearly: return tr("Every year", "Setiap tahun")
            case .custom: return tr("Custom…", "Atur sendiri…")
            }
        }
    }

    enum EndMode: String, CaseIterable, Identifiable {
        case never, onDate, afterCount
        var id: String { rawValue }
        var title: String {
            switch self {
            case .never: return tr("Never", "Tidak pernah")
            case .onDate: return tr("On date", "Pada tanggal")
            case .afterCount: return tr("After N payments", "Setelah N kali")
            }
        }
    }

    /// Taller only for UI snapshots (DUEBAR_FORM_HEIGHT), so the whole form fits one picture.
    private static var height: CGFloat { CGFloat(Double(ProcessInfo.processInfo.environment["DUEBAR_FORM_HEIGHT"] ?? "") ?? Self.size.height) }
    private var parsedAmount: Decimal? { AmountParser.parse(amountText, currency: currency) }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (parsedAmount ?? -1) >= 0 }
    private var isEditing: Bool { original != nil }

    static let size = CGSize(width: 420, height: 560)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section {
                    TextField(tr("Name", "Nama"), text: $name, prompt: Text(tr("e.g. Electricity, Netflix, Car installment", "mis. Listrik PLN, Netflix, Cicilan motor")))
                    HStack {
                        TextField(tr("Amount", "Jumlah"), text: $amountText, prompt: Text("0"))
                            .multilineTextAlignment(.trailing)
                        Picker("", selection: $currency) {
                            ForEach(currencyChoices, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().frame(width: 84)
                    }
                    if let amount = parsedAmount, amount > 0 {
                        LabeledContent("") { Text(Money.format(amount, currency: currency)).foregroundStyle(.secondary).font(.callout) }
                    }
                }

                Section(tr("Category", "Kategori")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                        ForEach(PaymentCategory.allCases, id: \.self) { c in categoryChip(c) }
                    }
                }

                Section(tr("Schedule", "Jadwal")) {
                    DatePicker(isEditing ? tr("Next due", "Jatuh tempo berikutnya") : tr("Due date", "Jatuh tempo"), selection: $due, displayedComponents: .date)
                    Picker(tr("Repeat", "Ulangi"), selection: $repeatChoice) {
                        ForEach(RepeatChoice.allCases) { Text($0.title).tag($0) }
                    }
                    if repeatChoice == .custom {
                        HStack {
                            Stepper(tr("Every \(customInterval)", "Setiap \(customInterval)"), value: $customInterval, in: 1...365)
                            Picker("", selection: $customUnit) {
                                Text(tr("days", "hari")).tag(RepeatUnit.day)
                                Text(tr("weeks", "minggu")).tag(RepeatUnit.week)
                                Text(tr("months", "bulan")).tag(RepeatUnit.month)
                                Text(tr("years", "tahun")).tag(RepeatUnit.year)
                            }.labelsHidden().frame(width: 100)
                        }
                    }
                    if repeatChoice != .once {
                        Picker(tr("Ends", "Berakhir"), selection: $endMode) {
                            ForEach(EndMode.allCases) { Text($0.title).tag($0) }
                        }
                        if endMode == .onDate { DatePicker(tr("End date", "Tanggal akhir"), selection: $endDate, displayedComponents: .date) }
                        if endMode == .afterCount { Stepper(tr("\(endCount) payments in total", "Total \(endCount) kali"), value: $endCount, in: 1...600) }
                    }
                    if repeatChoice == .monthly || repeatChoice == .quarterly || repeatChoice == .semiannual || repeatChoice == .yearly, Calendar.current.component(.day, from: due) > 28 {
                        Text(tr("Months without this day use their last day.", "Bulan yang tidak punya tanggal ini memakai tanggal terakhirnya."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(tr("Reminders", "Pengingat")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                        ForEach([0, 1, 2, 3, 7, 14], id: \.self) { d in offsetChip(d) }
                    }
                    DatePicker(tr("Remind at", "Ingatkan pukul"), selection: $reminderTime, displayedComponents: .hourAndMinute)
                }

                Section(tr("Details", "Detail")) {
                    TextField(tr("Payment link", "Tautan pembayaran"), text: $url, prompt: Text("https://"))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Notes", "Catatan"))
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $notes)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, -4)
                            if notes.isEmpty {
                                Text(tr("Account number, customer ID…", "Nomor rekening, ID pelanggan…"))
                                    .foregroundStyle(.tertiary).allowsHitTesting(false)
                            }
                        }
                        .frame(minHeight: 64, maxHeight: 120)
                    }
                    if isEditing { Toggle(tr("Paused", "Dijeda"), isOn: $paused) }
                }
            }
            .formStyle(.grouped)
            .controlSize(.small)

            Divider()
            HStack {
                if isEditing {
                    Button(tr("Delete", "Hapus"), role: .destructive) { confirmDelete = true }
                        .confirmationDialog(tr("Delete this payment?", "Hapus pembayaran ini?"), isPresented: $confirmDelete) {
                            Button(tr("Delete", "Hapus"), role: .destructive) {
                                if let id = original?.id { store.delete(id) }
                                onDone()
                            }
                        } message: { Text(tr("Its history is removed too, on every device.", "Riwayatnya ikut terhapus, di semua perangkat.")) }
                }
                Spacer()
                Button(tr("Cancel", "Batal"), action: onDone).keyboardShortcut(.cancelAction)
                Button(isEditing ? tr("Save", "Simpan") : tr("Add", "Tambah"), action: save)
                    .buttonStyle(.borderedProminent).tint(Brand.orange)
                    .keyboardShortcut(.defaultAction).disabled(!isValid)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: Self.size.width, height: Self.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .onAppear(perform: load)
    }

    // The traffic lights sit in the top-left corner (full-size content window).
    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 30)
            Text(isEditing ? tr("Edit payment", "Ubah pembayaran") : tr("New payment", "Pembayaran baru"))
                .font(.system(size: 14.5, weight: .bold))
            Spacer()
        }
        .padding(.leading, 80).padding(.trailing, 16)
        .frame(height: 50)
    }

    private var currencyChoices: [String] {
        var all = Money.commonCurrencies
        if !all.contains(currency) { all.append(currency) }
        return all
    }

    private func categoryChip(_ c: PaymentCategory) -> some View {
        let selected = category == c
        let color = Color(hex: c.colorHex)
        return Button { category = c } label: {
            VStack(spacing: 3) {
                Image(systemName: c.symbol).font(.system(size: 15, weight: .semibold))
                Text(c.title).font(.system(size: 9.5)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(selected ? Color.white : color)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? color : color.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private func offsetChip(_ days: Int) -> some View {
        let on = offsets.contains(days)
        let label = days == 0 ? tr("On the day", "Hari H") : (days == 7 ? tr("1 week", "1 minggu") : (days == 14 ? tr("2 weeks", "2 minggu") : tr("\(days)d before", "H-\(days)")))
        return Button {
            if on { offsets.remove(days) } else { offsets.insert(days) }
        } label: {
            Text(label).font(.system(size: 11.5, weight: on ? .semibold : .regular))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6).padding(.vertical, 5)
                .background(Capsule().fill(on ? accent : Color.secondary.opacity(0.15)))
                .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Load / save

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let p = original else { return }
        name = p.name
        amountText = NSDecimalNumber(decimal: p.amount).stringValue
        currency = p.currency
        category = p.category
        due = (p.nextDue() ?? p.startDate).date(hour: 12)
        offsets = Set(p.reminderOffsets)
        reminderTime = Calendar.current.date(bySettingHour: p.reminderMinute / 60, minute: p.reminderMinute % 60, second: 0, of: Date()) ?? Date()
        url = p.url
        notes = p.notes
        paused = p.paused
        let r = p.repeatRule
        switch (r.unit, r.interval) {
        case (.none, _): repeatChoice = .once
        case (.day, 1): repeatChoice = .daily
        case (.week, 1): repeatChoice = .weekly
        case (.month, 1): repeatChoice = .monthly
        case (.month, 3): repeatChoice = .quarterly
        case (.month, 6): repeatChoice = .semiannual
        case (.year, 1): repeatChoice = .yearly
        default: repeatChoice = .custom; customInterval = r.interval; customUnit = r.unit
        }
        switch r.end {
        case .never: endMode = .never
        case .onDate(let d): endMode = .onDate; endDate = d.date(hour: 12)
        case .afterCount(let n): endMode = .afterCount; endCount = n
        }
    }

    private func buildRule() -> RepeatRule {
        let end: RepeatEnd = repeatChoice == .once ? .never : {
            switch endMode {
            case .never: return .never
            case .onDate: return .onDate(DayStamp(endDate))
            case .afterCount: return .afterCount(endCount)
            }
        }()
        switch repeatChoice {
        case .once: return .none
        case .daily: return RepeatRule(unit: .day, end: end)
        case .weekly: return RepeatRule(unit: .week, end: end)
        case .monthly: return RepeatRule(unit: .month, end: end)
        case .quarterly: return RepeatRule(unit: .month, interval: 3, end: end)
        case .semiannual: return RepeatRule(unit: .month, interval: 6, end: end)
        case .yearly: return RepeatRule(unit: .year, end: end)
        case .custom: return RepeatRule(unit: customUnit, interval: customInterval, end: end)
        }
    }

    private func save() {
        guard isValid, let amount = parsedAmount else { return }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let minute = (comps.hour ?? 9) * 60 + (comps.minute ?? 0)
        let day = DayStamp(due)
        let rule = buildRule()
        var p: Payment
        if var existing = original {
            // Changing the date or the rule starts the series over from the date chosen.
            let dateChanged = existing.nextDue() != day
            let ruleChanged = existing.repeatRule != rule
            existing.repeatRule = rule
            if dateChanged || ruleChanged { existing.reschedule(to: day) }
            p = existing
        } else {
            p = Payment(name: name, amount: amount, startDate: day)
            p.repeatRule = rule
        }
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.amount = amount
        p.currency = currency
        p.category = category
        p.reminderOffsets = offsets.sorted()
        p.reminderMinute = minute
        p.url = url.trimmingCharacters(in: .whitespaces)
        p.notes = notes
        p.paused = paused
        store.save(p)
        onDone()
    }
}
