import Foundation

public enum Export {
    /// Payments and history as CSV for spreadsheets.
    public static func csv(ledger: Ledger) -> String {
        func esc(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        func num(_ d: Decimal) -> String { NSDecimalNumber(decimal: d).stringValue }
        var out = "type,name,amount,currency,category,due_date,repeat,status,paid_at\n"
        for p in ledger.allPayments.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }) {
            let rule = p.repeatRule.isRepeating ? "\(p.repeatRule.unit.rawValue)x\(p.repeatRule.interval)" : "once"
            let due = p.nextDue().map(\.description) ?? ""
            let status = p.archived ? "finished" : (p.paused ? "paused" : "active")
            out += ["payment", esc(p.name), num(p.amount), p.currency, p.category.rawValue, due, rule, status, ""].joined(separator: ",") + "\n"
        }
        let iso = ISO8601DateFormatter()
        for e in ledger.history.reversed() {
            out += ["history", esc(e.name), num(e.amount), e.currency, e.category.rawValue, e.dueDate.description, "", e.kind.rawValue, iso.string(from: e.resolvedAt)].joined(separator: ",") + "\n"
        }
        return out
    }

    /// Full backup that can be restored on any device.
    public static func backupJSON(ledger: Ledger) throws -> Data {
        struct Backup: Codable { var version = 1; var payments: [Payment]; var history: [PaymentEvent] }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(Backup(payments: ledger.allPayments, history: ledger.history))
    }

    /// Reads a backup into an existing ledger; records already present are replaced by the backup's version.
    public static func restore(_ data: Data, into ledger: inout Ledger) throws -> Int {
        struct Backup: Codable { var version: Int; var payments: [Payment]; var history: [PaymentEvent] }
        let backup = try JSONDecoder().decode(Backup.self, from: data)
        for p in backup.payments { ledger.upsert(p) }
        for e in backup.history { ledger.record(e) }
        return backup.payments.count
    }
}
