import DueKit
import Foundation

/// The app's data: one `Ledger` persisted as JSON in Application Support.
/// Every change is saved atomically, then the sync engine and the
/// notification scheduler are told.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var ledger: Ledger
    /// Bumped at midnight and on wake so "today" views recompute.
    @Published private(set) var dayTick = 0
    var onChange: (() -> Void)?
    /// Fired after a sync brought in remote changes (reschedule reminders, redraw).
    var onChangeAfterRemote: (() -> Void)?

    private let fileURL: URL

    nonisolated static var defaultDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["DUEBAR_DATA_DIR"], !dir.isEmpty { return URL(fileURLWithPath: dir, isDirectory: true) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DueBar", isDirectory: true)
    }

    init(directory: URL = Store.defaultDirectory) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("ledger.json")
        if let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode(Ledger.self, from: data) {
            ledger = loaded
        } else {
            ledger = Ledger()
            // A file that exists but can't be read is kept aside, never overwritten.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.moveItem(at: fileURL, to: directory.appendingPathComponent("ledger.corrupt-\(Int(Date().timeIntervalSince1970)).json"))
            }
        }
    }

    // MARK: Derived

    var agenda: Agenda {
        _ = dayTick
        return Agenda.make(payments: ledger.allPayments, horizonDays: UserDefaults.standard.integer(forKey: SettingsKey.horizonDays))
    }

    var summary: MonthSummary {
        _ = dayTick
        return MonthSummary.make(ledger: ledger)
    }

    var history: [PaymentEvent] { ledger.history }
    var finished: [Payment] { ledger.allPayments.filter(\.archived).sorted { $0.name.lowercased() < $1.name.lowercased() } }

    func refreshDay() { dayTick += 1; onChange?() }

    // MARK: Changes

    func mutate(_ change: (inout Ledger) -> Void) {
        change(&ledger)
        save()
        onChange?()
    }

    func save(_ payment: Payment) { mutate { $0.upsert(payment) } }
    func delete(_ id: String) { mutate { $0.delete(id) } }

    @discardableResult
    func resolve(_ id: String, _ kind: EventKind, paidAmount: Decimal? = nil) -> PaymentEvent? {
        var event: PaymentEvent?
        mutate { event = $0.resolve(id, kind, paidAmount: paidAmount) }
        return event
    }

    func undo(_ eventID: String) { mutate { $0.undo(eventID) } }
    func setPaused(_ id: String, _ paused: Bool) {
        guard var p = ledger.payment(id) else { return }
        p.paused = paused
        save(p)
    }

    /// Applies what the server sent. Not a user edit, so no push follows.
    func applyRemote(_ records: [SyncRecord], cursor: Int64, pushed: [SyncRecord]) {
        ledger.markPushed(pushed)
        ledger.apply(remote: records)
        ledger.cursor = cursor
        save()
        objectWillChange.send()
    }

    func resetCursorAndPushAll() {
        ledger.cursor = 0
        ledger.markAllDirty()
        save()
    }

    func replaceAll(_ newLedger: Ledger) {
        ledger = newLedger
        save()
        onChange?()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
