import Foundation

public struct AgendaItem: Identifiable, Equatable, Sendable {
    public var payment: Payment
    public var due: DayStamp
    public var status: DueStatus
    public var id: String { payment.id }
}

/// The list the menu bar shows: what's late, what's due today, this week, later.
public struct Agenda: Equatable, Sendable {
    public var overdue: [AgendaItem] = []
    public var today: [AgendaItem] = []
    public var week: [AgendaItem] = []
    public var later: [AgendaItem] = []
    public var paused: [Payment] = []

    public var isEmpty: Bool { overdue.isEmpty && today.isEmpty && week.isEmpty && later.isEmpty && paused.isEmpty }
    public var attentionCount: Int { overdue.count + today.count }
    /// What needs attention now: overdue, due today, or inside the payment's own reminder window.
    /// A payment due in 18 days with reminders at 1, 2 and 7 days isn't "soon" yet.
    public var dueSoon: [AgendaItem] { (overdue + today + week + later).filter(Self.isDueSoon) }
    /// The number on the menu bar badge.
    public var dueSoonCount: Int { dueSoon.count }

    public static func isDueSoon(_ item: AgendaItem) -> Bool {
        switch item.status {
        case .overdue, .today: return true
        case .upcoming(let days): return days <= item.payment.reminderWindowDays
        }
    }
    /// First thing the menu bar should mention.
    public var next: AgendaItem? { (overdue + today + week + later).first }

    public static func make(payments: [Payment], today: DayStamp = .today(), horizonDays: Int = 60, calendar: Calendar = .current) -> Agenda {
        var a = Agenda()
        for p in payments where !p.archived {
            if p.paused { a.paused.append(p); continue }
            guard let due = p.nextDue(calendar: calendar), let status = p.status(today: today, calendar: calendar) else { continue }
            let item = AgendaItem(payment: p, due: due, status: status)
            switch status {
            case .overdue: a.overdue.append(item)
            case .today: a.today.append(item)
            case .upcoming(let d):
                if d <= 7 { a.week.append(item) } else if d <= horizonDays { a.later.append(item) }
            }
        }
        let order: (AgendaItem, AgendaItem) -> Bool = { ($0.due, $0.payment.name.lowercased()) < ($1.due, $1.payment.name.lowercased()) }
        a.overdue.sort(by: order); a.today.sort(by: order); a.week.sort(by: order); a.later.sort(by: order)
        a.paused.sort { $0.name.lowercased() < $1.name.lowercased() }
        return a
    }
}

/// What is owed soon (overdue, due today, or inside its reminder window) as one number in the main
/// currency. Amounts in other currencies are converted with the exchange rates; any currency the
/// rates don't cover is kept apart in `unconverted` so nothing is silently dropped.
public struct Outstanding: Equatable, Sendable {
    public var currency: String
    public var total: Decimal = 0
    public var count = 0
    /// True when part of `total` came from a conversion.
    public var includesConverted = false
    public var unconverted: [String: Decimal] = [:]

    public init(currency: String) { self.currency = currency }
}

public extension Agenda {
    /// The total of everything that is due soon (see `dueSoon`), in `currency`.
    func outstanding(in currency: String, rates: ExchangeRates?) -> Outstanding {
        var o = Outstanding(currency: currency)
        for item in dueSoon {
            o.count += 1
            let p = item.payment
            if p.currency == currency {
                o.total += p.amount
            } else if let converted = rates?.convert(p.amount, from: p.currency, to: currency) {
                o.total += converted
                o.includesConverted = true
            } else {
                o.unconverted[p.currency, default: 0] += p.amount
            }
        }
        return o
    }
}

/// Paid and still-to-pay totals for one calendar month, per currency.
public struct MonthSummary: Equatable, Sendable {
    public var paid: [String: Decimal] = [:]
    public var remaining: [String: Decimal] = [:]
    public var paidCount = 0
    public var remainingCount = 0

    public var currencies: [String] { Set(paid.keys).union(remaining.keys).sorted() }
    public var totalCount: Int { paidCount + remainingCount }
    /// 0...1 by number of payments, for the progress bar.
    public var progress: Double { totalCount == 0 ? 0 : Double(paidCount) / Double(totalCount) }

    public static func make(ledger: Ledger, today: DayStamp = .today(), calendar: Calendar = .current) -> MonthSummary {
        var s = MonthSummary()
        func inMonth(_ d: DayStamp) -> Bool { d.year == today.year && d.month == today.month }
        for event in ledger.history where event.kind == .paid && inMonth(event.dueDate) {
            s.paid[event.currency, default: 0] += event.amount
            s.paidCount += 1
        }
        let monthEnd = DayStamp(year: today.year, month: today.month,
                                day: DayStamp.daysInMonth(year: today.year, month: today.month, calendar: calendar))
        for p in ledger.activePayments where !p.paused {
            // Late ones from earlier months count too: they still have to be paid.
            for _ in p.upcoming(limit: 40, until: monthEnd, calendar: calendar) {
                s.remaining[p.currency, default: 0] += p.amount
                s.remainingCount += 1
            }
        }
        return s
    }
}

public struct PlannedReminder: Equatable, Sendable {
    public var paymentID: String
    public var name: String
    public var amount: Decimal
    public var currency: String
    public var due: DayStamp
    public var offset: Int
    public var fire: Date
}

public enum ReminderPlanner {
    /// The next reminders to hand to the system, soonest first. macOS keeps
    /// at most 64 pending notifications, so the plan is capped.
    public static func plan(payments: [Payment], now: Date = Date(), limit: Int = 60, calendar: Calendar = .current) -> [PlannedReminder] {
        let today = DayStamp(now, calendar: calendar)
        var out: [PlannedReminder] = []
        for p in payments where !p.archived && !p.paused {
            let hour = p.reminderMinute / 60, minute = p.reminderMinute % 60
            for due in p.upcoming(limit: 6, calendar: calendar) {
                for offset in Set(p.reminderOffsets) where offset >= 0 {
                    let fire = due.adding(days: -offset, calendar: calendar).date(hour: hour, minute: minute, calendar: calendar)
                    if fire > now {
                        out.append(PlannedReminder(paymentID: p.id, name: p.name, amount: p.amount, currency: p.currency, due: due, offset: offset, fire: fire))
                    }
                }
            }
            // Late and still unpaid: nudge once a day for the next three days.
            if case .overdue = p.status(today: today, calendar: calendar), let due = p.nextDue(calendar: calendar) {
                for n in 0..<3 {
                    let fire = today.adding(days: n, calendar: calendar).date(hour: hour, minute: minute, calendar: calendar)
                    if fire > now {
                        out.append(PlannedReminder(paymentID: p.id, name: p.name, amount: p.amount, currency: p.currency, due: due, offset: -1, fire: fire))
                    }
                }
            }
        }
        out.sort { ($0.fire, $0.name) < ($1.fire, $1.name) }
        return Array(out.prefix(limit))
    }
}
