import DueKit
import Foundation

enum Money {
    /// "Rp1.250.000" / "$12.50". Currencies without minor units in daily use
    /// (IDR, JPY, KRW, VND) drop the decimals unless the amount has them.
    static func format(_ amount: Decimal, currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        // Rupiah always reads "Rp 1.250.000", whatever the UI language: id_ID drops the space, en_US writes "IDR".
        f.locale = currency == "IDR" ? Locale(identifier: "en_ID") : appLocale
        let noMinor: Set<String> = ["IDR", "JPY", "KRW", "VND", "CLP", "ISK", "HUF"]
        let fractional = (amount as NSDecimalNumber).doubleValue.truncatingRemainder(dividingBy: 1) != 0
        let digits = noMinor.contains(currency) && !fractional ? 0 : (noMinor.contains(currency) ? 2 : nil)
        if let digits { f.minimumFractionDigits = digits; f.maximumFractionDigits = digits }
        return f.string(from: amount as NSDecimalNumber) ?? "\(currency) \(amount)"
    }

    /// For totals and converted amounts: rounded to the currency's usual precision first (IDR to
    /// whole rupiah, others to cents), so a conversion never shows "Rp 242.088,50".
    static func formatTotal(_ amount: Decimal, currency: String) -> String {
        let noMinor: Set<String> = ["IDR", "JPY", "KRW", "VND", "CLP", "ISK", "HUF"]
        var value = amount
        var source = amount
        NSDecimalRound(&value, &source, noMinor.contains(currency) ? 0 : 2, .plain)
        return format(value, currency: currency)
    }

    /// Adds amounts in different currencies as one amount in `currency` (see ExchangeRates.total).
    /// Without rates only amounts already in `currency` count and the total is incomplete.
    static func total(_ amounts: [(Decimal, String)], in currency: String, rates: ExchangeRates?) -> (total: Decimal, complete: Bool) {
        let entries = amounts.map { (amount: $0.0, currency: $0.1) }
        if let rates { return rates.total(of: entries, in: currency) }
        let same = entries.filter { $0.currency == currency }
        return (same.reduce(0) { $0 + $1.amount }, same.count == entries.count)
    }

    static let commonCurrencies = ["IDR", "USD", "EUR", "SGD", "MYR", "JPY", "GBP", "AUD", "SAR"]
}

enum DueText {
    static func relative(_ status: DueStatus) -> String {
        switch status {
        case .overdue(let d): return d == 1 ? tr("1 day late", "Telat 1 hari") : tr("\(d) days late", "Telat \(d) hari")
        case .today: return tr("Today", "Hari ini")
        case .upcoming(let d):
            if d == 1 { return tr("Tomorrow", "Besok") }
            return tr("In \(d) days", "\(d) hari lagi")
        }
    }

    /// "now", "21 minutes ago" in the app's language, not the system's.
    static func ago(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = appLocale
        f.unitsStyle = .full
        f.dateTimeStyle = .named
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func date(_ day: DayStamp) -> String {
        let f = DateFormatter()
        f.locale = appLocale
        f.setLocalizedDateFormatFromTemplate(day.year == DayStamp.today().year ? "d MMM" : "d MMM yyyy")
        return f.string(from: day.date())
    }

    static func repeatText(_ rule: RepeatRule) -> String {
        guard rule.isRepeating else { return tr("One time", "Sekali") }
        let n = rule.interval
        switch (rule.unit, n) {
        case (.day, 1): return tr("Daily", "Harian")
        case (.week, 1): return tr("Weekly", "Mingguan")
        case (.month, 1): return tr("Monthly", "Bulanan")
        case (.month, 3): return tr("Every 3 months", "Tiap 3 bulan")
        case (.month, 6): return tr("Every 6 months", "Tiap 6 bulan")
        case (.year, 1): return tr("Yearly", "Tahunan")
        case (.day, _): return tr("Every \(n) days", "Tiap \(n) hari")
        case (.week, _): return tr("Every \(n) weeks", "Tiap \(n) minggu")
        case (.month, _): return tr("Every \(n) months", "Tiap \(n) bulan")
        case (.year, _): return tr("Every \(n) years", "Tiap \(n) tahun")
        case (.none, _): return tr("One time", "Sekali")
        }
    }
}

extension PaymentCategory {
    var title: String {
        switch self {
        case .utilities: return tr("Utilities", "Listrik & air")
        case .internet: return tr("Internet & phone", "Internet & pulsa")
        case .subscription: return tr("Subscription", "Langganan")
        case .rent: return tr("Rent & housing", "Sewa & hunian")
        case .loan: return tr("Loan & installment", "Cicilan")
        case .insurance: return tr("Insurance", "Asuransi")
        case .tax: return tr("Tax", "Pajak")
        case .credit: return tr("Credit card", "Kartu kredit")
        case .education: return tr("Education", "Pendidikan")
        case .other: return tr("Other", "Lainnya")
        }
    }
}

extension PaymentCategory {
    /// One short word or two for the category chips, so every label fits at the same size.
    var shortTitle: String {
        switch self {
        case .utilities: return tr("Utilities", "Listrik")
        case .internet: return tr("Internet", "Internet")
        case .subscription: return tr("Subscription", "Langganan")
        case .rent: return tr("Housing", "Hunian")
        case .loan: return tr("Loan", "Cicilan")
        case .insurance: return tr("Insurance", "Asuransi")
        case .tax: return tr("Tax", "Pajak")
        case .credit: return tr("Card", "Kartu")
        case .education: return tr("Education", "Sekolah")
        case .other: return tr("Other", "Lainnya")
        }
    }
}
