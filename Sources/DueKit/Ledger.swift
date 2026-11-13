import Foundation

/// One record on the sync wire. `data` is the entity as a JSON string, so
/// the server and other platforms never need to understand the schema.
public struct SyncRecord: Codable, Equatable, Sendable {
    public var kind: String
    public var id: String
    /// Milliseconds since 1970 (client clock); the newer write wins.
    public var updatedAt: Int64
    public var deleted: Bool
    public var data: String?

    public init(kind: String, id: String, updatedAt: Int64, deleted: Bool, data: String?) {
        self.kind = kind
        self.id = id
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.data = data
    }
}

/// Everything the app knows: payments and their history, each stamped with
/// when it last changed and whether the server has seen that change yet.
/// Pure value logic (no I/O) so merge rules are unit-testable.
public struct Ledger: Codable, Equatable, Sendable {
    public struct Stamp<T: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
        public var value: T?          // nil = tombstone
        public var updatedAt: Int64
        public var dirty: Bool
    }

    public var payments: [String: Stamp<Payment>] = [:]
    public var events: [String: Stamp<PaymentEvent>] = [:]
    /// Last server sequence number pulled.
    public var cursor: Int64 = 0

    public init() {}

    public static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    // MARK: Reading

    public var activePayments: [Payment] {
        payments.values.compactMap(\.value).filter { !$0.archived }
    }

    public var allPayments: [Payment] { payments.values.compactMap(\.value) }

    public var history: [PaymentEvent] {
        events.values.compactMap(\.value).sorted { $0.resolvedAt > $1.resolvedAt }
    }

    public func payment(_ id: String) -> Payment? { payments[id]?.value }

    // MARK: Writing

    public mutating func upsert(_ payment: Payment, now: Date = Date()) {
        payments[payment.id] = Stamp(value: payment, updatedAt: Self.nextStamp(payments[payment.id]?.updatedAt, now), dirty: true)
    }

    /// Deleting leaves a tombstone so the deletion syncs; the payment's
    /// history is removed with it.
    public mutating func delete(_ id: String, now: Date = Date()) {
        payments[id] = Stamp(value: nil, updatedAt: Self.nextStamp(payments[id]?.updatedAt, now), dirty: true)
        for (eid, stamp) in events where stamp.value?.paymentId == id {
            events[eid] = Stamp(value: nil, updatedAt: Self.nextStamp(stamp.updatedAt, now), dirty: true)
        }
    }

    public mutating func record(_ event: PaymentEvent, now: Date = Date()) {
        events[event.id] = Stamp(value: event, updatedAt: Self.nextStamp(events[event.id]?.updatedAt, now), dirty: true)
    }

    public mutating func removeEvent(_ id: String, now: Date = Date()) {
        events[id] = Stamp(value: nil, updatedAt: Self.nextStamp(events[id]?.updatedAt, now), dirty: true)
    }

    /// Marks the current occurrence paid or skipped.
    @discardableResult
    public mutating func resolve(_ id: String, _ kind: EventKind, paidAmount: Decimal? = nil, now: Date = Date()) -> PaymentEvent? {
        guard var payment = payment(id), let event = payment.resolve(kind, paidAmount: paidAmount, at: now) else { return nil }
        upsert(payment, now: now)
        record(event, now: now)
        return event
    }

    /// Undoes the most recent resolution of a payment.
    public mutating func undo(_ eventID: String, now: Date = Date()) {
        guard let event = events[eventID]?.value, var payment = payment(event.paymentId), payment.resolvedCount > 0 else { return }
        payment.resolvedCount -= 1
        payment.archived = false
        upsert(payment, now: now)
        removeEvent(eventID, now: now)
    }

    /// A write is always strictly newer than what it replaces, even when
    /// two edits land in the same millisecond or the clock stepped back.
    private static func nextStamp(_ previous: Int64?, _ now: Date) -> Int64 {
        max(millis(now), (previous ?? 0) + 1)
    }

    // MARK: Sync

    public func pendingChanges() -> [SyncRecord] {
        let enc = JSONEncoder()
        func record<T: Codable & Equatable & Sendable>(_ kind: String, _ id: String, _ s: Stamp<T>) -> SyncRecord? {
            guard s.dirty else { return nil }
            let json = s.value.flatMap { try? String(decoding: enc.encode($0), as: UTF8.self) }
            return SyncRecord(kind: kind, id: id, updatedAt: s.updatedAt, deleted: s.value == nil, data: json)
        }
        return payments.compactMap { record("payment", $0.key, $0.value) }
            + events.compactMap { record("event", $0.key, $0.value) }
    }

    public var hasPendingChanges: Bool {
        payments.values.contains(where: \.dirty) || events.values.contains(where: \.dirty)
    }

    /// Clears the dirty flag of records the server accepted, unless they
    /// changed again while the request was in flight.
    public mutating func markPushed(_ pushed: [SyncRecord]) {
        for r in pushed {
            if r.kind == "payment", payments[r.id]?.updatedAt == r.updatedAt { payments[r.id]?.dirty = false }
            if r.kind == "event", events[r.id]?.updatedAt == r.updatedAt { events[r.id]?.dirty = false }
        }
    }

    /// Last-write-wins merge of records pulled from the server.
    public mutating func apply(remote: [SyncRecord]) {
        let dec = JSONDecoder()
        for r in remote {
            switch r.kind {
            case "payment":
                if let local = payments[r.id], local.updatedAt >= r.updatedAt { continue }
                let value = r.deleted ? nil : r.data.flatMap { try? dec.decode(Payment.self, from: Data($0.utf8)) }
                if !r.deleted && value == nil { continue }
                payments[r.id] = Stamp(value: value, updatedAt: r.updatedAt, dirty: false)
            case "event":
                if let local = events[r.id], local.updatedAt >= r.updatedAt { continue }
                let value = r.deleted ? nil : r.data.flatMap { try? dec.decode(PaymentEvent.self, from: Data($0.utf8)) }
                if !r.deleted && value == nil { continue }
                events[r.id] = Stamp(value: value, updatedAt: r.updatedAt, dirty: false)
            default: continue
            }
        }
    }

    /// After signing in on a device that already has data, everything local
    /// is pushed once.
    public mutating func markAllDirty() {
        for k in payments.keys { payments[k]?.dirty = true }
        for k in events.keys { events[k]?.dirty = true }
    }
}

/// One month of history, newest first.
public struct HistoryMonth: Identifiable, Equatable, Sendable {
    /// year * 100 + month, so it sorts correctly across years (202701 > 202611).
    public var id: Int
    public var events: [PaymentEvent]
    public var date: Date { events.first?.resolvedAt ?? Date(timeIntervalSince1970: 0) }
}

public extension Ledger {
    /// History grouped by calendar month, months and the events in them newest first.
    func historyByMonth(limit: Int? = nil, calendar: Calendar = .current) -> [HistoryMonth] {
        let events = limit.map { Array(history.prefix($0)) } ?? history
        let groups = Dictionary(grouping: events) { e -> Int in
            let c = calendar.dateComponents([.year, .month], from: e.resolvedAt)
            return (c.year ?? 0) * 100 + (c.month ?? 0)
        }
        return groups.keys.sorted(by: >).map { HistoryMonth(id: $0, events: groups[$0] ?? []) }
    }
}
