import Foundation

public enum AmountParser {
    /// Currencies people write without minor units: "1.250.000" means one
    /// million two hundred fifty thousand, never 1.25.
    public static let wholeCurrencies: Set<String> = ["IDR", "JPY", "KRW", "VND", "CLP", "ISK", "HUF"]

    /// Reads what a person types: "Rp 1.250.000", "1,250,000.50", "12,5".
    /// Returns nil when there's no number in it.
    public static func parse(_ text: String, currency: String) -> Decimal? {
        let allowed = Set("0123456789.,")
        let cleaned = String(text.filter { allowed.contains($0) })
        guard cleaned.contains(where: \.isNumber) else { return nil }
        let digitsOnly = cleaned.filter(\.isNumber)

        let lastSep = cleaned.lastIndex(where: { $0 == "." || $0 == "," })
        guard let sepIndex = lastSep else { return Decimal(string: digitsOnly) }
        let after = cleaned[cleaned.index(after: sepIndex)...].filter(\.isNumber)
        let sepCount = cleaned.filter { $0 == "." || $0 == "," }.count
        let before = cleaned[..<sepIndex].filter(\.isNumber)

        if wholeCurrencies.contains(currency) {
            // A short tail after the last separator is a fraction only if it is the single separator and not three digits.
            if sepCount == 1, !after.isEmpty, after.count <= 2 {
                return Decimal(string: "\(before).\(after)", locale: Locale(identifier: "en_US_POSIX"))
            }
            return Decimal(string: digitsOnly)
        }
        let kinds = Set(cleaned.filter { $0 == "." || $0 == "," })
        let decimalPoint: Bool
        if kinds.count == 2 {
            decimalPoint = true                 // "1.250,50": the last separator is the decimal point
        } else {
            decimalPoint = sepCount == 1 && after.count != 3   // "1,250" is grouping, "12,5" a fraction
        }
        if decimalPoint, !after.isEmpty {
            return Decimal(string: "\(before).\(after)", locale: Locale(identifier: "en_US_POSIX"))
        }
        return Decimal(string: digitsOnly)
    }
}
